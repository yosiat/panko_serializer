#pragma once

#include <ruby.h>
#include <stdbool.h>

#include "attributes_writer/attributes_writer.h"

typedef struct _SerializationDescriptor {
  // Metadata
  VALUE attributes;
  VALUE aliases;

  AttributesWriter attributes_writer;
}* SerializationDescriptor;

SerializationDescriptor sd_read(VALUE descriptor);

void sd_mark(SerializationDescriptor data);

void sd_set_writer(SerializationDescriptor sd, VALUE object);

void panko_init_serialization_descriptor(VALUE mPanko);
