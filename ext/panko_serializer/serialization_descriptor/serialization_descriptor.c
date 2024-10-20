#include "serialization_descriptor.h"

static ID object_id;
static ID sc_id;

static void sd_free(SerializationDescriptor sd) {
  if (!sd) {
    return;
  }

  sd->attributes = Qnil;
  sd->aliases = Qnil;
  xfree(sd);
}

void sd_mark(SerializationDescriptor data) {
  rb_gc_mark(data->attributes);
  rb_gc_mark(data->aliases);
}

static VALUE sd_alloc(VALUE klass) {
  SerializationDescriptor sd = ALLOC(struct _SerializationDescriptor);

  sd->attributes = Qnil;
  sd->aliases = Qnil;

  sd->attributes_writer = create_empty_attributes_writer();

  return Data_Wrap_Struct(klass, sd_mark, sd_free, sd);
}

SerializationDescriptor sd_read(VALUE descriptor) {
  return (SerializationDescriptor)DATA_PTR(descriptor);
}

void sd_set_writer(SerializationDescriptor sd, VALUE object) {
  if (sd->attributes_writer.object_type != UnknownObjectType) {
    return;
  }

  sd->attributes_writer = create_attributes_writer(object);
}

VALUE sd_attributes_set(VALUE self, VALUE attributes) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);

  sd->attributes = attributes;
  return Qnil;
}

VALUE sd_attributes_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->attributes;
}

VALUE sd_aliases_set(VALUE self, VALUE aliases) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->aliases = aliases;
  return Qnil;
}

VALUE sd_aliases_aref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->aliases;
}

void panko_init_serialization_descriptor(VALUE mPanko) {
  object_id = rb_intern("@object");
  sc_id = rb_intern("@sc");

  VALUE cSerializationDescriptor =
      rb_define_class_under(mPanko, "SerializationDescriptor", rb_cObject);

  rb_define_alloc_func(cSerializationDescriptor, sd_alloc);

  rb_define_method(cSerializationDescriptor, "attributes=", sd_attributes_set,
                   1);
  rb_define_method(cSerializationDescriptor, "attributes", sd_attributes_ref,
                   0);

  rb_define_method(cSerializationDescriptor, "aliases=", sd_aliases_set, 1);
  rb_define_method(cSerializationDescriptor, "aliases", sd_aliases_aref, 0);
}
