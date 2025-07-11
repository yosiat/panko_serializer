#include <ruby.h>

#include "time_conversion.h"

static ID push_value_id;

static VALUE datetime_writer_write(VALUE self, VALUE value, VALUE writer,
                                   VALUE key) {
  if (RB_TYPE_P(value, T_STRING)) {
    const char* val = StringValuePtr(value);

    // 'Z' in ISO8601 says it's UTC
    if (val[strlen(val) - 1] == 'Z' && is_iso8601_time_string(val) == Qtrue) {
      rb_funcall(writer, push_value_id, 2, value, key);
      return Qtrue;
    }

    volatile VALUE iso8601_string = iso_ar_iso_datetime_string(val);
    if (iso8601_string != Qnil) {
      rb_funcall(writer, push_value_id, 2, iso8601_string, key);
      return Qtrue;
    }
  }

  return Qfalse;
}

// Helper function to safely get a constant if it exists
static VALUE safe_const_get(VALUE parent, const char* name) {
  if (rb_const_defined(parent, rb_intern(name))) {
    return rb_const_get(parent, rb_intern(name));
  }
  return Qnil;
}

void Init_panko_serializer() {
  push_value_id = rb_intern("push_value");

  VALUE mPanko = rb_define_module("Panko");

  panko_init_time(mPanko);

  VALUE impl = safe_const_get(mPanko, "Impl");
  if (NIL_P(impl)) {
    printf("Not patching\n");
    return;
  }

  VALUE attributes_writer = safe_const_get(impl, "AttributesWriter");
  if (NIL_P(attributes_writer)) {
    printf("Not patching\n");
    return;
  }

  VALUE active_record = safe_const_get(attributes_writer, "ActiveRecord");
  if (NIL_P(active_record)) {
    printf("Not patching\n");
    return;
  }

  VALUE values_writer = safe_const_get(active_record, "ValuesWriter");
  if (NIL_P(values_writer)) {
    printf("Not patching\n");
    return;
  }

  VALUE cDateTimeWriter = safe_const_get(values_writer, "DateTimeWriter");
  if (NIL_P(cDateTimeWriter)) {
    printf("Not patching\n");
  } else {
    rb_define_method(cDateTimeWriter, "write", datetime_writer_write, 3);
  }
}
