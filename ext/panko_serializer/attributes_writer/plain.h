#pragma once

#include "common.h"
#include "ruby.h"

VALUE plain_attributes_writer(VALUE obj,
                              VALUE attributes,
                              EachAttributeFunc func,
                              VALUE writer);
