#pragma once

#include <ruby.h>


#define PANKO_EMPTY_HASH(hash) \
  (hash == Qnil || hash == Qundef) ? 1 : (RHASH_SIZE(hash) == 0)

