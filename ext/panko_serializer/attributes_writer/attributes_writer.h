#pragma once

#include <ruby.h>

#include "active_record.h"
#include "common.h"
#include "plain.h"
#include "hash.h"

enum ObjectType { Unknown = 0, ActiveRecord = 1, Plain = 2, Hash = 3 };

typedef struct _AttributesWriter {
  enum ObjectType object_type;

  void (*write_attributes)(VALUE object, VALUE attributes,
                           EachAttributeFunc func, VALUE context);
} AttributesWriter;

/**
 * Infers the attributes writer from the object type
 */
AttributesWriter create_attributes_writer(VALUE object);

/**
 * Creates empty writer
 * Useful when the writer is not known, and you need init something
 */
AttributesWriter create_empty_attributes_writer();

void init_attributes_writer(VALUE mPanko);
