#include <ruby.h>

#include "association.h"
#include "attribute.h"
#include "attributes_writer/writer.h"
#include "serialization_descriptor.h"

VALUE serialize_subject(VALUE key,
                        VALUE subject,
                        VALUE str_writer,
                        SerializationDescriptor descriptor,
                        VALUE context);

VALUE serialize_subjects(VALUE key,
                         VALUE subjects,
                         VALUE str_writer,
                         SerializationDescriptor descriptor,
                         VALUE context);
