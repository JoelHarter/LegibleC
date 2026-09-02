# Type

The scalar types the transpiler supports, with what each language calls them
and the abbreviation used when a type has to appear in a mangled name (see
`naming.md`). The table in `src/type.jl` is the one the code reads; keep
the two in step.

| Julia     | C          | Mangled |
|-----------|------------|---------|
| `Bool`    | `bool`     | `B`     |
| `Int8`    | `int8_t`   | `I8`    |
| `UInt8`   | `uint8_t`  | `U8`    |
| `Int16`   | `int16_t`  | `I16`   |
| `UInt16`  | `uint16_t` | `U16`   |
| `Int32`   | `int32_t`  | `I32`   |
| `UInt32`  | `uint32_t` | `U32`   |
| `Int64`   | `int64_t`  | `I64`   |
| `UInt64`  | `uint64_t` | `U64`   |
| `Float32` | `float`    | `F32`   |
| `Float64` | `double`   | `F64`   |

`Float64` is the default: a function whose arguments are all `Float64` leaves
the abbreviation out of its mangled name entirely.

## Types both languages have that aren't in the table yet

Beyond booleans, integers, and floats, the scalar kinds C has are:

- **Complex numbers** — C99 `float _Complex` / `double _Complex` (`complex.h`)
  ↔ Julia `ComplexF32` / `ComplexF64`. Genuinely supported by both, with the
  same arithmetic operators. Would be `C32`/`C64`. Not emitted yet.
- **Pointers** — `T*` ↔ `Ptr{T}`. Needed the moment arrays are passed to C.
- **Characters** — C `char` is a byte, an integer type; Julia `Char` is a
  32-bit Unicode scalar. Not equivalent. C's `char32_t` (`uchar.h`) is the
  honest match. Not emitted yet.
- **`void`** ↔ `Nothing`, as a return type only.

And a few that exist on one side but not cleanly on the other:

- `Int128`/`UInt128` — C has `__int128` only as a GCC/clang extension.
- `Float16` — C23 `_Float16` is optional and platform-dependent.
- `long double` — no Julia equivalent.
- `Rational`, `BigInt`, `BigFloat` — no C equivalent.

## Arrays

Arrays aren't emitted yet, but their part in mangling is defined:

- A **static** array type carries its size in the type — the test is whether
  `size` is defined on the type itself, so no particular package is required.
  Whether it's immutable or mutable makes no difference to the C.
- A **regular** `Array{T,N}` carries only its dimension count. Under the
  `staticarray` option it's a static array in every respect — same C, same
  helpers, same names — with its size supplied in the `transpile` call
  (`(f, Float64, 2, 3)`; see `array.md`). Internally it's represented by the
  shaped stand-in `Shaped{T, size, N}` in `src/type.jl`, so that every rule
  that asks an array for its size gets one.
