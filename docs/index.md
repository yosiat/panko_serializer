---
title: Introduction
layout: default
nav_order: 1
---

# Introduction

Panko is a library which is inspired by ActiveModelSerializers 0.9 for serializing ActiveRecord/Ruby objects to JSON strings, fast.

To achieve it's [performance]({% link performance.md %}):

-   Oj - Panko relies on Oj since it's fast and allow to serialize incrementally using `Oj::StringWriter`.
-   Serialization Descriptor - Panko computes most of the metadata ahead of time, to save time later in serialization.
-   Type casting — Panko does type casting by itself, instead of relying on ActiveRecord.
