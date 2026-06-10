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

static void association_mark(void* data) {
  Association association = data;

  rb_gc_mark(association->name_str);
  rb_gc_mark(association->name_sym);
  rb_gc_mark(association->rb_descriptor);

  if (association->descriptor != NULL) {
    sd_mark(association->descriptor);
  }
}

static size_t association_memsize(const void* data) {
  return data ? sizeof(struct _Association) : 0;
}

static const rb_data_type_t association_data_type = {
    "Panko::Association",
    {
        association_mark,
        association_free,
        association_memsize,
    },
    0,
    0,
    0,
};

static VALUE association_new(int argc, VALUE* argv, VALUE self) {
  Association association;
  VALUE obj;

  Check_Type(argv[0], T_SYMBOL);
  Check_Type(argv[1], T_STRING);

  obj = TypedData_Make_Struct(cAssociation, struct _Association,
                              &association_data_type, association);
  association->name_sym = argv[0];
  association->name_str = argv[1];
  association->rb_descriptor = argv[2];

  association->name_id = rb_intern_str(rb_sym2str(association->name_sym));
  association->descriptor = sd_read(association->rb_descriptor);

  return obj;
}

Association association_read(VALUE association) {
  Association ptr;

  TypedData_Get_Struct(association, struct _Association, &association_data_type,
                       ptr);

  return ptr;
}

VALUE association_name_sym_ref(VALUE self) {
  Association association = association_read(self);
  return association->name_sym;
}

VALUE association_name_str_ref(VALUE self) {
  Association association = association_read(self);
  return association->name_str;
}

VALUE association_descriptor_ref(VALUE self) {
  Association association = association_read(self);
  return association->rb_descriptor;
}

VALUE association_decriptor_aset(VALUE self, VALUE descriptor) {
  Association association = association_read(self);

  association->rb_descriptor = descriptor;
  association->descriptor = sd_read(descriptor);

  return association->rb_descriptor;
}

void panko_init_association(VALUE mPanko) {
  cAssociation = rb_define_class_under(mPanko, "Association", rb_cObject);
  rb_undef_alloc_func(cAssociation);
  rb_global_variable(&cAssociation);

  rb_define_module_function(cAssociation, "new", association_new, -1);

  rb_define_method(cAssociation, "name_sym", association_name_sym_ref, 0);
  rb_define_method(cAssociation, "name_str", association_name_str_ref, 0);
  rb_define_method(cAssociation, "descriptor", association_descriptor_ref, 0);
  rb_define_method(cAssociation, "descriptor=", association_decriptor_aset, 1);
}
