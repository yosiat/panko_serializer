#include <ruby.h>
#include <stdbool.h>

#include "attribute.h"
#include "serialization_descriptor.h"
#include "type_cast.h"

typedef void (*EachAttributeFunc)(VALUE object,
                                  VALUE name,
                                  VALUE value,
                                  VALUE type_metadata,
                                  VALUE context);

extern VALUE panko_each_attribute(VALUE object,
                                  VALUE attributes,
                                  EachAttributeFunc func,
                                  VALUE context);

void panko_init_attributes_iterator(VALUE mPanko);
