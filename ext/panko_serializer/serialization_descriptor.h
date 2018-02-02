#pragma once

#include <ruby.h>
#include <stdbool.h>

#include "attributes_iterator.h"

enum ObjectType { Unknown = 0, ActiveRecord = 1, Plain = 2 };

typedef void (*EachAttributeFunc)(VALUE writer, VALUE name, VALUE value);
typedef struct _SerializationDescriptor {
  // type of the serializer, so we can create it later
  VALUE serializer_type;
  // Cached value of the serializer
  VALUE serializer;

  // Metadata
  VALUE attributes;
  VALUE aliases;
  VALUE method_fields;
  VALUE has_one_associations;
  VALUE has_many_associations;

  enum ObjectType object_type;

  int (*write_attributes)(VALUE object,
                          VALUE attributes,
                          EachAttributeFunc func,
                          VALUE context);

} * SerializationDescriptor;

SerializationDescriptor sd_read(VALUE descriptor);

void sd_mark(SerializationDescriptor data);

VALUE sd_build_serializer(SerializationDescriptor descriptor);
void sd_apply_serializer_config(VALUE serializer, VALUE object, VALUE context);
void sd_set_object_type(SerializationDescriptor sd, VALUE subject);

void panko_init_serialization_descriptor(VALUE mPanko);
