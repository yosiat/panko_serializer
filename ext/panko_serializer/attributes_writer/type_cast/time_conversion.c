#include "time_conversion.h"

const int YEAR_REGION = 1;
const int MONTH_REGION = 2;
const int DAY_REGION = 3;
const int HOUR_REGION = 4;
const int MINUTE_REGION = 5;
const int SECOND_REGION = 6;

static VALUE rb_iso8601_time_regex = Qundef;
static VALUE rb_ar_iso_datetime_regex = Qundef;

VALUE is_iso8601_time_string(const VALUE value) {
  const VALUE isMatch = rb_reg_match(rb_iso8601_time_regex, value);
  return NIL_P(isMatch) ? Qfalse: Qtrue;
}

void append_region_str(const char* source, char** to, int regionBegin,
                       int regionEnd) {
  long iter = 0;
  for (iter = regionBegin; iter < regionEnd; iter++) {
    *(*to)++ = source[iter];
  }
}

bool is_iso_ar_iso_datetime_string_fast_case(const char* value) {
  return (
      // year
      isdigit(value[0]) && isdigit(value[1]) && isdigit(value[2]) &&
      isdigit(value[3]) && value[4] == '-' &&
      // month
      isdigit(value[5]) && isdigit(value[6]) && value[7] == '-' &&
      // mday
      isdigit(value[8]) && isdigit(value[9]) && value[10] == ' ' &&

      // hour
      isdigit(value[11]) && isdigit(value[12]) && value[13] == ':' &&
      // minute
      isdigit(value[14]) && isdigit(value[15]) && value[16] == ':' &&
      // seconds
      isdigit(value[17]) && isdigit(value[18]));
}

bool is_iso_ar_iso_datetime_string_slow_case(const VALUE value) {
  const VALUE isMatch = rb_reg_match(rb_ar_iso_datetime_regex, value);
  return !NIL_P(isMatch);
}


VALUE iso_ar_iso_datetime_string(const VALUE value) {
  const char* str = StringValuePtr(value);

  if (is_iso_ar_iso_datetime_string_fast_case(str) == true ||
      is_iso_ar_iso_datetime_string_slow_case(value) == true) {
    volatile VALUE output;

    char buf[24] = "";
    char* cur = buf;

    append_region_str(str, &cur, 0, 4);
    *cur++ = '-';

    append_region_str(str, &cur, 5, 7);
    *cur++ = '-';

    append_region_str(str, &cur, 8, 10);
    *cur++ = 'T';

    append_region_str(str, &cur, 11, 13);
    *cur++ = ':';

    append_region_str(str, &cur, 14, 16);
    *cur++ = ':';

    append_region_str(str, &cur, 17, 19);

    *cur++ = '.';
    if (str[19] == '.' && isdigit(str[20])) {
      if (isdigit(str[20])) {
        *cur++ = str[20];
      } else {
        *cur++ = '0';
      }

      if (isdigit(str[21])) {
        *cur++ = str[21];
      } else {
        *cur++ = '0';
      }

      if (isdigit(str[22])) {
        *cur++ = str[22];
      } else {
        *cur++ = '0';
      }
    } else {
      *cur++ = '0';
      *cur++ = '0';
      *cur++ = '0';
    }
    *cur++ = 'Z';

    output = rb_str_new(buf, cur - buf);
    return output;
  }

  return Qnil;
}



void panko_init_time(VALUE mPanko) {
  rb_iso8601_time_regex = rb_reg_new_str(rb_str_new_cstr("^([\\+-]?\\d{4}(?!\\d{2}\\b))((-?)((0[1-9]|1[0-2])(\\3([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))([T\\s]((([01]\\d|2[0-3])((:?)[0-5]\\d)?|24\\:?00)([\\.,]\\d+(?!:))?)?(\\17[0-5]\\d([\\.,]\\d+)?)?([zZ]|([\\+-])([01]\\d|2[0-3]):?([0-5]\\d)?)?)?)?$"), 0);

  rb_ar_iso_datetime_regex = rb_reg_new_str(rb_str_new_cstr("\\A(?<year>\\d{4})-(?<month>\\d\\d)-(?<mday>\\d\\d) (?<hour>\\d\\d):(?<min>\\d\\d):(?<sec>\\d\\d)(\\.(?<microsec>\\d+))?\\z"), 0);


  rb_global_variable(&rb_iso8601_time_regex);
  rb_global_variable(&rb_ar_iso_datetime_regex);
}
