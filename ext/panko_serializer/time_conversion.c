#include "time_conversion.h"

static regex_t* iso8601_time_regex;
static regex_t* ar_iso_datetime_regex;

VALUE is_iso8601_time_string(const char* value) {
  const UChar *start, *range, *end;

  const UChar* str = (const UChar*)(value);

  end = str + strlen(value);
  start = str;
  range = end;
  OnigPosition r = onig_search(iso8601_time_regex, str, end, start, range, NULL,
                               ONIG_OPTION_NONE);

  return r >= 0 ? Qtrue : Qfalse;
}

void append_region_part(char* buf,
                        const char* value,
                        const OnigRegion* region,
                        int i) {
  long substringLength = region->end[i] - region->beg[i];
  strncat(buf, value + region->beg[i], substringLength);
}

VALUE iso_ar_iso_datetime_string(const char* value) {
  const UChar *start, *range, *end;
  OnigRegion* region = onig_region_new();

  const UChar* str = (const UChar*)(value);

  end = str + strlen(value);
  start = str;
  range = end;
  OnigPosition r = onig_search(ar_iso_datetime_regex, str, end, start, range,
                               region, ONIG_OPTION_NONE);

  VALUE output = Qnil;
  if (r >= 0) {
    char buf[21];
    sprintf(buf, "");

    append_region_part(buf, value, region, 1);
    strncat(buf, "-", 1);

    append_region_part(buf, value, region, 2);
    strncat(buf, "-", 1);

    append_region_part(buf, value, region, 3);
    strncat(buf, "T", 1);

    append_region_part(buf, value, region, 4);
    strncat(buf, ":", 1);

    append_region_part(buf, value, region, 5);
    strncat(buf, ":", 1);

    append_region_part(buf, value, region, 6);
    strncat(buf, "Z", 1);

    output = rb_str_new(buf, strlen(buf));
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
  const UChar* ISO8601_PATTERN =
      (UChar*)"^([\\+-]?\\d{4}(?!\\d{2}\\b))((-?)((0[1-9]|1[0-2])(\\3([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))([T\\s]((([01]\\d|2[0-3])((:?)[0-5]\\d)?|24\\:?00)([\\.,]\\d+(?!:))?)?(\\17[0-5]\\d([\\.,]\\d+)?)?([zZ]|([\\+-])([01]\\d|2[0-3]):?([0-5]\\d)?)?)?)?$";

  build_regex(&iso8601_time_regex, ISO8601_PATTERN);

  const UChar* AR_ISO_DATETIME_PATTERN =
      (UChar*)"\\A(?<year>\\d{4})-(?<month>\\d\\d)-(?<mday>\\d\\d) (?<hour>\\d\\d):(?<min>\\d\\d):(?<sec>\\d\\d)(\\.(?<microsec>\\d+))?\\z";

  build_regex(&ar_iso_datetime_regex, AR_ISO_DATETIME_PATTERN);
}
