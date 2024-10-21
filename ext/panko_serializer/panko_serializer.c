#include "panko_serializer.h"

#include <ruby.h>

void Init_panko_serializer() {
  VALUE mPanko = rb_define_module("Panko");

  panko_init_type_cast(mPanko);
}
