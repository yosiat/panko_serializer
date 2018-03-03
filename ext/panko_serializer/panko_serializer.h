#include <ruby.h>

#include "attributes_writer/writer.h"
#include "serialization_descriptor/serialization_descriptor.h"
#include "serialization_descriptor/association.h"
#include "serialization_descriptor/attribute.h"

VALUE serialize_subject(VALUE key,
                        VALUE subject,
                        VALUE str_writer,
                        SerializationDescriptor descriptor);

VALUE serialize_subjects(VALUE key,
                         VALUE subjects,
                         VALUE str_writer,
                         SerializationDescriptor descriptor);
