#include "type_cast.h"

static ID	type_cast_from_database_id = 0;

static VALUE string_type = Qundef;
static VALUE text_type = Qundef;

void cache_type_lookup() {
  if(string_type == Qundef || text_type == Qundef) {
    VALUE ar = rb_const_get_at(rb_cObject, rb_intern("ActiveRecord"));
    VALUE ar_type = rb_const_get_at(ar, rb_intern("Type"));


    string_type = rb_const_get_at(ar_type, rb_intern("String"));
    text_type = rb_const_get_at(ar_type, rb_intern("Text"));
  }
}

VALUE type_cast(VALUE type_metadata, VALUE value)
{
  cache_type_lookup();
  VALUE value_klass = rb_obj_class(type_metadata);

  if(value_klass == string_type || value_klass == text_type) {
    if(RB_TYPE_P(value, T_STRING)) {
      return value;
    }

  }

  if(type_cast_from_database_id == 0) {
    type_cast_from_database_id = rb_intern_const("type_cast_from_database");
  }
  return rb_funcall(type_metadata, type_cast_from_database_id, 1, value);
}
