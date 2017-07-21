#include <ruby.h>

#include "attributes_iterator.h"
#include "type_cast.h"

static ID push_value_id = 0;

void write_value(VALUE str_writer,
                 VALUE key,
                 VALUE value,
                 VALUE type_metadata) {
  if (type_metadata != Qnil) {
    value = type_cast(type_metadata, value);
  }

  rb_funcall(str_writer, push_value_id, 2, value, key);
}

void panko_attributes_iter(VALUE object,
                           VALUE name,
                           VALUE value,
                           VALUE type_metadata,
                           VALUE context) {
  write_value(context, name, value, type_metadata);
}

VALUE process(VALUE klass,
              VALUE obj,
              VALUE str_writer,
              VALUE serializer,
              VALUE attributes,
              VALUE method_calls_attributes) {
  panko_each_attribute(obj, attributes, panko_attributes_iter, str_writer);

  long i;
  for (i = 0; i < RARRAY_LEN(method_calls_attributes); i++) {
    VALUE attribute_name = RARRAY_AREF(method_calls_attributes, i);
    VALUE result = rb_funcall(serializer, rb_sym2id(attribute_name), 0);

    write_value(str_writer, rb_sym2str(attribute_name), result, Qnil);
  }

  return Qnil;
}

void Init_panko() {
  push_value_id = rb_intern("push_value");

  VALUE mPanko = rb_define_module("Panko");
  rb_define_singleton_method(mPanko, "process", process, 5);

  panko_init_attributes_iterator(mPanko);
  panko_init_type_cast(mPanko);
}
