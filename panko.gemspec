# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'panko/version'

Gem::Specification.new do |spec|
  spec.name          = "panko"
  spec.version       = Panko::VERSION
  spec.authors       = ["Yosi Attias"]
  spec.email         = ["yosy101@gmail.com"]

  spec.summary       = "Fast serialization for ActiveModel"
  spec.homepage      = ""
  spec.license       = "MIT"


  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.require_paths = ['lib']

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"

  spec.add_dependency 'oj', '~> 3.1.3'
end
