---
id: index
title: Introduction
sidebar_label: Introduction
slug: /
---
Panko is a library which is inspired by ActiveModelSerializers 0.9 for serializing ActiveRecord/Ruby objects to JSON strings, fast.

To achieve it's [performance](https://panko.dev/docs/performance/):

-   Oj - Panko relies on Oj since it's fast and allow to serialize incrementally using `Oj::StringWriter`.
-   Serialization Descriptor - Panko computes most of the metadata ahead of time, to save time later in serialization.
-   Type casting — Panko does type casting by itself, instead of relying on ActiveRecord.
