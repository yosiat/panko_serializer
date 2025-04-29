# Panko

![Build Status](https://github.com/yosiat/panko_serializer/workflows/Panko%20Serializer%20CI/badge.svg?branch=master)

Panko is a library which is inspired by ActiveModelSerializers 0.9 for serializing ActiveRecord/Ruby objects to JSON strings, fast.

To achieve its [performance](https://panko.dev/performance/):

* Oj - Panko relies on Oj since it's fast and allows for incremental serialization using `Oj::StringWriter`
* Serialization Descriptor - Panko computes most of the metadata ahead of time, to save time later in serialization.
* Type casting — Panko does type casting by itself, instead of relying on ActiveRecord.

To dig deeper about the performance choices, read [Design Choices](https://panko.dev/design-choices/).


Support
-------

- [Documentation](https://panko.dev/)
- [Getting Started](https://panko.dev/getting-started/)

License
-------

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
