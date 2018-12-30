#pragma once

#include <ruby.h>
#include <stdbool.h>

#include "../common.h"
#include "common.h"
#include "serialization_descriptor/attribute.h"
#include "type_cast/type_cast.h"

extern void active_record_attributes_writer(VALUE object,
                                            VALUE attributes,
                                            EachAttributeFunc func,
                                            VALUE writer);

void init_active_record_attributes_writer(VALUE mPanko);
