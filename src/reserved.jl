# Names the output must never use for anything of its own. Every name that reaches C
# is checked against this list and gets `_` appended if it matches (see `identifiers`
# in name.jl); a name starting with `_` has its underscores moved to the end, since C
# keeps every such name at file scope for itself. Maintained by hand.
#
# The header sections cover every standard header the output might include, and the
# common ones that C written *around* the output might: the names are reserved whether
# or not a given file happens to include that header, so the C changes less between
# development updates (adding an include later can't rename something that used to be
# fine) and stays compatible with outside C that includes any of these itself. When a
# new header joins the list of ones we might emit, add its names here.

# The math.h functions, each also present with an `f` (float) and an `l` (long double)
# suffix.
const mathfunction = [
    "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
    "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
    "exp", "exp2", "expm1", "log", "log2", "log10", "log1p", "logb", "ilogb",
    "pow", "sqrt", "cbrt", "hypot",
    "fabs", "fmod", "remainder", "remquo", "fma", "fmin", "fmax", "fdim",
    "floor", "ceil", "round", "trunc", "rint", "nearbyint", "lround", "llround", "lrint", "llrint",
    "copysign", "nan", "nextafter", "nexttoward", "ldexp", "frexp", "modf", "scalbn", "scalbln",
    "erf", "erfc", "tgamma", "lgamma",
]

