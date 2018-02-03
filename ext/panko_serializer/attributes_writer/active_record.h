#pragma once

#include <ruby.h>
#include <stdbool.h>

#include "../attribute.h"
//#include "../serialization_descriptor.h"
#include "../type_cast.h"
#include "common.h"

extern VALUE active_record_attributes_writer(VALUE object,
                                             VALUE attributes,
                                             EachAttributeFunc func,
                                             VALUE context);

void init_active_record_attributes_writer(VALUE mPanko);
