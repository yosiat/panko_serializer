#include "type_cast.h"

static ID	type_cast_from_database_id = 0;
static ID	to_s_id = 0;

static VALUE ar_string_type = Qundef;
static VALUE ar_text_type = Qundef;
static VALUE ar_float_type = Qundef;
static VALUE ar_integer_type = Qundef;

static int initiailized = 0;
void cache_type_lookup() {
  if(initiailized != 1) {
    VALUE ar = rb_const_get_at(rb_cObject, rb_intern("ActiveRecord"));
    VALUE ar_type = rb_const_get_at(ar, rb_intern("Type"));


    ar_string_type = rb_const_get_at(ar_type, rb_intern("String"));
    ar_text_type = rb_const_get_at(ar_type, rb_intern("Text"));
    ar_float_type = rb_const_get_at(ar_type, rb_intern("Float"));
    ar_integer_type = rb_const_get_at(ar_type, rb_intern("Integer"));

    initiailized = 1;
  }
}


bool isStringOrTextType(VALUE type_metadata, VALUE type_klass) {
  return type_klass == ar_string_type || type_klass == ar_text_type;
}

VALUE castStringOrTextType(VALUE type_metadata, VALUE value) {
  if(RB_TYPE_P(value, T_STRING)) {
    return value;
  }

  return rb_funcall(value, to_s_id, 0);
}

bool isFloatType(VALUE type_metadata, VALUE type_klass) {
  return type_klass == ar_float_type;
}

VALUE castFloatType(VALUE type_metadata, VALUE value) {
  if(RB_TYPE_P(value, T_FLOAT)) {
    return value;
  }

  if(RB_TYPE_P(value, T_STRING)) {
    const char* val = StringValuePtr(value);
    return rb_float_new(strtod(val, NULL));
  }

  return Qundef;
}

bool isIntegerType(VALUE type_metadata, VALUE type_klass) {
  return type_klass == ar_integer_type;
}

VALUE castIntegerType(VALUE type_metadata, VALUE value) {
  if(RB_INTEGER_TYPE_P(value)) {
    return value;
  }

  if(RB_TYPE_P(value, T_STRING)) {
    const char* val = StringValuePtr(value);
    return rb_cstr2inum(val, 10);
  }

  return Qundef;
}

VALUE type_cast(VALUE type_metadata, VALUE value)
{
  cache_type_lookup();

  VALUE value_klass = rb_obj_class(type_metadata);
  VALUE typeCastedValue = Qundef;

  TypeCast	typeCast;
  for (typeCast = type_casts; NULL != typeCast->canCast; typeCast++) {
    if(typeCast->canCast(type_metadata, value_klass) == true) {
      typeCastedValue = typeCast->typeCast(type_metadata, value);
      break;
    }
  }

  if(typeCastedValue == Qundef) {
    return rb_funcall(type_metadata, type_cast_from_database_id, 1, value);
  }

  return typeCastedValue;
}

VALUE public_type_cast(VALUE module, VALUE type_metadata, VALUE value) {
  return type_cast(type_metadata, value);
}

void init_panko_type_cast(VALUE mPanko) {
  type_cast_from_database_id = rb_intern_const("type_cast_from_database");
  to_s_id = rb_intern_const("to_s");

  rb_define_singleton_method(mPanko, "_type_cast", public_type_cast, 2);
}
