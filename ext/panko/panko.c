#include <ruby.h>

static ID	attributes_id = 0;
static ID	push_value_id = 0;
static ID	types_id = 0;
static ID	values_id = 0;


static VALUE
read_attributes(VALUE obj) {
  if (0 == attributes_id) {
    attributes_id = rb_intern("@attributes");
  }
  return rb_ivar_get(obj, attributes_id);
}

static void
write_value(VALUE str_writer, VALUE key, VALUE value, VALUE type_metadata)
{
  if (0 == push_value_id) {
    push_value_id = rb_intern("push_value");
  }

  // TODO: take care of type_metadata
  // TODO: call directly on oj's push_value
  rb_funcall(str_writer, push_value_id, 2, value, key);
}


static VALUE
process(VALUE klass, VALUE obj, VALUE str_writer, VALUE serializer, VALUE attributes, VALUE method_calls_attributes)
{
  VALUE attributes_set = read_attributes(obj);
  if(attributes_set == Qnil) {
    return Qnil;
  }
  VALUE attributes_hash = read_attributes(attributes_set);
  if(attributes_hash == Qnil) {
    return Qnil;
  }

  if (0 == types_id) {
    types_id = rb_intern("@types");
  }
  VALUE types = rb_ivar_get(attributes_hash, types_id);
  if(types == Qnil) {
    return Qnil;
  }

  if (0 == values_id) {
    values_id = rb_intern("@values");
  }
  VALUE values = rb_ivar_get(attributes_hash, values_id);
  if(values == Qnil) {
    return Qnil;
  }

  for (long i = 0; i < RARRAY_LEN(attributes); i++) {
    VALUE member = rb_sym2str(RARRAY_AREF(attributes, i));

    VALUE value = rb_hash_aref(values, member);
    VALUE type_metadata = rb_hash_aref(types, member);

    write_value(str_writer, member, value, type_metadata);
  }

  for (long i = 0; i < RARRAY_LEN(method_calls_attributes); i++) {
    VALUE attribute_name = RARRAY_AREF(method_calls_attributes, i);
    VALUE result = rb_funcall(serializer, rb_sym2id(attribute_name), 0);

    write_value(str_writer, rb_sym2str(attribute_name), result, Qnil);
  }

  return Qnil;
}

void
Init_panko()
{
  VALUE mPanko = rb_define_module("Panko");
  rb_define_singleton_method(mPanko, "process", process, 5);
}
