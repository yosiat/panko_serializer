#include "type_cast.h"
#include "time_conversion.h"

ID deserialize_from_db_id = 0;
ID to_s_id = 0;
ID to_i_id = 0;

static VALUE oj_type = Qundef;
static VALUE oj_parseerror_type = Qundef;
ID oj_sc_parse_id = 0;

// Caching ActiveRecord Types
static VALUE ar_string_type = Qundef;
static VALUE ar_text_type = Qundef;
static VALUE ar_float_type = Qundef;
static VALUE ar_integer_type = Qundef;
static VALUE ar_boolean_type = Qundef;
static VALUE ar_date_time_type = Qundef;
static VALUE ar_time_zone_converter = Qundef;
static VALUE ar_json_type = Qundef;

static VALUE ar_pg_integer_type = Qundef;
static VALUE ar_pg_float_type = Qundef;
static VALUE ar_pg_uuid_type = Qundef;
static VALUE ar_pg_json_type = Qundef;
static VALUE ar_pg_date_time_type = Qundef;

static int initiailized = 0;

VALUE cache_postgres_type_lookup(VALUE ar) {
  VALUE ar_connection_adapters, ar_postgresql, ar_oid;

  ar_connection_adapters = rb_const_get_at(ar, rb_intern("ConnectionAdapters"));
  if (ar_connection_adapters == Qundef) {
    return Qfalse;
  }

  ar_postgresql =
      rb_const_get_at(ar_connection_adapters, rb_intern("PostgreSQL"));
  if (ar_postgresql == Qundef) {
    return Qfalse;
  }

  if (!rb_const_defined(ar_postgresql, rb_intern("OID"))) {
    return Qfalse;
  }

  ar_oid = rb_const_get_at(ar_postgresql, rb_intern("OID"));

  if (rb_const_defined(ar_oid, rb_intern("Float"))) {
    ar_pg_float_type = rb_const_get_at(ar_oid, rb_intern("Float"));
  }

  if (rb_const_defined(ar_oid, rb_intern("Integer"))) {
    ar_pg_integer_type = rb_const_get_at(ar_oid, rb_intern("Integer"));
  }

  if (rb_const_defined(ar_oid, rb_intern("Uuid"))) {
    ar_pg_uuid_type = rb_const_get_at(ar_oid, rb_intern("Uuid"));
  }

  if (rb_const_defined(ar_oid, rb_intern("Json"))) {
    ar_pg_json_type = rb_const_get_at(ar_oid, rb_intern("Json"));
  }

  if (rb_const_defined(ar_oid, rb_intern("DateTime"))) {
    ar_pg_date_time_type = rb_const_get_at(ar_oid, rb_intern("DateTime"));
  }

  return Qtrue;
}

VALUE cache_time_zone_type_lookup(VALUE ar) {
  VALUE ar_attr_methods, ar_time_zone_conversion;

  // ActiveRecord::AttributeMethods
  ar_attr_methods = rb_const_get_at(ar, rb_intern("AttributeMethods"));
  if (ar_attr_methods == Qundef) {
    return Qfalse;
  }

  // ActiveRecord::AttributeMethods::TimeZoneConversion
  ar_time_zone_conversion =
      rb_const_get_at(ar_attr_methods, rb_intern("TimeZoneConversion"));
  if (ar_time_zone_conversion == Qundef) {
    return Qfalse;
  }

  ar_time_zone_converter =
      rb_const_get_at(ar_time_zone_conversion, rb_intern("TimeZoneConverter"));

  return Qtrue;
}

