#include "common.h"

VALUE attr_name_for_serialization(Attribute attribute) {
  volatile VALUE name_str = attribute->name_str;
  if (attribute->alias_name != Qnil) {
    name_str = attribute->alias_name;
  }

  return name_str;
}
