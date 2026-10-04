# frozen_string_literal: true

require_relative "serializer"
require_relative "compile_all_result"
require_relative "code_gen/serializer_cache"

module Panko
  COMPILE_ALL_MODES = %i[json hash].freeze

  # Compiles every loaded Panko::Serializer subclass that declares at least
  # one field: the base for each mode, plus a specialized variant for each
  # model declared with {Serializer.models}. Call it at boot, after eager
  # load and before forking workers, so workers inherit the compiled
  # classes instead of compiling them on their first requests. Warm-up
  # calls belong after it: a compile defines constants, which throws away
  # YJIT code that reads the same constant names. Safe to repeat: entries
  # already compiled are cache hits.
  #
  # @param modes [Array<Symbol>] a non-empty subset of +[:json, :hash]+
  # @return [Panko::CompileAllResult]
  # @raise [ArgumentError] when +modes+ is empty or holds an unknown mode
  def self.compile_all(modes: COMPILE_ALL_MODES)
    if modes.empty? || !(modes - COMPILE_ALL_MODES).empty?
      raise ArgumentError, "compile_all modes: expected a non-empty subset of #{COMPILE_ALL_MODES.inspect}, got #{modes.inspect}"
    end

    compiled = []
    without_models = []
    not_specialized = {}
    errors = {}
    cache = CodeGen::SerializerCache

    compile_all_serializers.each do |serializer|
      models = serializer._cg_models
      missed = []
      begin
        modes.each do |mode|
          cache.instance_pool(serializer, mode)
          models.each do |model|
            cache.variant_pool(serializer, mode, model)
            missed << model unless cache.specialized?(serializer, mode, model)
          end
        end
      rescue => error
        errors[serializer] = error
        next
      end

      if models.empty?
        without_models << serializer
      elsif missed.empty?
        compiled << serializer
      else
        not_specialized[serializer] = missed.uniq
      end
    end

    CompileAllResult.new(
      compiled: compiled.freeze,
      without_models: without_models.freeze,
      not_specialized: not_specialized.freeze,
      errors: errors.freeze
    )
  end

  # Every user serializer class, walked before any compile so the
  # Generated Classes a compile adds are not visited. Generated Classes
  # subclass the user serializer and are told apart by +serialize_one+,
  # which only the generator defines. Serializers without fields (abstract
  # bases) are left out.
  def self.compile_all_serializers
    found = []
    pending = Panko::Serializer.subclasses
    until pending.empty?
      serializer = pending.shift
      next if serializer.method_defined?(:serialize_one)
      pending.concat(serializer.subclasses)
      next if serializer._cg_attributes.empty? &&
        serializer._cg_method_attributes.empty? &&
        serializer._cg_associations.empty?
      found << serializer
    end
    found
  end
  private_class_method :compile_all_serializers
end
