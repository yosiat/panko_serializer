# frozen_string_literal: true

module Panko
  # What one {Panko.compile_all} call compiled. Every serializer it visited
  # is in exactly one of the four fields.
  #
  # @!attribute [r] compiled
  #   @return [Array<Class>] serializers with the base and a specialized
  #     variant for every declared model, in every requested mode
  # @!attribute [r] without_models
  #   @return [Array<Class>] serializers that declare no {Serializer.models}:
  #     only the base is compiled, and they specialize on first request
  # @!attribute [r] not_specialized
  #   @return [Hash{Class => Array<Class>}] serializer to the declared models
  #     that got no specialized variant (not an ActiveRecord class, a compile
  #     error, capacity reached, or auto-specialization disabled). Records of
  #     those models serialize through the base.
  # @!attribute [r] errors
  #   @return [Hash{Class => StandardError}] serializers whose base compile
  #     raised; the same error raises again on their first serialize
  CompileAllResult = Data.define(:compiled, :without_models, :not_specialized, :errors)
end
