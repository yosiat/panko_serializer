# frozen_string_literal: true

module Fixtures
  # Stand-in for the user serializer class a Panko-built Descriptor always
  # carries as its +parent_class+. Engine fixtures that don't exercise
  # Symbol-body dispatch still need *a* parent for the required
  # +Descriptor#parent_class+ field, so they subclass this empty base and
  # the emitted +class X < Fixtures::BaseSerializer+ header stays
  # deterministic across the snapshot suite.
  class BaseSerializer
  end
end
