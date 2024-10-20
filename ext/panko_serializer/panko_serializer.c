#include "panko_serializer.h"

#include <ruby.h>

static ID push_value_id;
static ID push_json_id;


void write_value(VALUE str_writer, VALUE key, VALUE value, VALUE isJson) {
  if (isJson == Qtrue) {
    rb_funcall(str_writer, push_json_id, 2, value, key);
  } else {
    rb_funcall(str_writer, push_value_id, 2, value, key);
  }
}

VALUE write_attributes_api(VALUE klass, VALUE object, VALUE descriptor,
                           VALUE str_writer) {
  SerializationDescriptor sd = sd_read(descriptor);

  sd->attributes_writer.write_attributes(object, sd->attributes, write_value,
                                         str_writer);

  return Qnil;
}

VALUE sd_set_writer_api(VALUE klass, VALUE descriptor, VALUE object) {
  SerializationDescriptor sd = sd_read(descriptor);

  sd_set_writer(sd, object);

  return Qnil;
}

void Init_panko_serializer() {
  push_value_id = rb_intern("push_value");
  push_json_id = rb_intern("push_json");

  VALUE mPanko = rb_define_module("Panko");

  rb_define_singleton_method(mPanko, "_write_attributes", write_attributes_api,
                             3);

  rb_define_singleton_method(mPanko, "_sd_set_writer", sd_set_writer_api, 2);

  panko_init_serialization_descriptor(mPanko);
  init_attributes_writer(mPanko);
  panko_init_type_cast(mPanko);
  panko_init_attribute(mPanko);
  panko_init_association(mPanko);
}
