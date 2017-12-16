# Panko

[![Build Status](https://travis-ci.org/yosiat/panko_serializer.svg?branch=master)](https://travis-ci.org/yosiat/panko_serializer)

Panko is library which is inspired by ActiveModelSerializers 0.9 for serializing ActiveRecord objects to JSON strings, fast.

To achieve it's [performance](https://yosiat.github.io/panko_serializer/performance.html):

* Oj - Panko relies Oj since it's fast and allow to to serialize incrementally using `Oj::StringWriter`
* Serialization Descriptor - Panko computes most of the metadata ahead of time, to save time later in serialization.
* Type casting — Panko does type casting by it's self, instead of relying ActiveRecord.

To dig deeper about the performance choices, read [Design Choices](https://yosiat.github.io/panko_serializer/design-choices.html).


Support
-------

- [Documentation](https://yosiat.github.io/panko_serializer)
- [Getting Started](https://yosiat.github.io/panko_serializer/getting-started.html)
- Join our [slack community](https://pankoserializer.herokuapp.com/)

License
-------

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