const reserved = Set([
    # C keywords (the `_Bool`, `_Generic`, … family is covered by the underscore rule)
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
    "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
    "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct",
    "switch", "typedef", "union", "unsigned", "void", "volatile", "while",
    # C23 keywords
    "alignas", "alignof", "bool", "constexpr", "false", "nullptr", "static_assert",
    "thread_local", "true", "typeof", "typeof_unqual",
    # the program's entry point, and common compiler extensions
    "main", "asm", "typeof", "offsetof", "va_list", "va_start", "va_arg", "va_end", "va_copy",

    # <stdint.h>
    "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t",
    "int_least8_t", "int_least16_t", "int_least32_t", "int_least64_t",
    "uint_least8_t", "uint_least16_t", "uint_least32_t", "uint_least64_t",
    "int_fast8_t", "int_fast16_t", "int_fast32_t", "int_fast64_t",
    "uint_fast8_t", "uint_fast16_t", "uint_fast32_t", "uint_fast64_t",
    "intptr_t", "uintptr_t", "intmax_t", "uintmax_t",
    "INT8_MIN", "INT16_MIN", "INT32_MIN", "INT64_MIN",
    "INT8_MAX", "INT16_MAX", "INT32_MAX", "INT64_MAX",
    "UINT8_MAX", "UINT16_MAX", "UINT32_MAX", "UINT64_MAX",
    "INTMAX_MIN", "INTMAX_MAX", "UINTMAX_MAX", "INTPTR_MIN", "INTPTR_MAX", "UINTPTR_MAX",
    "SIZE_MAX", "PTRDIFF_MIN", "PTRDIFF_MAX", "WCHAR_MIN", "WCHAR_MAX",
    "INT8_C", "INT16_C", "INT32_C", "INT64_C", "UINT8_C", "UINT16_C", "UINT32_C", "UINT64_C", "INTMAX_C", "UINTMAX_C",
    # <stdbool.h> — bool/true/false are keywords above
    # <stddef.h>
    "size_t", "ptrdiff_t", "wchar_t", "max_align_t", "nullptr_t", "NULL",
    # <uchar.h>
    "char16_t", "char32_t",
    # <limits.h>
    "CHAR_BIT", "CHAR_MIN", "CHAR_MAX", "SCHAR_MIN", "SCHAR_MAX", "UCHAR_MAX", "SHRT_MIN", "SHRT_MAX", "USHRT_MAX",
    "INT_MIN", "INT_MAX", "UINT_MAX", "LONG_MIN", "LONG_MAX", "ULONG_MAX", "LLONG_MIN", "LLONG_MAX", "ULLONG_MAX", "MB_LEN_MAX",
    # <float.h>
    "FLT_RADIX", "FLT_MANT_DIG", "FLT_DIG", "FLT_MIN", "FLT_MAX", "FLT_EPSILON", "FLT_MIN_EXP", "FLT_MAX_EXP",
    "DBL_MANT_DIG", "DBL_DIG", "DBL_MIN", "DBL_MAX", "DBL_EPSILON", "DBL_MIN_EXP", "DBL_MAX_EXP",
    "LDBL_MANT_DIG", "LDBL_DIG", "LDBL_MIN", "LDBL_MAX", "LDBL_EPSILON", "DECIMAL_DIG", "FLT_EVAL_METHOD", "FLT_ROUNDS",
    # <stdlib.h>
    "abs", "labs", "llabs", "div", "ldiv", "lldiv", "div_t", "ldiv_t", "lldiv_t",
    "malloc", "calloc", "realloc", "free", "aligned_alloc", "exit", "abort", "atexit", "quick_exit", "at_quick_exit",
    "rand", "srand", "qsort", "bsearch", "atoi", "atol", "atoll", "atof",
    "strtol", "strtoll", "strtoul", "strtoull", "strtod", "strtof", "strtold",
    "getenv", "system", "mblen", "mbtowc", "wctomb", "mbstowcs", "wcstombs",
    "EXIT_SUCCESS", "EXIT_FAILURE", "RAND_MAX", "MB_CUR_MAX",
    # <string.h>, and the POSIX <strings.h> names that usually come with it
    "memset", "memcpy", "memmove", "memcmp", "memchr", "strlen", "strnlen", "strcpy", "strncpy", "strcat", "strncat",
    "strcmp", "strncmp", "strcoll", "strxfrm", "strchr", "strrchr", "strstr", "strspn", "strcspn", "strpbrk", "strtok",
    "strerror", "strdup", "strndup", "strsep", "strcasecmp", "strncasecmp", "index", "rindex", "bcopy", "bzero",
    # <stdio.h>
    "printf", "fprintf", "sprintf", "snprintf", "vprintf", "vfprintf", "vsprintf", "vsnprintf",
    "scanf", "fscanf", "sscanf", "puts", "fputs", "putchar", "fputc", "putc", "getchar", "fgetc", "getc", "ungetc",
    "fgets", "gets", "fopen", "freopen", "fclose", "fflush", "fread", "fwrite", "fseek", "ftell", "fsetpos", "fgetpos",
    "rewind", "remove", "rename", "tmpfile", "tmpnam", "perror", "feof", "ferror", "clearerr", "setbuf", "setvbuf",
    "FILE", "fpos_t", "stdin", "stdout", "stderr", "EOF", "BUFSIZ", "SEEK_SET", "SEEK_CUR", "SEEK_END", "FILENAME_MAX", "FOPEN_MAX",
    # <ctype.h>
    "isalpha", "isdigit", "isalnum", "isspace", "isupper", "islower", "isprint", "ispunct", "isxdigit", "iscntrl",
    "isgraph", "isblank", "toupper", "tolower",
    # <assert.h>, <errno.h>
    "assert", "errno", "EDOM", "ERANGE", "EILSEQ",
    # <time.h>
    "time", "clock", "time_t", "clock_t", "difftime", "mktime", "strftime", "localtime", "gmtime", "asctime", "ctime",
    "timespec", "timespec_get", "tm", "CLOCKS_PER_SEC", "TIME_UTC",
    # <math.h>: the functions above in all three widths, then the rest
    mathfunction..., (mathfunction .* "f")..., (mathfunction .* "l")...,
    "isnan", "isinf", "isfinite", "isnormal", "signbit", "fpclassify",
    "isgreater", "isgreaterequal", "isless", "islessequal", "islessgreater", "isunordered",
    "HUGE_VAL", "HUGE_VALF", "HUGE_VALL", "INFINITY", "NAN",
    "FP_NAN", "FP_INFINITE", "FP_ZERO", "FP_SUBNORMAL", "FP_NORMAL", "FP_ILOGB0", "FP_ILOGBNAN",
    "MATH_ERRNO", "MATH_ERREXCEPT", "math_errhandling", "float_t", "double_t",
    "M_E", "M_LOG2E", "M_LOG10E", "M_LN2", "M_LN10", "M_PI", "M_PI_2", "M_PI_4", "M_1_PI", "M_2_PI", "M_2_SQRTPI", "M_SQRT2", "M_SQRT1_2",
    # POSIX and glibc additions to <math.h> that a default compiler exposes
    "j0", "j1", "jn", "y0", "y1", "yn", "gamma", "lgamma_r", "significand", "drem", "scalb", "exp10", "pow10", "sincos",

    # reserved by the transpiler's own naming scheme
    # (temp<N> and U<hex> are patterns rather than words and are handled elsewhere)
])
