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
  VALUE method_fields;
  VALUE aliases;
  VALUE has_one_associations;
  VALUE has_many_associations;
} * SerializationDescriptor;

VALUE serialization_descriptor_fields_ref(VALUE descriptor);
VALUE serialization_descriptor_method_fields_ref(VALUE descriptor);
VALUE serialization_descriptor_has_one_associations_ref(VALUE descriptor);
VALUE serialization_descriptor_has_many_associations_ref(VALUE descriptor);

SerializationDescriptor sd_read(VALUE descriptor);
VALUE sd_build_serializer(SerializationDescriptor descriptor);
void sd_apply_serializer_config(VALUE serializer, VALUE object, VALUE context);

void panko_init_serialization_descriptor(VALUE mPanko);

#endif
