#pragma once

#include "common.h"
#include "ruby.h"

void hash_attributes_writer(VALUE obj, VALUE attributes, EachAttributeFunc func,
                            VALUE writer);
