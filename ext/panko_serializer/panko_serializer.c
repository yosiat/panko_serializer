#include <ruby.h>

#include "panko_serializer.h"

static ID push_value_id;
static ID push_array_id;
static ID push_object_id;
static ID pop_id;

static ID to_a_id;

void write_value(VALUE str_writer, VALUE key, VALUE value) {
  rb_funcall(str_writer, push_value_id, 2, value, key);
}

void serialize_method_fields(VALUE subject,
                             VALUE str_writer,
                             SerializationDescriptor descriptor,
                             VALUE context) {
  VALUE method_fields, serializer;
  long i;

  method_fields = descriptor->method_fields;
  if (RARRAY_LEN(method_fields) == 0) {
    return;
  }

  serializer = sd_build_serializer(descriptor);
  sd_apply_serializer_config(serializer, subject, context);

  for (i = 0; i < RARRAY_LEN(method_fields); i++) {
    VALUE attribute_name = RARRAY_AREF(method_fields, i);
    volatile VALUE result =
        rb_funcall(serializer, rb_sym2id(attribute_name), 0);

    write_value(str_writer, rb_sym2str(attribute_name), result);
  }
}

void panko_attributes_iter(VALUE object,
                           VALUE name,
                           VALUE value,
                           VALUE type_metadata,
                           VALUE str_writer) {
  write_value(str_writer, name, value);
}

void serialize_fields(VALUE subject,
                      VALUE str_writer,
                      SerializationDescriptor descriptor,
                      VALUE context) {
  panko_each_attribute(subject, descriptor->attributes, panko_attributes_iter,
                       str_writer);

  serialize_method_fields(subject, str_writer, descriptor, context);
}

void serialize_has_one_associations(VALUE subject,
                                    VALUE str_writer,
                                    VALUE context,
                                    SerializationDescriptor descriptor,
                                    VALUE associations) {
  long i;
  for (i = 0; i < RARRAY_LEN(associations); i++) {
    volatile VALUE association_el = RARRAY_AREF(associations, i);
    Association association = association_read(association_el);

    volatile VALUE value = rb_funcall(subject, association->name_id, 0);

    if (value == Qnil) {
      write_value(str_writer, association->name_str, value);
    } else {
      serialize_subject(association->name_str, value, str_writer,
                        association->descriptor, context);
    }
  }
}

void serialize_has_many_associations(VALUE subject,
                                     VALUE str_writer,
                                     VALUE context,
                                     SerializationDescriptor descriptor,
                                     VALUE associations) {
  long i;
  for (i = 0; i < RARRAY_LEN(associations); i++) {
    volatile VALUE association_el = RARRAY_AREF(associations, i);
    Association association = association_read(association_el);

    volatile VALUE value = rb_funcall(subject, association->name_id, 0);

    if (value == Qnil) {
      write_value(str_writer, association->name_str, value);
    } else {
      serialize_subjects(association->name_str, value, str_writer,
                         association->descriptor, context);
    }
  }
}

VALUE serialize_subject(VALUE key,
                        VALUE subject,
                        VALUE str_writer,
                        SerializationDescriptor descriptor,
                        VALUE context) {
  rb_funcall(str_writer, push_object_id, 1, key);

  serialize_fields(subject, str_writer, descriptor, context);

  if (RARRAY_LEN(descriptor->has_one_associations) >= 0) {
    serialize_has_one_associations(subject, str_writer, context, descriptor,
                                   descriptor->has_one_associations);
  }

  if (RARRAY_LEN(descriptor->has_many_associations) >= 0) {
    serialize_has_many_associations(subject, str_writer, context, descriptor,
                                    descriptor->has_many_associations);
  }

  rb_funcall(str_writer, pop_id, 0);

  return Qnil;
}

VALUE serialize_subjects(VALUE key,
                         VALUE subjects,
                         VALUE str_writer,
                         SerializationDescriptor descriptor,
                         VALUE context) {
  long i;

  rb_funcall(str_writer, push_array_id, 1, key);

  if (!RB_TYPE_P(subjects, T_ARRAY)) {
    subjects = rb_funcall(subjects, to_a_id, 0);
  }

  for (i = 0; i < RARRAY_LEN(subjects); i++) {
    volatile VALUE subject = RARRAY_AREF(subjects, i);
    serialize_subject(Qnil, subject, str_writer, descriptor, context);
  }

  rb_funcall(str_writer, pop_id, 0);

  return Qnil;
}

VALUE serialize_subject_api(VALUE klass,
                            VALUE subject,
                            VALUE str_writer,
                            VALUE descriptor,
                            VALUE context) {
  return serialize_subject(Qnil, subject, str_writer, sd_read(descriptor),
                           context);
}

VALUE serialize_subjects_api(VALUE klass,
                             VALUE subjects,
                             VALUE str_writer,
                             VALUE descriptor,
                             VALUE context) {
  serialize_subjects(Qnil, subjects, str_writer, sd_read(descriptor), context);

  return Qnil;
}

void Init_panko_serializer() {
  push_value_id = rb_intern("push_value");
  push_array_id = rb_intern("push_array");
  push_object_id = rb_intern("push_object");
  pop_id = rb_intern("pop");
  to_a_id = rb_intern("to_a");

  VALUE mPanko = rb_define_module("Panko");

  rb_define_singleton_method(mPanko, "serialize_subject", serialize_subject_api,
                             4);

  rb_define_singleton_method(mPanko, "serialize_subjects",
                             serialize_subjects_api, 4);

  panko_init_serialization_descriptor(mPanko);
  panko_init_attributes_iterator(mPanko);
  panko_init_type_cast(mPanko);
  panko_init_attribute(mPanko);
  panko_init_association(mPanko);
}
