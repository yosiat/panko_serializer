#pragma once

#include <ruby.h>
#include <stdbool.h>

#include "attributes_writer/attributes_writer.h"

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

  AttributesWriter attributes_writer;
} * SerializationDescriptor;

SerializationDescriptor sd_read(VALUE descriptor);

void sd_mark(SerializationDescriptor data);

void sd_set_writer(SerializationDescriptor sd, VALUE subject);

void panko_init_serialization_descriptor(VALUE mPanko);
