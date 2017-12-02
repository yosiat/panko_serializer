#include "association.h"

VALUE cAssociation;

static void association_free(void* ptr) {
  if (!ptr) {
    return;
  }

  Association association = (Association)ptr;
  association->name_str = Qnil;
  association->name_id = 0;
  association->name_sym = Qnil;
  association->rb_descriptor = Qnil;

  if (!association->descriptor || association->descriptor != NULL) {
    association->descriptor = NULL;
  }

  xfree(association);
}

void association_mark(Association data) {
  rb_gc_mark(data->name_str);
  rb_gc_mark(data->name_sym);
  rb_gc_mark(data->rb_descriptor);

  if (data->descriptor != NULL) {
    sd_mark(data->descriptor);
  }
}

static VALUE association_new(int argc, VALUE* argv, VALUE self) {
  Association association = ALLOC(struct _Association);

  Check_Type(argv[0], T_SYMBOL);
  Check_Type(argv[1], T_STRING);

  association->name_sym = argv[0];
  association->name_str = argv[1];
  association->rb_descriptor = argv[2];

  association->name_id = rb_intern_str(association->name_str);
  association->descriptor = sd_read(association->rb_descriptor);

  return Data_Wrap_Struct(cAssociation, association_mark, association_free,
                          association);
}

Association association_read(VALUE association) {
  return (Association)DATA_PTR(association);
}

VALUE association_first_ref(VALUE self) {
  Association association = (Association)DATA_PTR(self);
  return association->name_sym;
}

VALUE association_last_ref(VALUE self) {
  Association association = (Association)DATA_PTR(self);
  return association->rb_descriptor;
}

void panko_init_association(VALUE mPanko) {
  cAssociation = rb_define_class_under(mPanko, "Association", rb_cObject);

  rb_define_module_function(cAssociation, "new", association_new, -1);

  rb_define_method(cAssociation, "first", association_first_ref, 0);
  rb_define_method(cAssociation, "last", association_last_ref, 0);
}
