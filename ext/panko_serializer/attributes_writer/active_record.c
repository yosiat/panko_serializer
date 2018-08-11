#include "active_record.h"

static ID attributes_id;
static ID types_id;
static ID additional_types_id;
static ID values_id;
static ID delegate_hash_id;

static ID value_before_type_cast_id;
static ID type_id;

VALUE panko_read_lazy_attributes_hash(VALUE object) {
  volatile VALUE attributes_set, lazy_attributes_hash;

  attributes_set = rb_ivar_get(object, attributes_id);
  if (NIL_P(attributes_set)) {
    return Qnil;
  }

  lazy_attributes_hash = rb_ivar_get(attributes_set, attributes_id);
  return lazy_attributes_hash;
}

void panko_read_types_and_value(VALUE attributes_hash,
                                VALUE* types,
                                VALUE* additional_types,
                                VALUE* values) {
  *types = rb_ivar_get(attributes_hash, types_id);
  *additional_types = rb_ivar_get(attributes_hash, additional_types_id);
  *values = rb_ivar_get(attributes_hash, values_id);
}

void read_attribute_from_hash(VALUE attributes_hash,
                              VALUE member,
                              volatile VALUE* value,
                              volatile VALUE* type) {
  volatile VALUE attribute_metadata = rb_hash_aref(attributes_hash, member);
  if (attribute_metadata != Qnil) {
    *value = rb_ivar_get(attribute_metadata, value_before_type_cast_id);

    if (NIL_P(*type)) {
      *type = rb_ivar_get(attribute_metadata, type_id);
    }
  }
}

struct attributes {
  VALUE attributes_hash;

  VALUE types;
  VALUE additional_types;
  VALUE values;

  // heuristicts
  bool shouldReadFromHash;
  bool tryToReadFromAdditionalTypes;
};

struct attributes init_context(VALUE obj) {
  struct attributes attributes_ctx;
  attributes_ctx.attributes_hash = Qnil;
  attributes_ctx.values = Qnil;
  attributes_ctx.types = Qnil;
  attributes_ctx.additional_types = Qnil;

  attributes_ctx.shouldReadFromHash = false;
  attributes_ctx.tryToReadFromAdditionalTypes = false;

  volatile VALUE lazy_attribute_hash = panko_read_lazy_attributes_hash(obj);

  if (RB_TYPE_P(lazy_attribute_hash, T_HASH)) {
    attributes_ctx.attributes_hash = lazy_attribute_hash;
    attributes_ctx.shouldReadFromHash = true;
  } else {
    volatile VALUE delegate_hash =
        rb_ivar_get(lazy_attribute_hash, delegate_hash_id);
    if (!PANKO_EMPTY_HASH(delegate_hash)) {
      attributes_ctx.attributes_hash = delegate_hash;
      attributes_ctx.shouldReadFromHash = true;
    }

    panko_read_types_and_value(lazy_attribute_hash, &attributes_ctx.types,
                               &attributes_ctx.additional_types,
                               &attributes_ctx.values);

    attributes_ctx.tryToReadFromAdditionalTypes =
        !PANKO_EMPTY_HASH(attributes_ctx.additional_types);
  }

  return attributes_ctx;
}

VALUE read_attribute(struct attributes attributes_ctx, Attribute attribute) {
  VALUE member = attribute->name_str;
  volatile VALUE value = Qundef;

  if (!NIL_P(attributes_ctx.values)) {
    value = rb_hash_aref(attributes_ctx.values, member);
    if (NIL_P(value)) {
      value = Qundef;
    }
  }

  if (value == Qundef && attributes_ctx.shouldReadFromHash) {
    read_attribute_from_hash(attributes_ctx.attributes_hash, member, &value,
                             &attribute->type);
  }

  if (NIL_P(attribute->type) && !NIL_P(value)) {
    if (attributes_ctx.tryToReadFromAdditionalTypes) {
      attribute->type = rb_hash_aref(attributes_ctx.additional_types, member);
    }

    if (!NIL_P(attributes_ctx.types) && NIL_P(attribute->type)) {
      attribute->type = rb_hash_aref(attributes_ctx.types, member);
    }
  }

  if (!NIL_P(attribute->type) && !NIL_P(value)) {
    return type_cast(attribute->type, value);
  }

  return value;
}

VALUE active_record_attributes_writer(VALUE obj,
                                      VALUE attributes,
                                      EachAttributeFunc func,
                                      VALUE writer) {
  long i;
  struct attributes attributes_ctx = init_context(obj);
  volatile VALUE record_class = CLASS_OF(obj);

  for (i = 0; i < RARRAY_LEN(attributes); i++) {
    volatile VALUE raw_attribute = RARRAY_AREF(attributes, i);
    Attribute attribute = PANKO_ATTRIBUTE_READ(raw_attribute);
    attribute_try_invalidate(attribute, record_class);

    volatile VALUE value = read_attribute(attributes_ctx, attribute);

    func(writer, attr_name_for_serialization(attribute), value);
  }

  return Qnil;
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
