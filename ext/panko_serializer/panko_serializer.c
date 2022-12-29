#include "panko_serializer.h"

#include <ruby.h>

static ID push_value_id;
static ID push_array_id;
static ID push_object_id;
static ID push_json_id;
static ID pop_id;

static ID to_a_id;

static ID object_id;
static ID serialization_context_id;

static VALUE SKIP = Qundef;

void write_value(VALUE str_writer, VALUE key, VALUE value, VALUE isJson) {
  if (isJson == Qtrue) {
    rb_funcall(str_writer, push_json_id, 2, value, key);
  } else {
    rb_funcall(str_writer, push_value_id, 2, value, key);
  }
}

void serialize_method_fields(VALUE object, VALUE str_writer,
                             SerializationDescriptor descriptor) {
  if (RARRAY_LEN(descriptor->method_fields) == 0) {
    return;
  }

  volatile VALUE method_fields, serializer;
  long i;

  method_fields = descriptor->method_fields;

  serializer = descriptor->serializer;
  rb_ivar_set(serializer, object_id, object);

  for (i = 0; i < RARRAY_LEN(method_fields); i++) {
    volatile VALUE raw_attribute = RARRAY_AREF(method_fields, i);
    Attribute attribute = PANKO_ATTRIBUTE_READ(raw_attribute);

    volatile VALUE result = rb_funcall(serializer, attribute->name_id, 0);
    if (result != SKIP) {
      write_value(str_writer, attribute->name_str, result, Qfalse);
    }
  }

  rb_ivar_set(serializer, object_id, Qnil);
}

void serialize_fields(VALUE object, VALUE str_writer,
                      SerializationDescriptor descriptor) {
  descriptor->attributes_writer.write_attributes(object, descriptor->attributes,
                                                 write_value, str_writer);

  serialize_method_fields(object, str_writer, descriptor);
}

void serialize_has_one_associations(VALUE object, VALUE str_writer,
                                    VALUE associations) {
  long i;
  for (i = 0; i < RARRAY_LEN(associations); i++) {
    volatile VALUE association_el = RARRAY_AREF(associations, i);
    Association association = association_read(association_el);

    volatile VALUE value = rb_funcall(object, association->name_id, 0);

    if (NIL_P(value)) {
      write_value(str_writer, association->name_str, value, Qfalse);
    } else {
      serialize_object(association->name_str, value, str_writer,
                       association->descriptor);
    }
  }
}

void serialize_has_many_associations(VALUE object, VALUE str_writer,
                                     VALUE associations) {
  long i;
  for (i = 0; i < RARRAY_LEN(associations); i++) {
    volatile VALUE association_el = RARRAY_AREF(associations, i);
    Association association = association_read(association_el);

    volatile VALUE value = rb_funcall(object, association->name_id, 0);

    if (NIL_P(value)) {
      write_value(str_writer, association->name_str, value, Qfalse);
    } else {
      serialize_objects(association->name_str, value, str_writer,
                        association->descriptor);
    }
  }
}

VALUE serialize_object(VALUE key, VALUE object, VALUE str_writer,
                       SerializationDescriptor descriptor) {
  sd_set_writer(descriptor, object);

  rb_funcall(str_writer, push_object_id, 1, key);

  serialize_fields(object, str_writer, descriptor);

  if (RARRAY_LEN(descriptor->has_one_associations) > 0) {
    serialize_has_one_associations(object, str_writer,
                                   descriptor->has_one_associations);
  }

  if (RARRAY_LEN(descriptor->has_many_associations) > 0) {
    serialize_has_many_associations(object, str_writer,
                                    descriptor->has_many_associations);
  }

  rb_funcall(str_writer, pop_id, 0);

  return Qnil;
}

VALUE serialize_objects(VALUE key, VALUE objects, VALUE str_writer,
                        SerializationDescriptor descriptor) {
  long i;

  rb_funcall(str_writer, push_array_id, 1, key);

  if (!RB_TYPE_P(objects, T_ARRAY)) {
    objects = rb_funcall(objects, to_a_id, 0);
  }

  for (i = 0; i < RARRAY_LEN(objects); i++) {
    volatile VALUE object = RARRAY_AREF(objects, i);
    serialize_object(Qnil, object, str_writer, descriptor);
  }

  rb_funcall(str_writer, pop_id, 0);

  return Qnil;
}

VALUE serialize_object_api(VALUE klass, VALUE object, VALUE str_writer,
                           VALUE descriptor) {
  SerializationDescriptor sd = sd_read(descriptor);
  return serialize_object(Qnil, object, str_writer, sd);
}

VALUE serialize_objects_api(VALUE klass, VALUE objects, VALUE str_writer,
                            VALUE descriptor) {
  serialize_objects(Qnil, objects, str_writer, sd_read(descriptor));

  return Qnil;
}

void Init_panko_serializer() {
  push_value_id = rb_intern("push_value");
  push_array_id = rb_intern("push_array");
  push_object_id = rb_intern("push_object");
  push_json_id = rb_intern("push_json");
  pop_id = rb_intern("pop");
  to_a_id = rb_intern("to_a");
  object_id = rb_intern("@object");
  serialization_context_id = rb_intern("@serialization_context");

  VALUE mPanko = rb_define_module("Panko");

  rb_define_singleton_method(mPanko, "serialize_object", serialize_object_api,
                             3);

  rb_define_singleton_method(mPanko, "serialize_objects", serialize_objects_api,
                             3);

  VALUE mPankoSerializer = rb_const_get(mPanko, rb_intern("Serializer"));
  SKIP = rb_const_get(mPankoSerializer, rb_intern("SKIP"));
  rb_global_variable(&SKIP);

  panko_init_serialization_descriptor(mPanko);
  init_attributes_writer(mPanko);
  panko_init_type_cast(mPanko);
  panko_init_attribute(mPanko);
  panko_init_association(mPanko);
}
