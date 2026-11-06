# frozen_string_literal: true

module Panko::CodeGen
  class Dump
    def initialize(descriptor, output:, config:, path:,
      validator: Validators::Validator.new, generator: Generator.new)
      @descriptor = descriptor
      @output = output
      @config = config
      @path = path
      @validator = validator
      @generator = generator
    end

    def dump
      validate_path!
      @validator.validate(@descriptor, output: @output, config: @config)
      if @descriptor.associations.empty?
        write_flat
      else
        write_fan_out
      end
      @path
    end

    private

    def validate_path!
      unless @path.is_a?(String)
        raise ArgumentError,
          "path: must be a String, got #{@path.class} (#{@path.inspect})"
      end
      raise ArgumentError, "path: must not be empty" if @path.empty?
    end

    def write_flat
      source = @generator.emit(@descriptor, output: @output, config: @config)
      File.write(@path, source)
    end

    # Inner file paths are derived, never taken from the caller: +require_relative+
    # lines name derived basenames. When the root is in a cycle, its peers
    # +require_relative+ it by its derived name, so +path:+ must use that basename.
    def write_fan_out
      directory = File.dirname(@path)
      Generators::Fanout.emit_files(@descriptor, output: @output, config: @config).each do |file|
        target = file[:descriptor].equal?(@descriptor) ? @path : File.join(directory, file[:basename])
        File.write(target, file[:source])
      end
    end
  end
end
