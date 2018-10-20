#include <ruby.h>

#include "attributes_writer/attributes_writer.h"
#include "serialization_descriptor/association.h"
#include "serialization_descriptor/attribute.h"
#include "serialization_descriptor/serialization_descriptor.h"

VALUE serialize_subject(VALUE key,
                        VALUE subject,
                        VALUE str_writer,
                        SerializationDescriptor descriptor);

VALUE serialize_subjects(VALUE key,
                         VALUE subjects,
                         VALUE str_writer,
                         SerializationDescriptor descriptor);