void cache_type_lookup() {
  if (initiailized == 1) {
    return;
  }

  initiailized = 1;

  VALUE ar, ar_type, ar_type_methods;

  ar = rb_const_get_at(rb_cObject, rb_intern("ActiveRecord"));

  // ActiveRecord::Type
  ar_type = rb_const_get_at(ar, rb_intern("Type"));

  ar_string_type = rb_const_get_at(ar_type, rb_intern("String"));
  ar_text_type = rb_const_get_at(ar_type, rb_intern("Text"));
  ar_float_type = rb_const_get_at(ar_type, rb_intern("Float"));
  ar_integer_type = rb_const_get_at(ar_type, rb_intern("Integer"));
  ar_boolean_type = rb_const_get_at(ar_type, rb_intern("Boolean"));
  ar_date_time_type = rb_const_get_at(ar_type, rb_intern("DateTime"));

  ar_type_methods = rb_class_instance_methods(0, NULL, ar_string_type);
  if (rb_ary_includes(ar_type_methods,
                      rb_to_symbol(rb_str_new_cstr("deserialize")))) {
    deserialize_from_db_id = rb_intern("deserialize");
  } else {
    deserialize_from_db_id = rb_intern("type_cast_from_database");
  }

  if (rb_const_defined(ar_type, rb_intern("Json"))) {
    ar_json_type = rb_const_get_at(ar_type, rb_intern("Json"));
  }

  // TODO: if we get error or not, add this to some debug log
  int isErrored;
  rb_protect(cache_postgres_type_lookup, ar, &isErrored);

  rb_protect(cache_time_zone_type_lookup, ar, &isErrored);
}

bool is_string_or_text_type(VALUE type_klass) {
  return type_klass == ar_string_type || type_klass == ar_text_type ||
         (ar_pg_uuid_type != Qundef && type_klass == ar_pg_uuid_type);
}

VALUE cast_string_or_text_type(VALUE value) {
  if (RB_TYPE_P(value, T_STRING)) {
    return value;
  }

  if (value == Qtrue) {
    return rb_str_new_cstr("t");
  }

  if (value == Qfalse) {
    return rb_str_new_cstr("f");
  }

  return rb_funcall(value, to_s_id, 0);
}

bool is_float_type(VALUE type_klass) {
  return type_klass == ar_float_type ||
         (ar_pg_float_type != Qundef && type_klass == ar_pg_float_type);
}

VALUE cast_float_type(VALUE value) {
  if (RB_TYPE_P(value, T_FLOAT)) {
    return value;
  }

  if (RB_TYPE_P(value, T_STRING)) {
    const char* val = StringValuePtr(value);
    return rb_float_new(strtod(val, NULL));
  }

  return Qundef;
}

bool is_integer_type(VALUE type_klass) {
  return type_klass == ar_integer_type ||
         (ar_pg_integer_type != Qundef && type_klass == ar_pg_integer_type);
}

VALUE cast_integer_type(VALUE value) {
  if (RB_INTEGER_TYPE_P(value)) {
    return value;
  }

  if (RB_TYPE_P(value, T_STRING)) {
    const char* val = StringValuePtr(value);
    if (strlen(val) == 0) {
      return Qnil;
    }
    return rb_cstr2inum(val, 10);
  }

  if (RB_FLOAT_TYPE_P(value)) {
    // We are calling the `to_i` here, because ruby internal
    // `flo_to_i` is not accessible
    return rb_funcall(value, to_i_id, 0);
  }

  if (value == Qtrue) {
    return INT2NUM(1);
  }

  if (value == Qfalse) {
    return INT2NUM(0);
  }

  // At this point, we handled integer, float, string and booleans
  // any thing other than this (array, hashes, etc) should result in nil
  return Qnil;
}

bool is_json_type(VALUE type_klass) {
  return ((ar_pg_json_type != Qundef && type_klass == ar_pg_json_type) ||
          (ar_json_type != Qundef && type_klass == ar_json_type));
}


bool is_boolean_type(VALUE type_klass) { return type_klass == ar_boolean_type; }

VALUE cast_boolean_type(VALUE value) {
  if (value == Qtrue || value == Qfalse) {
    return value;
  }

  if (value == Qnil) {
    return Qnil;
  }

  if (RB_TYPE_P(value, T_STRING)) {
    if (RSTRING_LEN(value) == 0) {
      return Qnil;
    }

    const char* val = StringValuePtr(value);

    bool isFalseValue =
        (*val == '0' || (*val == 'f' || *val == 'F') ||
         (strcmp(val, "false") == 0 || strcmp(val, "FALSE") == 0) ||
         (strcmp(val, "off") == 0 || strcmp(val, "OFF") == 0));

    return isFalseValue ? Qfalse : Qtrue;
  }

  if (RB_INTEGER_TYPE_P(value)) {
    return value == INT2NUM(1) ? Qtrue : Qfalse;
  }

  return Qundef;
}

