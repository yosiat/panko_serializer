#include <ruby.h>
#include <stdbool.h>

/*
 * Type Casting
 *
 * We do "special" type casting which is mix of two inspirations:
 *  *) light records gem
 *  *) pg TextDecoders
 *
 * The whole idea behind those type casts, are to do the minimum required
 * type casting in the most performant manner and *allocation free*.
 *
 * For example, in `ActiveRecord::Type::String` the type_cast_from_database
 * creates new string, for known reasons, but, in serialization flow we don't
 * need to create new string becuase we afraid of mutations.
 *
 * Since we know before hand, that we are only reading from the database, and
 * *not* writing and the end result if for JSON we can skip some "defenses".
 */

typedef bool (*TypeMatchFunc)(VALUE type_klass);

/*
 * TypeCastFunc
 *
 * @return VALUE casted value or Qundef if not casted
 */
typedef VALUE (*TypeCastFunc)(VALUE value);

typedef struct _TypeCast {
  TypeMatchFunc canCast;
  TypeCastFunc typeCast;
} * TypeCast;

// ActiveRecord::Type::String
// ActiveRecord::Type::Text
bool is_string_or_text_type(VALUE type_klass);
VALUE cast_string_or_text_type(VALUE value);

// ActiveRecord::Type::Float
bool is_float_type(VALUE type_klass);
VALUE cast_float_type(VALUE value);

// ActiveRecord::Type::Integer
bool is_integer_type(VALUE type_klass);
VALUE cast_integer_type(VALUE value);

// ActiveRecord::ConnectoinAdapters::PostgreSQL::Json
bool is_json_type(VALUE type_klass);
VALUE cast_json_type(VALUE value);

// ActiveRecord::Type::Boolean
bool is_boolean_type(VALUE type_klass);
VALUE cast_boolean_type(VALUE value);

static struct _TypeCast type_casts[] = {
    {is_string_or_text_type, cast_string_or_text_type},
    {is_integer_type, cast_integer_type},
    {is_boolean_type, cast_boolean_type},
    {is_float_type, cast_float_type},
    {is_json_type, cast_json_type},

    {NULL, NULL}};

extern VALUE type_cast(VALUE type_metadata, VALUE value);
void panko_init_type_cast(VALUE mPanko);
