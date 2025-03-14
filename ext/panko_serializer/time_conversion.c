#include "time_conversion.h"

const int YEAR_REGION = 1;
const int MONTH_REGION = 2;
const int DAY_REGION = 3;
const int HOUR_REGION = 4;
const int MINUTE_REGION = 5;
const int SECOND_REGION = 6;

static regex_t* iso8601_time_regex;
static regex_t* ar_iso_datetime_regex;

VALUE is_iso8601_time_string(const char* value) {
  const UChar *start, *range, *end;
  OnigPosition r;

  const UChar* str = (const UChar*)(value);

  end = str + strlen(value);
  start = str;
  range = end;
  r = onig_search(iso8601_time_regex, str, end, start, range, NULL,
                  ONIG_OPTION_NONE);

  return r >= 0 ? Qtrue : Qfalse;
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

bool is_iso_ar_iso_datetime_string_slow_case(const char* value) {
  const UChar *start, *range, *end;
  OnigPosition r;
  OnigRegion* region = onig_region_new();

  const UChar* str = (const UChar*)(value);

  end = str + strlen(value);
  start = str;
  range = end;
  r = onig_search(ar_iso_datetime_regex, str, end, start, range, region,
                  ONIG_OPTION_NONE);

  onig_region_free(region, 1);

  return (r >= 0);
}

VALUE iso_ar_iso_datetime_string(const char* value) {
  if (is_iso_ar_iso_datetime_string_fast_case(value) == true ||
      is_iso_ar_iso_datetime_string_slow_case(value) == true) {
    volatile VALUE output;

    char buf[24] = "";
    char* cur = buf;

    append_region_str(value, &cur, 0, 4);
    *cur++ = '-';

    append_region_str(value, &cur, 5, 7);
    *cur++ = '-';

    append_region_str(value, &cur, 8, 10);
    *cur++ = 'T';

    append_region_str(value, &cur, 11, 13);
    *cur++ = ':';

    append_region_str(value, &cur, 14, 16);
    *cur++ = ':';

    append_region_str(value, &cur, 17, 19);

    *cur++ = '.';
    if (value[19] == '.' && isdigit(value[20])) {
      if (isdigit(value[20])) {
        *cur++ = value[20];
      } else {
        *cur++ = '0';
      }

      if (isdigit(value[21])) {
        *cur++ = value[21];
      } else {
        *cur++ = '0';
      }

      if (isdigit(value[22])) {
        *cur++ = value[22];
      } else {
        *cur++ = '0';
      }
    } else {
      *cur++ = '0';
      *cur++ = '0';
      *cur++ = '0';
    }
    *cur++ = 'Z';

    output = rb_utf8_str_new(buf, cur - buf);
    return output;
  }

  return Qnil;
}

void build_regex(OnigRegex* reg, const UChar* pattern) {
  OnigErrorInfo einfo;

  int r = onig_new(reg, pattern, pattern + strlen((char*)pattern),
                   ONIG_OPTION_DEFAULT, ONIG_ENCODING_ASCII,
                   ONIG_SYNTAX_DEFAULT, &einfo);

  if (r != ONIG_NORMAL) {
    char s[ONIG_MAX_ERROR_MESSAGE_LEN];
    onig_error_code_to_str((UChar*)s, r, &einfo);
    printf("ERROR: %s\n", s);
  }
}

void panko_init_time(VALUE mPanko) {
  const UChar *ISO8601_PATTERN, *AR_ISO_DATETIME_PATTERN;

  ISO8601_PATTERN =
      (UChar*)"^([\\+-]?\\d{4}(?!\\d{2}\\b))((-?)((0[1-9]|1[0-2])(\\3([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))([T\\s]((([01]\\d|2[0-3])((:?)[0-5]\\d)?|24\\:?00)([\\.,]\\d+(?!:))?)?(\\17[0-5]\\d([\\.,]\\d+)?)?([zZ]|([\\+-])([01]\\d|2[0-3]):?([0-5]\\d)?)?)?)?$";

  build_regex(&iso8601_time_regex, ISO8601_PATTERN);

  AR_ISO_DATETIME_PATTERN =
      (UChar*)"\\A(?<year>\\d{4})-(?<month>\\d\\d)-(?<mday>\\d\\d) (?<hour>\\d\\d):(?<min>\\d\\d):(?<sec>\\d\\d)(\\.(?<microsec>\\d+))?\\z";

  build_regex(&ar_iso_datetime_regex, AR_ISO_DATETIME_PATTERN);
}
