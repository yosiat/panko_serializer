#include <ruby.h>

#include "association.h"
#include "attribute.h"
#include "serialization_descriptor.h"
#include "type_cast.h"

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
