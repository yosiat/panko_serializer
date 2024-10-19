#include "active_record.h"

static ID attributes_id;
static ID types_id;
static ID additional_types_id;
static ID values_id;
static ID delegate_hash_id;

static ID value_before_type_cast_id;
static ID type_id;

struct attributes {
  VALUE attributes_hash;

  VALUE types;
  VALUE additional_types;
  VALUE values;

  // heuristics
  bool tryToReadFromAdditionalTypes;
};

struct attributes init_context(VALUE obj) {
  volatile VALUE attributes_set = rb_ivar_get(obj, attributes_id);
  volatile VALUE attributes_hash = rb_ivar_get(attributes_set, attributes_id);

  return (struct attributes){
      .attributes_hash =
          PANKO_EMPTY_HASH(attributes_hash) ? Qnil : attributes_hash,
      .types = rb_ivar_get(attributes_set, types_id),
      .values = rb_ivar_get(attributes_set, values_id),
      .additional_types = rb_ivar_get(attributes_set, additional_types_id),
      .tryToReadFromAdditionalTypes =
          PANKO_EMPTY_HASH(rb_ivar_get(attributes_set, additional_types_id)) ==
          false};
}

VALUE read_attribute(struct attributes attributes_ctx, Attribute attribute,
                     volatile VALUE* isJson) {
  volatile VALUE member, value;

  member = attribute->name_str;
  value = Qnil;

  if (!NIL_P(attributes_ctx.attributes_hash)) {
    volatile VALUE attribute_metadata =
        rb_hash_aref(attributes_ctx.attributes_hash, member);

    if (attribute_metadata != Qnil) {
      value = rb_ivar_get(attribute_metadata, value_before_type_cast_id);

      if (NIL_P(attribute->type)) {
        attribute->type = rb_ivar_get(attribute_metadata, type_id);
      }
    }
  }

  if (NIL_P(value) && !NIL_P(attributes_ctx.values)) {
    value = rb_hash_aref(attributes_ctx.values, member);
  }

  if (NIL_P(attribute->type) && !NIL_P(value)) {
    if (attributes_ctx.tryToReadFromAdditionalTypes == true) {
      attribute->type = rb_hash_aref(attributes_ctx.additional_types, member);
    }

    if (!NIL_P(attributes_ctx.types) && NIL_P(attribute->type)) {
      attribute->type = rb_hash_aref(attributes_ctx.types, member);
    }
  }

  if (!NIL_P(attribute->type) && !NIL_P(value)) {
    return type_cast(attribute->type, value, isJson);
  }

  return value;
}

void active_record_attributes_writer(VALUE obj, VALUE attributes,
                                     EachAttributeFunc write_value,
                                     VALUE writer) {
  long i;
  struct attributes attributes_ctx = init_context(obj);
  volatile VALUE record_class = CLASS_OF(obj);

  for (i = 0; i < RARRAY_LEN(attributes); i++) {
    volatile VALUE raw_attribute = RARRAY_AREF(attributes, i);
    Attribute attribute = PANKO_ATTRIBUTE_READ(raw_attribute);
    attribute_try_invalidate(attribute, record_class);

    volatile VALUE isJson = Qfalse;
    volatile VALUE value = read_attribute(attributes_ctx, attribute, &isJson);

    write_value(writer, attr_name_for_serialization(attribute), value, isJson);
  }
}

void init_active_record_attributes_writer(VALUE mPanko) {
  attributes_id = rb_intern("@attributes");
  delegate_hash_id = rb_intern("@delegate_hash");
  values_id = rb_intern("@values");
  types_id = rb_intern("@types");
  additional_types_id = rb_intern("@additional_types");
  type_id = rb_intern("@type");
  value_before_type_cast_id = rb_intern("@value_before_type_cast");
}
