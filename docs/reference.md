---
title: Reference
layout: default
nav_order: 5
has_children: true
---

# Reference

Detailed reference for Panko's API and DSL.

-   [Serializers]({% link serializers.md %}) — the `Panko::Serializer` /
    `Panko::ArraySerializer` API: serialize methods, constructor options, and
    `context` / `scope`.
-   [Attributes]({% link attributes.md %}) — field attributes, method
    attributes, and `aliases`.
-   [Associations]({% link associations.md %}) — `has_one` and `has_many`,
    aliasing, and serializer inference.
-   [Filters]({% link filters.md %}) — `only` / `except`, nested filters, and
    `filters_for`.
-   [Response]({% link response-bag.md %}) — `Panko::Response` and
    `Panko::JsonValue` for composing responses.
-   [Configuration]({% link configuration.md %}) — `Panko.configure` and the
    auto-specialization settings.
-   [Descriptor]({% link descriptor.md %}) — `Panko::Descriptor`, the
    read-only view of a serializer's shape for preloaders and other tooling.
