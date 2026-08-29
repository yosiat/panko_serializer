---
title: Introduction
layout: default
nav_order: 1
---

# Introduction

Panko is a library for serializing ActiveRecord/Ruby objects to JSON strings —
fast.

It reaches its [performance]({% link performance.md %}) through a few choices:

-   **Code generation** — Panko compiles a specialized serializer, in plain
    Ruby, once per serializer class, so per-record serialization is
    straight-line code rather than a metadata-driven loop.
-   **Oj** — Panko builds JSON incrementally with `Oj::StringWriter`, skipping
    the intermediate Hash most serializers allocate.
-   **Ahead-of-time metadata** — everything Panko can figure out about a
    serializer (which fields are columns, which are methods, which associations
    exist) is resolved once, not inside the serialization loop.

The engine is **pure Ruby** — there is no native extension to compile when you
install the gem. To dig into these choices, read
[Design Choices]({% link design-choices.md %}).

Ready to write your first serializer? Head to
[Getting Started]({% link getting-started.md %}).
