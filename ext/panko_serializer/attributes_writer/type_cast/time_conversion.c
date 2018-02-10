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

void append_region(const char* source,
                   char** to,
                   const OnigRegion* region,
                   int region_number) {
  long iter = 0;
  long regionEnd = region->end[region_number];
  for (iter = region->beg[region_number]; iter < regionEnd; iter++) {
    *(*to)++ = source[iter];
  }
}

VALUE iso_ar_iso_datetime_string(const char* value) {
  const UChar *start, *range, *end;
  OnigPosition r;
  OnigRegion* region = onig_region_new();
  volatile VALUE output;

  const UChar* str = (const UChar*)(value);

  end = str + strlen(value);
  start = str;
  range = end;
  r = onig_search(ar_iso_datetime_regex, str, end, start, range, region,
                  ONIG_OPTION_NONE);

  output = Qnil;
  if (r >= 0) {
    char buf[21] = "";
    char* cur = buf;

    append_region(value, &cur, region, YEAR_REGION);
    *cur++ = '-';

    append_region(value, &cur, region, MONTH_REGION);
    *cur++ = '-';

    append_region(value, &cur, region, DAY_REGION);
    *cur++ = 'T';

    append_region(value, &cur, region, HOUR_REGION);
    *cur++ = ':';

    append_region(value, &cur, region, MINUTE_REGION);
    *cur++ = ':';

    append_region(value, &cur, region, SECOND_REGION);
    *cur++ = 'Z';

    output = rb_str_new(buf, cur - buf);
  }

  onig_region_free(region, 1);
  return output;
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
