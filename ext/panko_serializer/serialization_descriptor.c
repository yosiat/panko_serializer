#include "serialization_descriptor.h"

VALUE cSerializationDescriptor;

static ID context_id;
static ID object_id;

static void serialization_descriptor_free(void* ptr) {
  SerializationDescriptor sd;
  if (ptr == 0) {
    return;
  }

  sd = (SerializationDescriptor)ptr;
  sd->serializer_type = Qnil;
  sd->serializer = Qnil;
  sd->fields = Qnil;
  sd->method_fields = Qnil;
  sd->has_one_associations = Qnil;
  sd->has_many_associations = Qnil;
  sd->aliases = Qnil;
}

void serialization_descriptor_mark(SerializationDescriptor data) {
  rb_gc_mark(data->serializer_type);
  rb_gc_mark(data->serializer);
  rb_gc_mark(data->fields);
  rb_gc_mark(data->method_fields);
  rb_gc_mark(data->has_one_associations);
  rb_gc_mark(data->has_many_associations);
  rb_gc_mark(data->aliases);
}

static VALUE serialization_descriptor_new(int argc, VALUE* argv, VALUE self) {
  SerializationDescriptor sd = ALLOC(struct _SerializationDescriptor);

  sd->serializer = Qnil;
  sd->serializer_type = Qnil;
  sd->fields = Qnil;
  sd->method_fields = Qnil;
  sd->has_one_associations = Qnil;
  sd->has_many_associations = Qnil;
  sd->aliases = Qnil;

  return Data_Wrap_Struct(cSerializationDescriptor,
                          serialization_descriptor_mark,
                          serialization_descriptor_free, sd);
}

SerializationDescriptor sd_read(VALUE descriptor) {
  return (SerializationDescriptor)DATA_PTR(descriptor);
}

VALUE sd_build_serializer(SerializationDescriptor sd) {
  // We build the serializer and cache it on demand,
  // because of our cache - we lock and create descriptor, while inside
  // a descriptor we can't create another descriptor - deadlock.
  if (sd->serializer == Qnil) {
    VALUE args[0];
    sd->serializer = rb_class_new_instance(0, args, sd->serializer_type);
  }

  return sd->serializer;
}

void sd_apply_serializer_config(VALUE serializer, VALUE object, VALUE context) {
  rb_ivar_set(serializer, object_id, object);
  rb_ivar_set(serializer, context_id, context);
}

VALUE serialization_descriptor_fields_set(VALUE self, VALUE fields) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);

  sd->fields = fields;
  return Qnil;
}

VALUE serialization_descriptor_fields_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->fields;
}

VALUE serialization_descriptor_method_fields_set(VALUE self,
                                                 VALUE method_fields) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->method_fields = method_fields;
  return Qnil;
}

VALUE serialization_descriptor_method_fields_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->method_fields;
}

VALUE serialization_descriptor_has_one_associations_set(
    VALUE self,
    VALUE has_one_associations) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->has_one_associations = has_one_associations;
  return Qnil;
}

VALUE serialization_descriptor_has_one_associations_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->has_one_associations;
}

VALUE serialization_descriptor_has_many_associations_set(
    VALUE self,
    VALUE has_many_associations) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->has_many_associations = has_many_associations;
  return Qnil;
}

VALUE serialization_descriptor_has_many_associations_ref(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->has_many_associations;
}

VALUE serialization_descriptor_type_set(VALUE self, VALUE type) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->serializer_type = type;
  return Qnil;
}

VALUE serialization_descriptor_type_aref(VALUE self, VALUE type) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->serializer_type;
}

VALUE serialization_descriptor_aliases_set(VALUE self, VALUE aliases) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  sd->aliases = aliases;
  return Qnil;
}

VALUE serialization_descriptor_aliases_aref(VALUE self, VALUE aliases) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd->aliases;
}

// Exposing this for testing
VALUE serialization_descriptor_build_serializer(VALUE self) {
  SerializationDescriptor sd = (SerializationDescriptor)DATA_PTR(self);
  return sd_build_serializer(sd);
}

void panko_init_serialization_descriptor(VALUE mPanko) {
  object_id = rb_intern("@object");
  context_id = rb_intern("@context");

  cSerializationDescriptor =
      rb_define_class_under(mPanko, "SerializationDescriptor", rb_cObject);

  rb_define_module_function(cSerializationDescriptor, "new",
                            serialization_descriptor_new, -1);

  rb_define_method(cSerializationDescriptor,
                   "fields=", serialization_descriptor_fields_set, 1);
  rb_define_method(cSerializationDescriptor, "fields",
                   serialization_descriptor_fields_ref, 0);

  rb_define_method(cSerializationDescriptor,
                   "method_fields=", serialization_descriptor_method_fields_set,
                   1);
  rb_define_method(cSerializationDescriptor, "method_fields",
                   serialization_descriptor_method_fields_ref, 0);

  rb_define_method(cSerializationDescriptor, "has_one_associations=",
                   serialization_descriptor_has_one_associations_set, 1);
  rb_define_method(cSerializationDescriptor, "has_one_associations",
                   serialization_descriptor_has_one_associations_ref, 0);

  rb_define_method(cSerializationDescriptor, "has_many_associations=",
                   serialization_descriptor_has_many_associations_set, 1);
  rb_define_method(cSerializationDescriptor, "has_many_associations",
                   serialization_descriptor_has_many_associations_ref, 0);

  rb_define_method(cSerializationDescriptor,
                   "type=", serialization_descriptor_type_set, 1);
  rb_define_method(cSerializationDescriptor, "type",
                   serialization_descriptor_type_aref, 0);

  rb_define_method(cSerializationDescriptor,
                   "aliases=", serialization_descriptor_aliases_set, 1);
  rb_define_method(cSerializationDescriptor, "aliases",
                   serialization_descriptor_aliases_aref, 0);

  rb_define_method(cSerializationDescriptor, "build_serializer",
                   serialization_descriptor_build_serializer, 0);
}
