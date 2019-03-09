#include <ruby.h>

#include "attributes_writer/attributes_writer.h"
#include "serialization_descriptor/association.h"
#include "serialization_descriptor/attribute.h"
#include "serialization_descriptor/serialization_descriptor.h"

VALUE serialize_object(VALUE key, VALUE object, VALUE str_writer,
                       SerializationDescriptor descriptor);

VALUE serialize_objects(VALUE key, VALUE objects, VALUE str_writer,
                        SerializationDescriptor descriptor);
