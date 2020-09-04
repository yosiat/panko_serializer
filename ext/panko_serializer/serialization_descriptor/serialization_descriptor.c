#include "serialization_descriptor.h"

VALUE cSerializationDescriptor;

static ID object_id;
static ID sc_id;

static void sd_free(SerializationDescriptor sd) {
  if (!sd) {
    return;
  }

  sd->serializer_type = Qnil;
  sd->serializer = Qnil;
  sd->attributes = Qnil;
  sd->method_fields = Qnil;
  sd->has_one_associations = Qnil;
  sd->has_many_associations = Qnil;
  sd->aliases = Qnil;
  xfree(sd);
}

void sd_mark(SerializationDescriptor data) {
  rb_gc_mark(data->serializer_type);
  rb_gc_mark(data->serializer);
  rb_gc_mark(data->attributes);
  rb_gc_mark(data->method_fields);
  rb_gc_mark(data->has_one_associations);
  rb_gc_mark(data->has_many_associations);
  rb_gc_mark(data->aliases);
}

static VALUE sd_alloc(VALUE klass) {
  SerializationDescriptor sd = ALLOC(struct _SerializationDescriptor);

  sd->serializer = Qnil;
  sd->serializer_type = Qnil;
  sd->attributes = Qnil;
  sd->method_fields = Qnil;
  sd->has_one_associations = Qnil;
  sd->has_many_associations = Qnil;
  sd->aliases = Qnil;

  sd->attributes_writer = create_empty_attributes_writer();

  return Data_Wrap_Struct(cSerializationDescriptor, sd_mark, sd_free, sd);
}

SerializationDescriptor sd_read(VALUE descriptor) {
  return (SerializationDescriptor)DATA_PTR(descriptor);
}

void sd_set_writer(SerializationDescriptor sd, VALUE object) {
  if (sd->attributes_writer.object_type != Unknown) {
    return;
  }

  sd->attributes_writer = create_attributes_writer(object);
}

VALUE sd_serializer_set(VALUE self, VALUE serializer) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);

  sd->serializer = serializer;
  return Qnil;
}

VALUE sd_serializer_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);

  return sd->serializer;
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

VALUE sd_method_fields_set(VALUE self, VALUE method_fields) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->method_fields = method_fields;
  return Qnil;
}

VALUE sd_method_fields_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->method_fields;
}

VALUE sd_has_one_associations_set(VALUE self, VALUE has_one_associations) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->has_one_associations = has_one_associations;
  return Qnil;
}

VALUE sd_has_one_associations_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->has_one_associations;
}

VALUE sd_has_many_associations_set(VALUE self, VALUE has_many_associations) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->has_many_associations = has_many_associations;
  return Qnil;
}

VALUE sd_has_many_associations_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->has_many_associations;
}

VALUE sd_type_set(VALUE self, VALUE type) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->serializer_type = type;
  return Qnil;
}

VALUE sd_type_aref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->serializer_type;
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

  cSerializationDescriptor =
      rb_define_class_under(mPanko, "SerializationDescriptor", rb_cObject);

  rb_define_alloc_func(cSerializationDescriptor, sd_alloc);
  rb_define_method(cSerializationDescriptor, "serializer=", sd_serializer_set,
                   1);
  rb_define_method(cSerializationDescriptor, "serializer", sd_serializer_ref,
                   0);

  rb_define_method(cSerializationDescriptor, "attributes=", sd_attributes_set,
                   1);
  rb_define_method(cSerializationDescriptor, "attributes", sd_attributes_ref,
                   0);

  rb_define_method(cSerializationDescriptor,
                   "method_fields=", sd_method_fields_set, 1);
  rb_define_method(cSerializationDescriptor, "method_fields",
                   sd_method_fields_ref, 0);

  rb_define_method(cSerializationDescriptor,
                   "has_one_associations=", sd_has_one_associations_set, 1);
  rb_define_method(cSerializationDescriptor, "has_one_associations",
                   sd_has_one_associations_ref, 0);

  rb_define_method(cSerializationDescriptor,
                   "has_many_associations=", sd_has_many_associations_set, 1);
  rb_define_method(cSerializationDescriptor, "has_many_associations",
                   sd_has_many_associations_ref, 0);

  rb_define_method(cSerializationDescriptor, "type=", sd_type_set, 1);
  rb_define_method(cSerializationDescriptor, "type", sd_type_aref, 0);

  rb_define_method(cSerializationDescriptor, "aliases=", sd_aliases_set, 1);
  rb_define_method(cSerializationDescriptor, "aliases", sd_aliases_aref, 0);
}
