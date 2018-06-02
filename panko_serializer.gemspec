# coding: utf-8
# frozen_string_literal: true
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "panko/version"

Gem::Specification.new do |spec|
  spec.name          = "panko_serializer"
  spec.version       = Panko::VERSION
  spec.authors       = ["Yosi Attias"]
  spec.email         = ["yosy101@gmail.com"]

  spec.summary       = "Fast serialization for ActiveModel"
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.require_paths = ["lib"]

  spec.extensions << "ext/panko_serializer/extconf.rb"

  spec.add_dependency "oj", "~> 3.6.0"
end
