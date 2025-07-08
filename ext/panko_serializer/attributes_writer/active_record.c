#include "active_record.h"

static ID attributes_id;
static ID types_id;
static ID additional_types_id;
static ID values_id;
static ID delegate_hash_id;

static ID value_before_type_cast_id;
static ID type_id;

static ID fetch_id;

// ActiveRecord::Result::IndexedRow
static VALUE ar_result_indexed_row = Qundef;
static int fetched_ar_result_indexed_row = 0;

VALUE fetch_ar_result_indexed_row_type() {
  if (fetched_ar_result_indexed_row == 1) {
    return ar_result_indexed_row;
  }

  fetched_ar_result_indexed_row = 1;

  VALUE ar, ar_result;

  ar = rb_const_get_at(rb_cObject, rb_intern("ActiveRecord"));

  // ActiveRecord::Result
  ar_result = rb_const_get_at(ar, rb_intern("Result"));

  if (rb_const_defined_at(ar_result, rb_intern("IndexedRow")) == (int)Qtrue) {
    ar_result_indexed_row = rb_const_get_at(ar_result, rb_intern("IndexedRow"));
  }

  return ar_result_indexed_row;
}

struct attributes {
  // Hash
  VALUE attributes_hash;
  size_t attributes_hash_size;

  // Hash
  VALUE types;
  // Hash
  VALUE additional_types;
  // heuristics
  bool tryToReadFromAdditionalTypes;

  // Rails <8: Hash
  // Rails >=8: ActiveRecord::Result::IndexedRow
  VALUE values;

  // Hash
  VALUE indexed_row_column_indexes;
  // Array or NIL
  VALUE indexed_row_row;
  bool is_indexed_row;
};

struct attributes init_context(VALUE obj) {
  volatile VALUE attributes_set = rb_ivar_get(obj, attributes_id);
  volatile VALUE attributes_hash = rb_ivar_get(attributes_set, attributes_id);

  struct attributes attrs = (struct attributes){
      .attributes_hash =
          PANKO_EMPTY_HASH(attributes_hash) ? Qnil : attributes_hash,
      .attributes_hash_size = 0,
      .types = rb_ivar_get(attributes_set, types_id),
      .additional_types = rb_ivar_get(attributes_set, additional_types_id),
      .tryToReadFromAdditionalTypes =
          PANKO_EMPTY_HASH(rb_ivar_get(attributes_set, additional_types_id)) ==
          false,
      .values = rb_ivar_get(attributes_set, values_id),
      .is_indexed_row = false,
      .indexed_row_column_indexes = Qnil,
      .indexed_row_row = Qnil,
  };

  if (attrs.attributes_hash != Qnil) {
    attrs.attributes_hash_size = RHASH_SIZE(attrs.attributes_hash);
  }

  if (CLASS_OF(attrs.values) == fetch_ar_result_indexed_row_type()) {
    volatile VALUE indexed_row_column_indexes =
        rb_ivar_get(attrs.values, rb_intern("@column_indexes"));
    volatile VALUE indexed_row_row =
        rb_ivar_get(attrs.values, rb_intern("@row"));

    attrs.indexed_row_column_indexes = indexed_row_column_indexes;
    attrs.indexed_row_row = indexed_row_row;
    attrs.is_indexed_row = true;
    rb_p(CLASS_OF(attrs.values));
  } else {
    rb_p(attrs.values);
    rb_p(CLASS_OF(attrs.values));
    rb_p(fetch_ar_result_indexed_row_type());
  }

  return attrs;
}

VALUE _read_value_from_indexed_row(struct attributes attributes_ctx,
                                   volatile VALUE member) {
  volatile VALUE value = Qnil;

  if (NIL_P(attributes_ctx.indexed_row_column_indexes) ||
      NIL_P(attributes_ctx.indexed_row_row)) {
    return value;
  }

  volatile VALUE column_index =
      rb_hash_aref(attributes_ctx.indexed_row_column_indexes, member);

  if (NIL_P(column_index)) {
    return value;
  }

  volatile VALUE row = attributes_ctx.indexed_row_row;
  if (NIL_P(row)) {
    return value;
  }

  return RARRAY_AREF(row, NUM2INT(column_index));
}

VALUE read_attribute(struct attributes attributes_ctx, Attribute attribute,
                     volatile VALUE* isJson) {
  volatile VALUE member, value;

  member = attribute->name_str;
  value = Qnil;

  if (
      // we have attributes_hash
      !NIL_P(attributes_ctx.attributes_hash)
      // It's not empty
      && (attributes_ctx.attributes_hash_size > 0)) {
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
    if (attributes_ctx.is_indexed_row == true) {
      value = _read_value_from_indexed_row(attributes_ctx, member);
    } else {
      value = rb_hash_aref(attributes_ctx.values, member);
    }
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
  fetch_id = rb_intern("fetch");
}

void panko_init_active_record(VALUE mPanko) {
  init_active_record_attributes_writer(mPanko);
  panko_init_type_cast(mPanko);
}