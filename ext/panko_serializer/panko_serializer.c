#include <ruby.h>

#include "time_conversion.h"

VALUE public_is_iso8601_time_string(VALUE klass, VALUE value) {
  return is_iso8601_time_string(StringValuePtr(value)) ? Qtrue : Qfalse;
}

VALUE public_iso_ar_iso_datetime_string(VALUE klass, VALUE value) {
  return iso_ar_iso_datetime_string(StringValuePtr(value));
}

void Init_panko_serializer() {
  VALUE mPanko = rb_define_module("Panko");

  rb_define_singleton_method(mPanko, "is_iso8601_time_string",
                             public_is_iso8601_time_string, 1);
  rb_define_singleton_method(mPanko, "iso_ar_iso_datetime_string",
                             public_iso_ar_iso_datetime_string, 1);

  panko_init_time(mPanko);
}
