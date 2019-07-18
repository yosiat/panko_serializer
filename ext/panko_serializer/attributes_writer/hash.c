#include "hash.h"

void hash_attributes_writer(VALUE obj, VALUE attributes,
                             EachAttributeFunc func, VALUE writer) {
  long i;
  for (i = 0; i < RARRAY_LEN(attributes); i++) {
    volatile VALUE raw_attribute = RARRAY_AREF(attributes, i);
    Attribute attribute = attribute_read(raw_attribute);

    volatile VALUE value = rb_hash_aref(obj, attribute->name_str);

    func(writer, attr_name_for_serialization(attribute), value);
  }
}
