#pragma once

#include <ruby.h>

#include "common.h"
#include "active_record.h"
#include "plain.h"

enum ObjectType { Unknown = 0, ActiveRecord = 1, Plain = 2 };

typedef struct _AttributesWriter {
  enum ObjectType object_type;

  int (*write_attributes)(VALUE object,
                          VALUE attributes,
                          EachAttributeFunc func,
                          VALUE context);
} AttributesWriter;

/**
 * Infers the attributes writer from the subject type
 */
AttributesWriter create_attributes_writer(VALUE subject);

/**
 * Creates empty writer
 * Useful when the writer is not known, and you need init something
 */
AttributesWriter create_empty_attributes_writer();

void init_attributes_writer(VALUE mPanko);
