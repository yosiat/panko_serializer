#include <ruby.h>
#include <stdbool.h>

typedef bool (*TypeMatchFunc)(VALUE type_metadata, VALUE type_klass);

// Returns Qundef, if can't type cast
typedef VALUE (*TypeCastFunc)(VALUE type_metadata, VALUE value);

typedef struct _TypeCast {
    TypeMatchFunc canCast;
    TypeCastFunc	typeCast;
} *TypeCast;


// ActiveRecord::Type::String
// ActiveRecord::Type::Text
bool isStringOrTextType(VALUE type_metadata, VALUE type_klass);
VALUE castStringOrTextType(VALUE type_metadata, VALUE value);

// ActiveRecord::Type::Float
bool isFloatType(VALUE type_metadata, VALUE type_klass);
VALUE castFloatType(VALUE type_metadata, VALUE value);

// ActiveRecord::Type::Integer
bool isIntegerType(VALUE type_metadata, VALUE type_klass);
VALUE castIntegerType(VALUE type_metadata, VALUE value);

static struct _TypeCast	type_casts[] = {
  { isStringOrTextType, castStringOrTextType },
  { isIntegerType, castIntegerType },
  { isFloatType, castFloatType },

  { NULL, NULL }
};



extern VALUE type_cast(VALUE type_metadata, VALUE value);
void init_panko_type_cast(VALUE mPanko);
