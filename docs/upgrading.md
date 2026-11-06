---
title: Upgrading from 0.8
layout: default
nav_order: 6
---

# Upgrading from 0.8

Panko no longer ships a C extension. The serializer DSL, `Panko::ArraySerializer`,
filters, `context` / `scope` and `Panko::Response` work as before, so most apps
upgrade by bumping the gem.

## Requirements

-   Ruby 3.4 or newer (0.8 supported 3.1).
-   ActiveSupport 7.2 or newer. CI tests Rails 7.2, 8.0 and 8.1.
-   Nothing to compile at install: no compiler toolchain in your build image.

## What can change in your output

Run your serializer specs after upgrading. These are the cases where 0.8 and
the new engine differ:

-   **No trailing newline.** `serialize_to_json` and `to_json` no longer end
    with `"\n"`. Parsed JSON is identical; only byte-level consumers (response
    caches, checksums, ETags) see the difference.
-   **Values come from ActiveRecord.** Every attribute starts from what
    `record.<attribute>` returns, so custom attribute types, enums and
    time-zone-aware attributes serialize the way the rest of your app sees
    them. 0.8 re-implemented type casting in C.
-   **Attributes resolve like Ruby methods.** A model instance method now
    serializes its value; 0.8 wrote `null`. A name that is neither a column nor
    a method raises `NoMethodError` at serialize time instead of writing
    `null`. To keep a `null` key, define the method and return `nil`.
-   **An attribute and an association can't share a name.** The serializer
    raises `Panko::CodeGen::NameCollisionError` on first use. Drop the
    attribute to keep 0.8's parsed output, where the association won.
-   **Nested filters narrow, they don't replace.** A runtime nested filter is
    applied on top of the association's declared `only:` / `except:` and its
    serializer's `filters_for`, so it can no longer bring back a field those
    removed. See [Filters]({% link filters.md %}).
-   **The C classes are gone.** `Panko::SerializationDescriptor`,
    `Panko::Attribute`, `Panko::Association` and `Panko::ObjectWriter` no
    longer exist. Use [`Panko::Descriptor`]({% link descriptor.md %}) to read a
    serializer's shape.

Serializer instances are now reusable: 0.8 raised on a second `serialize` call.

## New, all optional

-   **[`Panko.compile_all` and `models`]({% link configuration.md %}#compiling-at-boot)**
    compile serializers once at boot, before a forking server starts its
    workers.
-   **[`Panko.configure`]({% link configuration.md %})** tunes auto-specialization
    and the JSON writer pool. The defaults need no change.
-   **[`Panko::Descriptor`]({% link descriptor.md %})** is a read-only view of a
    serializer's shape, for tools such as association preloaders.

The full list is in the
[CHANGELOG](https://github.com/yosiat/panko_serializer/blob/master/CHANGELOG.md).
