---
id: index
title: Introduction
sidebar_label: Introduction
slug: /
---
Panko is library which is inspired by ActiveModelSerializers 0.9 for serializing ActiveRecord/Ruby objects to JSON strings, fast.

To achieve it's [performance](https://panko.dev/docs/performance.html):

-   Oj - Panko relies Oj since it's fast and allow to serialize incrementally using `Oj::StringWriter`
-   Serialization Descriptor - Panko computes most of the metadata ahead of time, to save time later in serialization.
-   Type casting — Panko does type casting by it's self, instead of relying ActiveRecord.
