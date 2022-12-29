#pragma once

#include "../serialization_descriptor/attribute.h"
#include "ruby.h"

typedef void (*EachAttributeFunc)(VALUE writer, VALUE name, VALUE value,
                                  VALUE isJson);

VALUE attr_name_for_serialization(Attribute attribute);
