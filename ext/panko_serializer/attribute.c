#include "attribute.h"

VALUE cAttribute;

static void attribute_free(void* ptr) {
  if (!ptr) {
    return;
  }

  Attribute attribute = (Attribute)ptr;
  attribute->name_str = Qnil;
  attribute->alias_name = Qnil;
  attribute->type = Qnil;
  attribute->record_class = Qnil;

  xfree(attribute);
}

void attribute_mark(Attribute data) {
  rb_gc_mark(data->name_str);
  rb_gc_mark(data->alias_name);
  rb_gc_mark(data->type);
  rb_gc_mark(data->record_class);
}

static VALUE attribute_new(int argc, VALUE* argv, VALUE self) {
  Attribute attribute = ALLOC(struct _Attribute);

  attribute->name_str = argv[0];
  attribute->alias_name = argv[1];
  attribute->type = Qnil;
  attribute->record_class = Qnil;

  return Data_Wrap_Struct(cAttribute, attribute_mark, attribute_free,
                          attribute);
}

Attribute attribute_read(VALUE attribute) {
  return (Attribute)DATA_PTR(attribute);
}

void attribute_try_invalidate(Attribute attribute, VALUE new_record_class) {
  if (rb_equal(attribute->record_class, new_record_class) == Qfalse) {
    attribute->type = Qnil;
    attribute->record_class = new_record_class;
  }
}

VALUE attribute_name_ref(VALUE self) {
  Attribute attribute = (Attribute)DATA_PTR(self);
  return attribute->name_str;
}

VALUE attribute_alias_name_ref(VALUE self) {
  Attribute attribute = (Attribute)DATA_PTR(self);
  return attribute->alias_name;
}
void panko_init_attribute(VALUE mPanko) {
  cAttribute = rb_define_class_under(mPanko, "Attribute", rb_cObject);

  rb_define_module_function(cAttribute, "new", attribute_new, -1);

  rb_define_method(cAttribute, "name", attribute_name_ref, 0);
  rb_define_method(cAttribute, "alias_name", attribute_alias_name_ref, 0);
}
