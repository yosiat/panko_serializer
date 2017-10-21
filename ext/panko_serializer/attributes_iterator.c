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
    *type = rb_ivar_get(attribute_metadata, type_id);
  }
}

VALUE panko_each_attribute(VALUE obj,
                           VALUE attributes,
                           VALUE aliases,
                           EachAttributeFunc func,
                           VALUE context) {
  volatile VALUE lazy_attribute_hash, delegate_hash;
  VALUE values = Qundef;
  VALUE types = Qundef;
  VALUE additional_types = Qundef;
  int i;

  lazy_attribute_hash = panko_read_lazy_attributes_hash(obj);
  if (lazy_attribute_hash == Qnil) {
    return Qnil;
  }

  bool tryToReadFromDelegateHash = false;
  bool tryToReadFromAdditionalTypes = false;

  // If lazy_attribute_hash is not ActiveRecord::LazyAttributeHash
  // and it's actually hash, read from it
  if (RB_TYPE_P(lazy_attribute_hash, T_HASH)) {
    delegate_hash = lazy_attribute_hash;
    tryToReadFromDelegateHash = true;
  } else {
    delegate_hash = rb_ivar_get(lazy_attribute_hash, delegate_hash_id);
    tryToReadFromDelegateHash = !panko_is_empty_hash(delegate_hash);

    panko_read_types_and_value(lazy_attribute_hash, &types, &additional_types,
                               &values);

    tryToReadFromAdditionalTypes = !panko_is_empty_hash(additional_types);
  }

  bool tryToReadFromAliases = !panko_is_empty_hash(aliases);

  for (i = 0; i < RARRAY_LEN(attributes); i++) {
    volatile VALUE member_raw = RARRAY_AREF(attributes, i);
    volatile VALUE member = rb_sym2str(member_raw);

    volatile VALUE value = Qundef;
    volatile VALUE type_metadata = Qnil;

    // First try to read from delegate hash,
    // If the object was create in memory `User.new(name: "Yosi")`
    // it won't exist in types/values
    if (tryToReadFromDelegateHash) {
      read_attribute_from_hash(delegate_hash, member, &value, &type_metadata);
    }

    if (values != Qundef && value == Qundef) {
      value = rb_hash_aref(values, member);

      if (tryToReadFromAdditionalTypes) {
        type_metadata = rb_hash_aref(additional_types, member);
      }
      if (type_metadata == Qnil) {
        type_metadata = rb_hash_aref(types, member);
      }
    }

    if (tryToReadFromAliases) {
      volatile VALUE alias_name = rb_hash_aref(aliases, member_raw);
      if (alias_name != Qnil) {
        member = rb_sym2str(alias_name);
      }
    }

    func(obj, member, value, type_metadata, context);
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
