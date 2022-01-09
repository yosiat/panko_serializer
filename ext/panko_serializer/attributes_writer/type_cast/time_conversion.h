#pragma once

#include <ctype.h>
#include <ruby.h>
#include <stdbool.h>

VALUE is_iso8601_time_string(const VALUE value);
VALUE iso_ar_iso_datetime_string(const VALUE value);
void panko_init_time(VALUE mPanko);
