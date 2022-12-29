#include "attribute.h"

ID attribute_aliases_id = 0;
VALUE cAttribute;

static void attribute_free(void* ptr) {
  if (!ptr) {
    return;
  }

  Attribute attribute = (Attribute)ptr;
  attribute->name_str = Qnil;
  attribute->name_id = 0;
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

  Check_Type(argv[0], T_STRING);
  if (argv[1] != Qnil) {
    Check_Type(argv[1], T_STRING);
  }

  attribute->name_str = argv[0];
  attribute->name_id = rb_intern_str(attribute->name_str);
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
  if (attribute->record_class != new_record_class) {
    attribute->type = Qnil;
    attribute->record_class = new_record_class;

    // Once the record class is changed for this attribute, check if
    // we attribute_aliases (from ActivRecord), if so fill in
    // performance wise - this code should be called once (unless the serialzier
    // is polymorphic)
    volatile VALUE ar_aliases_hash =
        rb_funcall(new_record_class, attribute_aliases_id, 0);

    if (!PANKO_EMPTY_HASH(ar_aliases_hash)) {
      volatile VALUE aliasedValue =
          rb_hash_aref(ar_aliases_hash, attribute->name_str);
      if (aliasedValue != Qnil) {
        attribute->alias_name = attribute->name_str;
        attribute->name_str = aliasedValue;
        attribute->name_id = rb_intern_str(attribute->name_str);
      }
    }
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
  attribute_aliases_id = rb_intern("attribute_aliases");

  cAttribute = rb_define_class_under(mPanko, "Attribute", rb_cObject);
  rb_undef_alloc_func(cAttribute);
  rb_global_variable(&cAttribute);

  rb_define_module_function(cAttribute, "new", attribute_new, -1);

  rb_define_method(cAttribute, "name", attribute_name_ref, 0);
  rb_define_method(cAttribute, "alias_name", attribute_alias_name_ref, 0);
}
