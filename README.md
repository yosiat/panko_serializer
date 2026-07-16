# Panko

![Build Status](https://github.com/yosiat/panko_serializer/workflows/Panko%20Serializer%20CI/badge.svg?branch=master)

Panko is a library which is inspired by ActiveModelSerializers 0.9 for serializing ActiveRecord/Ruby objects to JSON strings, fast.

Panko is pure Ruby — no native extension, nothing to compile at install. To achieve its [performance](https://panko.dev/performance):

* Code generation — each serializer is compiled once into specialized, straight-line Ruby, so serialization runs no per-record introspection and YJIT optimizes it well.
* Auto-specialization — the first time a serializer meets an ActiveRecord class, Panko compiles a variant hard-wired to that model, reading values straight from its attribute storage.
* Oj — JSON is written incrementally using `Oj::StringWriter`.

To dig deeper about the performance choices, read [Design Choices](https://panko.dev/design-choices).


Support
-------

- [Documentation](https://panko.dev/)
- [Getting Started](https://panko.dev/getting-started)

License
-------

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
