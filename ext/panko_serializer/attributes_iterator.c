#include "attributes_iterator.h"

static ID attributes_id;
static ID types_id;
static ID values_id;
static ID delegate_hash_id;

static ID value_before_type_cast_id;
static ID type_id;

VALUE read_attributes(VALUE obj) {
  return rb_ivar_get(obj, attributes_id);
}

VALUE panko_read_lazy_attributes_hash(VALUE object) {
  volatile VALUE attributes_set, attributes_hash;

  attributes_set = read_attributes(object);
  if (attributes_set == Qnil) {
    return Qnil;
  }

  attributes_hash = read_attributes(attributes_set);
  if (attributes_hash == Qnil) {
    return Qnil;
  }

  return attributes_hash;
}

void panko_read_types_and_value(VALUE attributes_hash,
                                VALUE* types,
                                VALUE* values) {
  *types = rb_ivar_get(attributes_hash, types_id);
  *values = rb_ivar_get(attributes_hash, values_id);
}

VALUE panko_each_attribute(VALUE obj,
                           VALUE attributes,
                           EachAttributeFunc func,
                           VALUE context) {
  volatile VALUE attributes_hash, delegate_hash;
  int i;

  attributes_hash = panko_read_lazy_attributes_hash(obj);
  if (attributes_hash == Qnil) {
    return Qnil;
  }

  delegate_hash = rb_ivar_get(attributes_hash, delegate_hash_id);
  bool tryToReadFromDelegateHash = RHASH_SIZE(delegate_hash) > 0;

  VALUE types, values;
  panko_read_types_and_value(attributes_hash, &types, &values);

  for (i = 0; i < RARRAY_LEN(attributes); i++) {
    volatile VALUE member = rb_sym2str(RARRAY_AREF(attributes, i));

    volatile VALUE value = Qundef;
    volatile VALUE type_metadata = Qnil;

    // First try to read from delegate hash,
    // If the object was create in memory `User.new(name: "Yosi")`
    // it won't exist in types/values
    if (tryToReadFromDelegateHash) {
      volatile VALUE attribute_metadata = rb_hash_aref(delegate_hash, member);
      if (attribute_metadata != Qnil) {
        value = rb_ivar_get(attribute_metadata, value_before_type_cast_id);
        type_metadata = rb_ivar_get(attribute_metadata, type_id);
      }
    }

    if (value == Qundef) {
      value = rb_hash_aref(values, member);
      type_metadata = rb_hash_aref(types, member);
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
  type_id = rb_intern("@type");
  value_before_type_cast_id = rb_intern("@value_before_type_cast");
}
