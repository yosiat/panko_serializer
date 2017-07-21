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
 * Since we know before hand, that we are only reading from the database, and *not* writing
 * and the end result if for JSON we can skip some "defenses".
 */

typedef bool (*TypeMatchFunc)(VALUE type_klass);

// Returns Qundef, if can't type cast
typedef VALUE (*TypeCastFunc)(VALUE value);

typedef struct _TypeCast {
    TypeMatchFunc canCast;
    TypeCastFunc	typeCast;
} *TypeCast;


// ActiveRecord::Type::String
// ActiveRecord::Type::Text
bool isStringOrTextType(VALUE type_klass);
VALUE castStringOrTextType(VALUE value);

// ActiveRecord::Type::Float
bool isFloatType(VALUE type_klass);
VALUE castFloatType(VALUE value);

// ActiveRecord::Type::Integer
bool isIntegerType(VALUE type_klass);
VALUE castIntegerType(VALUE value);

// ActiveRecord::ConnectoinAdapters::PostgreSQL::Json
bool isJsonType(VALUE type_klass);
VALUE castJsonType(VALUE value);

static struct _TypeCast	type_casts[] = {
  { isStringOrTextType, castStringOrTextType },
  { isIntegerType, castIntegerType },
  { isFloatType, castFloatType },
  { isJsonType, castJsonType },

  { NULL, NULL }
};



extern VALUE type_cast(VALUE type_metadata, VALUE value);
void init_panko_type_cast(VALUE mPanko);