bool is_date_time_type(VALUE type_klass) {
  return (type_klass == ar_date_time_type) ||
         (ar_pg_date_time_type != Qundef &&
          type_klass == ar_pg_date_time_type) ||
         (ar_time_zone_converter != Qundef &&
          type_klass == ar_time_zone_converter);
}

VALUE cast_date_time_type(VALUE value) {
  // Instead of take strings to comparing them to time zones
  // and then comparing them back to string
  // We will just make sure we have string on ISO8601 and it's utc
  if (RB_TYPE_P(value, T_STRING)) {
    const char* val = StringValuePtr(value);
    // 'Z' in ISO8601 says it's UTC
    if (val[strlen(val) - 1] == 'Z' && is_iso8601_time_string(value) == Qtrue) {
      return value;
    }

    volatile VALUE iso8601_string = iso_ar_iso_datetime_string(value);
    if (iso8601_string != Qnil) {
      return iso8601_string;
    }
  }

  return Qundef;
}

VALUE rescue_func() { return Qfalse; }

VALUE parse_json(VALUE value) { return rb_funcall(oj_type, oj_sc_parse_id, 2, rb_cObject, value); }

VALUE is_json_value(VALUE value) {
  if (!RB_TYPE_P(value, T_STRING)) {
    return value;
  }


  if(RSTRING_LEN(value) == 0) {
    return Qfalse;
  }

  volatile VALUE result =
      rb_rescue2(parse_json, value, rescue_func, Qundef, oj_parseerror_type, 0);

  if(NIL_P(result)) {
    return Qtrue;
  }

  if(result == Qfalse) {
    return Qfalse;
  }

  // TODO: fix me!
  return Qfalse;
}

VALUE type_cast(VALUE type_metadata, VALUE value, VALUE* isJson) {
  if (value == Qnil || value == Qundef) {
    return value;
  }

  cache_type_lookup();

  VALUE type_klass, typeCastedValue;


  type_klass = CLASS_OF(type_metadata);
  typeCastedValue = Qundef;

  TypeCast typeCast;
  for (typeCast = type_casts; typeCast->canCast != NULL; typeCast++) {
    if (typeCast->canCast(type_klass)) {
      typeCastedValue = typeCast->typeCast(value);
      break;
    }
  }

  if(is_json_type(type_klass)) {
    if(is_json_value(value) == Qfalse) {
      return Qnil;
    }
    *isJson = Qtrue;
    return value;
  }

  if (typeCastedValue == Qundef) {
    return rb_funcall(type_metadata, deserialize_from_db_id, 1, value);
  }

  return typeCastedValue;
}

VALUE public_type_cast(int argc, VALUE* argv, VALUE self) {
  VALUE type_metadata, value, isJson;
  rb_scan_args(argc, argv, "21", &type_metadata, &value, &isJson);

  if (isJson == Qnil || isJson == Qundef) {
    isJson = Qfalse;
  }

  return type_cast(type_metadata, value, &isJson);
}

void panko_init_type_cast(VALUE mPanko) {
  to_s_id = rb_intern("to_s");
  to_i_id = rb_intern("to_i");

  oj_type = rb_const_get_at(rb_cObject, rb_intern("Oj"));
  oj_parseerror_type = rb_const_get_at(oj_type, rb_intern("ParseError"));
  oj_sc_parse_id = rb_intern("sc_parse");


  // TODO: pass 3 arguments here
  rb_define_singleton_method(mPanko, "_type_cast", public_type_cast, -1);

  panko_init_time(mPanko);

  rb_global_variable(&oj_type);
  rb_global_variable(&oj_parseerror_type);
  rb_global_variable(&ar_string_type);
  rb_global_variable(&ar_text_type);
  rb_global_variable(&ar_float_type);
  rb_global_variable(&ar_integer_type);
  rb_global_variable(&ar_boolean_type);
  rb_global_variable(&ar_date_time_type);
  rb_global_variable(&ar_time_zone_converter);
  rb_global_variable(&ar_json_type);
  rb_global_variable(&ar_pg_integer_type);
  rb_global_variable(&ar_pg_float_type);
  rb_global_variable(&ar_pg_uuid_type);
  rb_global_variable(&ar_pg_json_type);
  rb_global_variable(&ar_pg_date_time_type);
}
