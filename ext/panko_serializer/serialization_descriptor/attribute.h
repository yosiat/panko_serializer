#include <ruby.h>

#ifndef __ATTRIBUTE_H__
#define __ATTRIBUTE_H__

#include "../common.h"

typedef struct _Attribute {
  VALUE name_str;
  ID name_id;
  VALUE alias_name;

  /*
   * We will cache the activerecord type
   * by the record_class
   */
  VALUE type;
  VALUE record_class;
} * Attribute;

Attribute attribute_read(VALUE attribute);
void attribute_try_invalidate(Attribute attribute, VALUE record);
void panko_init_attribute(VALUE mPanko);

#endif
