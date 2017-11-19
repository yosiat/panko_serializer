#include "attributes_iterator.h"

static ID attributes_id;
static ID types_id;
static ID additional_types_id;
static ID values_id;
static ID delegate_hash_id;

static ID value_before_type_cast_id;
static ID type_id;

VALUE read_attributes(VALUE obj) {
  return rb_ivar_get(obj, attributes_id);
}

VALUE panko_read_lazy_attributes_hash(VALUE object) {
  volatile VALUE attributes_set, lazy_attributes_hash;

  attributes_set = read_attributes(object);
  if (attributes_set == Qnil) {
    return Qnil;
  }

  lazy_attributes_hash = read_attributes(attributes_set);
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

bool panko_is_empty_hash(VALUE hash) {
  if (hash == Qnil || hash == Qundef) {
    return true;
  }

  return RHASH_SIZE(hash) == 0;
}

void read_attribute_from_hash(VALUE attributes_hash,
                              VALUE member,
                              volatile VALUE* value,
                              volatile VALUE* type) {
  volatile VALUE attribute_metadata = rb_hash_aref(attributes_hash, member);
  if (attribute_metadata != Qnil) {
    *value = rb_ivar_get(attribute_metadata, value_before_type_cast_id);

    if (*type == Qnil) {
      *type = rb_ivar_get(attribute_metadata, type_id);
      if (*type != Qnil) {
        *type = CLASS_OF(*type);
      }
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

  if (lazy_attribute_hash == Qnil) {
    // TODO: handle
  }

  if (RB_TYPE_P(lazy_attribute_hash, T_HASH)) {
    attributes_ctx.attributes_hash = lazy_attribute_hash;
    attributes_ctx.shouldReadFromHash = true;
  } else {
    volatile VALUE delegate_hash =
        rb_ivar_get(lazy_attribute_hash, delegate_hash_id);
    if (!panko_is_empty_hash(delegate_hash)) {
      attributes_ctx.attributes_hash = delegate_hash;
      attributes_ctx.shouldReadFromHash = true;
    }

    panko_read_types_and_value(lazy_attribute_hash, &attributes_ctx.types,
                               &attributes_ctx.additional_types,
                               &attributes_ctx.values);

    attributes_ctx.tryToReadFromAdditionalTypes =
        !panko_is_empty_hash(attributes_ctx.additional_types);
  }

  return attributes_ctx;
}

VALUE read_attribute(struct attributes attributes_ctx, Attribute attribute) {
  VALUE member = attribute->name_str;
  volatile VALUE value = Qundef;

  if (attributes_ctx.values != Qnil && value == Qundef) {
    value = rb_hash_aref(attributes_ctx.values, member);
    if (value == Qnil) {
      value = Qundef;
    }
  }

  if (value == Qundef && attributes_ctx.shouldReadFromHash) {
    read_attribute_from_hash(attributes_ctx.attributes_hash, member, &value,
                             &attribute->type);
  }

  if (attribute->type == Qnil) {
    if (attributes_ctx.tryToReadFromAdditionalTypes) {
      attribute->type = rb_hash_aref(attributes_ctx.additional_types, member);
    }

    if (attributes_ctx.types != Qnil && attribute->type == Qnil) {
      attribute->type = rb_hash_aref(attributes_ctx.types, member);
    }

    if (attribute->type != Qnil) {
      attribute->type = CLASS_OF(attribute->type);
    }
  }

  if (attribute->type != Qnil && value != Qnil) {
    return type_cast(attribute->type, value);
  }

  return value;
}

VALUE panko_each_attribute(VALUE obj,
                           VALUE attributes,
                           EachAttributeFunc func,
                           VALUE context) {
  long i;
  struct attributes attributes_ctx = init_context(obj);
  volatile VALUE record_class = CLASS_OF(obj);

  for (i = 0; i < RARRAY_LEN(attributes); i++) {
    volatile VALUE raw_attribute = RARRAY_AREF(attributes, i);
    Attribute attribute = attribute_read(raw_attribute);
    attribute_try_invalidate(attribute, record_class);

    VALUE name_str = attribute->name_str;
    if (attribute->alias_name != Qnil) {
      name_str = attribute->alias_name;
    }

    VALUE value = read_attribute(attributes_ctx, attribute);

    func(obj, name_str, value, Qnil, context);
  }

  return Qnil;
}

void panko_init_attributes_iterator(VALUE mPanko) {
  attributes_id = rb_intern("@attributes");
  delegate_hash_id = rb_intern("@delegate_hash");
  values_id = rb_intern("@values");
  types_id = rb_intern("@types");
  additional_types_id = rb_intern("@additional_types");
  type_id = rb_intern("@type");
  value_before_type_cast_id = rb_intern("@value_before_type_cast");
}
