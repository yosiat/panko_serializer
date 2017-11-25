#include <ruby.h>

#ifndef __SD_H__
#define __SD_H__

typedef struct _SerializationDescriptor {
  // type of the serializer, so we can create it later
  VALUE serializer_type;
  // Cached value of the serializer
  VALUE serializer;

  // Metadata
  VALUE fields;
  VALUE aliases;
  VALUE method_fields;
  VALUE has_one_associations;
  VALUE has_many_associations;
} * SerializationDescriptor;

SerializationDescriptor sd_read(VALUE descriptor);
VALUE sd_build_serializer(SerializationDescriptor descriptor);
void sd_apply_serializer_config(VALUE serializer, VALUE object, VALUE context);

void panko_init_serialization_descriptor(VALUE mPanko);

#endif
