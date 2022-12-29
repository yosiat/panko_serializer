#include "plain.h"

void plain_attributes_writer(VALUE obj, VALUE attributes,
                             EachAttributeFunc write_value, VALUE writer) {
  long i;
  for (i = 0; i < RARRAY_LEN(attributes); i++) {
    volatile VALUE raw_attribute = RARRAY_AREF(attributes, i);
    Attribute attribute = attribute_read(raw_attribute);

    write_value(writer, attr_name_for_serialization(attribute),
                rb_funcall(obj, attribute->name_id, 0), Qfalse);
  }
}
