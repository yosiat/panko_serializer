#include "active_record.h"

static ID attributes_id;
static ID types_id;
static ID additional_types_id;
static ID values_id;
static ID delegate_hash_id;

static ID value_before_type_cast_id;
static ID type_id;

static bool type_detection_ran = false;
static bool is_lazy_attributes_set_defined = false;

/***
 * Returns ActiveModel::LazyAttributeSet or ActiveModel::LazyAttributesHash
 */
VALUE panko_read_attributes_container(VALUE object) {
  volatile VALUE attributes_set, lazy_attributes_hash;

  attributes_set = rb_ivar_get(object, attributes_id);
  if (NIL_P(attributes_set)) {
    return Qnil;
  }

  if (is_lazy_attributes_set_defined) {
    return attributes_set;
  }

  lazy_attributes_hash = rb_ivar_get(attributes_set, attributes_id);
  return lazy_attributes_hash;
}

struct attributes {
  VALUE attributes_hash;

  VALUE types;
  VALUE additional_types;
  VALUE values;

  // heuristicts
  bool tryToReadFromAdditionalTypes;
};

struct attributes init_context(VALUE obj) {
  struct attributes attributes_ctx;
  attributes_ctx.attributes_hash = Qnil;
  attributes_ctx.values = Qnil;
  attributes_ctx.types = Qnil;
  attributes_ctx.additional_types = Qnil;

  attributes_ctx.tryToReadFromAdditionalTypes = false;

  volatile VALUE attributes_container = panko_read_attributes_container(obj);

  if (RB_TYPE_P(attributes_container, T_HASH)) {
    attributes_ctx.attributes_hash = attributes_container;
  } else {
    if(is_lazy_attributes_set_defined == false) {
      volatile VALUE delegate_hash =
          rb_ivar_get(attributes_container, delegate_hash_id);

      if (PANKO_EMPTY_HASH(delegate_hash) == false) {
        attributes_ctx.attributes_hash = delegate_hash;
      }
    } else {
      volatile VALUE attributes_hash =
          rb_ivar_get(attributes_container, attributes_id);

      if (PANKO_EMPTY_HASH(attributes_hash) == false) {
        attributes_ctx.attributes_hash = attributes_hash;
      }
    }

    attributes_ctx.types = rb_ivar_get(attributes_container, types_id);
    attributes_ctx.values = rb_ivar_get(attributes_container, values_id);

    attributes_ctx.additional_types =
        rb_ivar_get(attributes_container, additional_types_id);
    attributes_ctx.tryToReadFromAdditionalTypes =
        PANKO_EMPTY_HASH(attributes_ctx.additional_types) == false;
  }

  return attributes_ctx;
}

VALUE read_attribute(struct attributes attributes_ctx, Attribute attribute, VALUE* isJson) {
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

VALUE detect_active_model_changes(VALUE v) {
  if (type_detection_ran == true) {
    return Qundef;
  }

  type_detection_ran = true;

  volatile VALUE active_model_type =
      rb_const_get_at(rb_cObject, rb_intern("ActiveModel"));

  is_lazy_attributes_set_defined =
    rb_const_defined(active_model_type, rb_intern("LazyAttributeSet")) > 0;

  return Qundef;
}

void active_record_attributes_writer(VALUE obj, VALUE attributes,
                                     EachAttributeFunc write_value, VALUE writer) {
  if (type_detection_ran == false) {
    // If ActiveModel can't be found it will throw error
    int isErrored;
    rb_protect(detect_active_model_changes, Qnil, &isErrored);
  }

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
