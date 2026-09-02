# Names the output must never use for anything of its own. Every name that reaches C
# is checked against this list and gets `_` appended if it matches (see `identifiers`
# in name.jl). Maintained by hand.
#
# The header sections cover every standard header the output *might* include. Their
# names are reserved whether or not a given file happens to include that header: that
# way the C changes less between development updates (adding an include later can't
# rename something that used to be fine) and stays compatible with outside C that may
# include any of these itself. When a new header joins the list of ones we might emit,
# add its names here.

const reserved = Set([
    # C keywords
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
    "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
    "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct",
    "switch", "typedef", "union", "unsigned", "void", "volatile", "while",
    # C23 keywords
    "alignas", "alignof", "bool", "constexpr", "false", "nullptr", "static_assert",
    "thread_local", "true", "typeof", "typeof_unqual",

    # <stdint.h>
    "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t",
    "uint64_t", "intptr_t", "uintptr_t", "intmax_t", "uintmax_t",
    "INT8_MIN", "INT16_MIN", "INT32_MIN", "INT64_MIN",
    "INT8_MAX", "INT16_MAX", "INT32_MAX", "INT64_MAX",
    "UINT8_MAX", "UINT16_MAX", "UINT32_MAX", "UINT64_MAX",
    # <stdbool.h> — bool/true/false are keywords above
    # <stddef.h>
    "size_t", "ptrdiff_t", "NULL", "offsetof",
    # <stdlib.h>
    "abs", "labs", "llabs", "malloc", "calloc", "realloc", "free", "exit", "abort", "atexit",
    "rand", "srand", "qsort", "bsearch", "atoi", "atol", "atof", "strtol", "strtod", "getenv", "system",
    "EXIT_SUCCESS", "EXIT_FAILURE", "RAND_MAX",
    # <math.h>
    "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
    "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
    "exp", "exp2", "expm1", "log", "log2", "log10", "log1p",
    "pow", "sqrt", "cbrt", "hypot",
    "fabs", "fmod", "remainder", "fma", "fmin", "fmax", "fdim",
    "floor", "ceil", "round", "trunc", "rint", "nearbyint", "lround", "llround",
    "copysign", "nan", "isnan", "isinf", "isfinite", "signbit",
    "ldexp", "frexp", "modf", "erf", "erfc", "tgamma", "lgamma",
    "HUGE_VAL", "INFINITY", "NAN", "M_PI", "M_E",

    # reserved by the transpiler's own naming scheme
    # (temp<N> and U<hex> are patterns rather than words and are handled elsewhere)
])
