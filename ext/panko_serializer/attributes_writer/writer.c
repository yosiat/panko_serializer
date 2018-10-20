#include "writer.h"

static bool types_initialized = false;
static VALUE ar_base_type = Qundef;

VALUE init_types(VALUE v) {
  if (types_initialized == true) {
    return Qundef;
  }

  types_initialized = true;

  volatile VALUE ar_type =
      rb_const_get_at(rb_cObject, rb_intern("ActiveRecord"));
  ar_base_type = rb_const_get_at(ar_type, rb_intern("Base"));

  return Qundef;
}

AttributesWriter create_attributes_writer(VALUE subject) {
  // If ActiveRecord::Base can't be found it will throw error
  int isErrored;
  rb_protect(init_types, Qnil, &isErrored);

  if (ar_base_type != Qundef &&
      rb_obj_is_kind_of(subject, ar_base_type) == Qtrue) {
    return (AttributesWriter){
        .object_type = ActiveRecord,
        .write_attributes = active_record_attributes_writer};
  } else {
    return (AttributesWriter){.object_type = Plain,
                              .write_attributes = plain_attributes_writer};
  }

  return create_empty_attributes_writer();
}

void empty_write_attributes(VALUE obj,
                            VALUE attributes,
                            EachAttributeFunc func,
                            VALUE writer) {}

AttributesWriter create_empty_attributes_writer() {
  return (AttributesWriter){.object_type = Unknown,
                            .write_attributes = empty_write_attributes};
}

void init_attributes_writer(VALUE mPanko) {
  init_active_record_attributes_writer(mPanko);
}
