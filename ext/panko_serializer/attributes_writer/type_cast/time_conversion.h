#pragma once

#include <ctype.h>
#include <ruby.h>
#include <ruby/oniguruma.h>

VALUE is_iso8601_time_string(const char* value);
VALUE iso_ar_iso_datetime_string(const char* value);
void panko_init_time(VALUE mPanko);
