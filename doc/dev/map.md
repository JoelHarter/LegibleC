# Map

A survey of what could cross between the two languages: the Julia worth
transpiling, the C worth being able to reach, and proposals for how the
important ones would map. It's a catalogue and a set of designs to argue
about, not a plan. Status marks: ✅ done,
🟡 partly, ⬜ open, ✗ no C meaning worth pursuing.

The lens throughout is `philosophy.md`: fastest C, reading as hand-written, one
general rule over many special ones. A mapping that can't meet all three is
marked as such rather than forced.

## 1. Julia worth transpiling

### Values and types

| Julia | would become in C | status |
|---|---|---|
| `Bool`, `Int8`…`Int64`, `UInt8`…`UInt64`, `Float32`, `Float64` | `bool`, `int8_t`…, `float`, `double` | ✅ |
| static arrays of any dimension | `double A[2][3]` parameters, row-major | ✅ |
| `Array{T,N}` with a size given to `transpile` | the same C as a static array | ✅ |
| `Array{T,N}` with a runtime size | VLA parameters, `void f(int m, int n, double A[m][n])` — see §3.4 | ⬜ |
| `Vector{T}` that grows (`push!`, `pop!`, `resize!`) | a generated `struct { T *data; size_t length, capacity; }` with helpers over `realloc` — §3.4 | ⬜ |
| `struct` (immutable) | `typedef struct { … } Name;` passed and returned by value — §3.1 | ✅ |
| `mutable struct` | the same struct, handled through a pointer — §3.1 | ✅ (passed in; not created inside) |
| parametric `struct Point{T}` at a concrete `T` | one C struct per instantiation, name mangled like a function's: `Point_F32` | ✅ |
| `Base.@kwdef` | designated initializers `(Point){.x = 1, .y = 2}` | ⬜ |
| `Tuple` (heterogeneous), multiple return values | a generated struct `Tuple_F64_I64`, returned by value — §3.2 | ✅ |
| `NTuple{N,T}` (homogeneous) | the same struct (`Tuple_F64_F64_F64`); a `T a[N]` would be the optimization | 🟡 |
| `NamedTuple` | a struct with those field names | ⬜ |
| `@enum` | `typedef enum { RED, GREEN } Color;` | ⬜ |
| `Union{T, Nothing}`, `missing` | `struct { bool present; T value; }`, or `NaN` for floats, or a null pointer for structs — §3.3 | ⬜ |
| `Nothing` as a return | `void` | ✅ |
| `Complex{Float64}` | `double _Complex` from `complex.h`; `+ - * /` and `creal`, `cimag`, `cabs`, `conj` map one to one | ⬜ |
| `Char` | `char`, ASCII only: a non-ASCII literal is refused. `char32_t` would be exact but no C library function takes it | ✅ |
| `String` | `const char *` UTF-8 for literals and read-only arguments; a built string is a `char[]` buffer — §3.6 | ⬜ |
| `Symbol` | an `enum` or a string constant, decided per use | ⬜ |
| `Ptr{T}`, `Ref{T}` | `T *` | ⬜ |
| `const G = 6.67e-11` | `static const double G = 6.67e-11;` at file scope | ⬜ |
| `const table = [1.0, 2.0, …]` | `static const double table[4] = {1.0, 2.0, …};` — lookup tables are a C staple | ⬜ |
| mutable globals | `static double x;` — legal, discouraged, and easy | ⬜ |
| `Val{N}`, type parameters, `Symbol` arguments | consumed at transpile time; never reach C | ✅ (as far as used) |
| `Int128`, `BigInt`, `Rational`, `BigFloat` | `__int128` is a compiler extension; the rest have no C | ✗ |
| abstract types, `Any` | nothing directly; every function is transpiled at concrete types (monomorphized), so a value's type is always known — §3.7 | ✅ by design |

### Functions and calls

| Julia | would become in C | status |
|---|---|---|
| a function at one concrete signature | a C function, name kept | ✅ |
| the same function at several signatures | one C function per signature, types appended to the name | ✅ |
| default arguments `f(x, y=1)` | the IR already sees `f(x, 1)`; nothing to do | ⬜ untested |
| keyword arguments | the IR sees an ordinary call; nothing to do | ⬜ untested |
| varargs `f(xs...)` | monomorphized per arity: `f_3(a, b, c)`; or an array plus a count | ⬜ |
| calling another transpiled function | a call — every function has a prototype | ✅ |
| calling a function that isn't transpiled | transpiled on demand | ✅ |
| recursion | recursion | ✅ |
| closures and `x -> …` | inlined when the closure is known at transpile time (nearly always); a function pointer plus a context struct when it must be a value — §3.5 | ⬜ |
| `map`, `reduce`, `foldl`, `filter`, `any(f, v)` | the loop they are, with the function inlined — §3.5 | ⬜ |
| `do` blocks | the same as closures | ⬜ |
| comprehensions `[f(i) for i in 1:n]` | a loop filling a static array (size known from the range) | ⬜ |
| `ccall((:f, "lib"), …)` | the call itself, plus a prototype or the header: Julia that calls C becomes C that calls C — §3.9 | ✅ |
| `@inline`, `@noinline` | `inline`, `__attribute__((noinline))` — the latter is an extension | ⬜ |
| `@inbounds`, `@simd`, `@fastmath` | nothing: C never checks bounds, and a per-site flag would break the philosophy's one-fixed-flag rule — §3.10 | ✗ / ⬜ |
| macros generally | expanded before the transpiler sees anything | ✅ |
| `@generated`, `@static if` | resolved before we see anything | ✅ |
| `main` — Julia 1.11's `function (@main)(args)` | `int main(int argc, char **argv)`, `ARGS` from `argv` — §3.11 | ⬜ |

### Control flow and errors

| Julia | would become in C | status |
|---|---|---|
| `if`/`elseif`/`else`, `while`, `for i in a:b`, `break`, `continue`, `return`, `&&`, `\|\|`, `?:` | the same | ✅ |
| `for x in v`, `for (i, x) in enumerate(v)`, `zip` | index loops | ✅ `for x in v` over a vector; ⬜ `enumerate`, `zip`, a matrix |
| `for i in 1:n` used only as an index | the C idiom `for (i = 0; i < n; i++) v[i]` | ⬜ |
| `if x == 1 … elseif x == 2 …` on integer constants | `switch` — see §2 | ⬜ |
| `@assert` | `assert(…)` from `assert.h` | ⬜ |
| `error("…")`, `throw(…)` uncaught | `fprintf(stderr, …); abort();` — the program dies with a message in both languages — §3.8 | ⬜ |
| `try`/`catch`/`finally` | within one function, a structured form; across functions, status codes — §3.8 | ⬜ |
| `@goto`/`@label` | `goto` — the one case where emitting it is honest | ⬜ |

### Arithmetic and library

| Julia | would become in C | status |
|---|---|---|
| `+ - * / ÷ % ^ mod`, comparisons, bit ops, `math.h` functions, casts, `pi`, `Inf`, `NaN` | the same | ✅ |
| integer overflow | Julia wraps, C leaves it undefined: `-fwrapv` as the one fixed flag, or unsigned arithmetic | ⬜ |
| `div(a, b)` by zero, `Int(2.5)` | Julia throws, C doesn't; reproduce the check or document the difference | ⬜ |
| `gcd`, `lcm`, `fld`, `cld`, `rem(x, y, RoundNearest)`, `sign`, `clamp`, `ifelse`, `muladd`, `fma`, `hypot`, `atan(y, x)` | small expressions or `math.h` | 🟡 |
| `count_ones`, `leading_zeros`, `trailing_zeros`, `bswap`, `bitrotate` | `__builtin_popcountll` and friends (extensions), or portable loops | ⬜ |
| `typemax`, `typemin`, `eps`, `floatmax`, `floatmin` | `INT64_MAX`, `DBL_EPSILON`, `DBL_MAX`, … | ⬜ |
| `isnan`, `isinf`, `isfinite`, `signbit`, `copysign`, `flipsign` | the same names in `math.h` | 🟡 |
| `Float32` math (`sqrt(x::Float32)`) | `sqrtf` and friends | ✅ |
| `round(x, digits=2)` | `rint(x * 100) / 100` | ⬜ |
| `rand()`, `randn()` | Julia's own generator, Xoshiro256++, written out in C: same seed, same stream, bit for bit — §3.12 | ⬜ |
| `time()`, `time_ns()` | `clock_gettime` (POSIX) or `timespec_get` (C11) | ⬜ |
| `println`, `print`, string interpolation | `printf` with a format built from the types — §3.6 | ⬜ |
| `@printf`, `@sprintf` | `printf`, `snprintf` — the format strings are already C's | ⬜ |
| `parse(Float64, s)`, `parse(Int, s)` | `strtod`, `strtoll` | ⬜ |
| `open`, `read`, `write`, `readline`, `eachline` | `stdio.h` | ⬜ |
| `sort!`, `sort`, `sortperm` | `qsort` with a generated comparator, or an inlined insertion sort for small static sizes | ⬜ |
| `searchsorted*`, `findfirst`, `findall` | loops, `bsearch` | ⬜ |
| `Dict{K,V}`, `Set{T}` | a generated open-addressing hash table per `(K, V)` — real work, and only worth it once dynamic arrays exist | ⬜ |
| `Threads.@threads for` | `#pragma omp parallel for` — one pragma, one flag (`-fopenmp`) | ⬜ |
| `Threads.@spawn`, `Channel`, `@async` | `pthread`s; a much bigger step | ✗ for now |
| `Threads.Atomic`, `@atomic` | C11 `<stdatomic.h>` | ⬜ |
| `reinterpret(UInt64, x)` | `memcpy` into a local — the portable type pun | ⬜ |
| `sizeof(T)` | `sizeof(T)` | ⬜ |
| `unsafe_load`, `unsafe_store!`, pointer arithmetic | `*p`, `p[i]`, `p + i` | ⬜ |

### Arrays and linear algebra

| Julia | would become in C | status |
|---|---|---|
| `+ - *` (all shapes), `'`, broadcasting, `dot`, `cross`, `det`, `zeros`, `ones`, `fill`, `one`, `I`, literals, `[A B; C D]`, copies | helpers named for their inputs | ✅ |
| `v[2:3]`, `A[i, :]`, `A[:, j]` (copies in Julia) | `slice_5_3`, `row_2x3`, `col_2x3` helpers that copy into a static array | ✅ |
| `@view A[:, j]`, `view(v, 2:3)` | a pointer for a contiguous slice (`&v[1]`), a `{pointer, stride, length}` struct otherwise — §3.4 | ⬜ |
| `sum`, `prod`, `maximum`, `minimum`, `norm`, `any`, `all` | reduction helpers, one loop each | ✅ |
| `sum(A; dims=d)`, `prod`, `maximum`, `minimum` with `dims`; `diff`, `cumsum`, `cumprod` | helpers along one dimension, the dimension on the name: `sum1_2x3`, `diff2_2x3`, `cumsum_4` | ✅ |
| `extrema`, `argmax`, `argmin`, `count` | reduction helpers | ✅ |
| `inv`, `A \ b`, `B / A`, `pinv`, `cholesky(A) \ b` | 1–3 written out; pivoted LU, Cholesky, the Gram matrix beyond — `math/solve.md` | ✅ |
| `tr`, `diag`, `diagm`, `kron`, `transpose!` | small helpers | ⬜ |
| `lu`, `qr`, `cholesky`, `eigen` | 1–3 in closed form where one exists (symmetric 3×3 eigenvalues do); iterative beyond, as helpers | ⬜ |
| `reshape`, `vec`, `permutedims`, `reverse`, `circshift` | index remapping helpers; `reshape` of a static array is free (same storage, like a transpose) | ⬜ |
| `.==`, `.<`, `ifelse.`, `clamp.` | pointwise helpers producing `bool` arrays | ✅ except `clamp.` |
| `A .= 0`, `fill!(A, x)`, `copyto!`, `A[i] = …` on a mutable array | the existing `zero_`/`fill_`/`copy_` helpers called on the variable | ✅ except `copyto!` |
| `isapprox`, `≈` | `fabs(a - b) <= tol * fmax(fabs(a), fabs(b))` with Julia's default tolerance | ⬜ |
| fusing a broadcast chain into one loop | one helper per chain instead of one per operation | ⬜ |

### Program structure

| Julia | would become in C | status |
|---|---|---|
| a `module` | one `.c` and one `.h`, names prefixed with the module's | ⬜ |
| `export` | the contents of the `.h`; everything else `static` | ⬜ |
| `include("file.jl")` | the same file split, or one translation unit | ⬜ |
| docstrings, comments, source lines | Doxygen blocks and `//` comments | ✅ |
| `using LinearAlgebra`, `using StaticArrays` | nothing: the helpers are generated | ✅ |

## 2. C worth being able to reach

The other direction: features of C a person writing by hand would use, and
what Julia could say to produce them.

| C | the Julia that could map to it | status |
|---|---|---|
| `static` file-scope functions | every helper; and every user function not `export`ed from a module | 🟡 |
| `const` parameters | every array argument not written to | ✅ |
| `restrict` | provable: a Julia result is a fresh array, so `out` never aliases an input — `double out[restrict 3]` on every helper and user function | ✅ |
| `inline` | `@inline`; or small single-use helpers automatically | ⬜ |
| fixed-size arrays `double A[2][3]` | static arrays | ✅ |
| VLA parameters `void f(int m, int n, double A[m][n])` | `Array{T,N}` arguments with runtime sizes — as readable as the static form, and the sizes travel with the call | ⬜ |
| `malloc`/`realloc`/`free` | growing vectors; a returned `Vector` is owned by the caller, who frees it | ⬜ |
| `struct`, `typedef` | `struct` | ✅ |
| compound literals `(Point){1.0, 2.0}` | constructor calls | ✅ |
| designated initializers `{.x = 1.0}` | `@kwdef` constructors | ⬜ |
| `union` | `reinterpret`; or a `Union` of isbits types as a tagged union | ⬜ |
| `enum` | `@enum` | ⬜ |
| bit fields `unsigned flag : 1` | nothing natural; a `Bool` field packed by request | ✗ |
| function pointers, `void *ctx` callbacks | closures handed to an external C API | ⬜ |
| `switch` | an `if`/`elseif` chain comparing one integer to constants | ⬜ |
| `do { … } while (c)` | `while true … c \|\| break end` | ⬜ |
| `for (i = 0; i < n; i++) v[i]` | `for i in 1:n` whose `i` only ever indexes | ⬜ |
| `goto` | `@goto`/`@label` only | ⬜ |
| `#define N 3`, `static const` | `const` globals | ⬜ |
| `static const double table[] = {…}` | `const` global arrays | ⬜ |
| function-like macros | `@inline` one-liners come out as functions, which the compiler inlines anyway | ✗ (not needed) |
| `#include`, separate compilation, a `.h` | modules; a companion `.h` for the transpiled functions is already on the todo | ⬜ |
| `memset` | `zeros`, `zero(A)`, `one(A)` | ✅ |
| `extern` | references across modules | ⬜ |
| `int main(int argc, char **argv)` | `(@main)(args)` | ⬜ |
| `exit(code)`, `abort()` | `exit(code)`, an uncaught `throw` | ⬜ |
| `printf` family | `println`, `@printf` | ⬜ |
| `assert` | `@assert` | ⬜ |
| `errno`, status-code returns | functions that can throw, across a call boundary — §3.8 | ⬜ |
| `setjmp`/`longjmp` | `try`/`catch` across calls — possible, ugly, and rarely what a C author would write | ✗ |
| `memcpy`, `memset`, `memcmp` | copies, `zero`, `==` on arrays | 🟡 |
| `qsort`, `bsearch` | `sort!`, `searchsorted` | ⬜ |
| `math.h`, `stdint.h`, `stdbool.h` | done | ✅ |
| `complex.h` | `Complex` | ⬜ |
| `tgmath.h` | `Float32`/`Float64` overloads of the same function — the generic macros pick the width | ⬜ |
| `_Generic` (C11) | multiple dispatch on scalar types, exposed to a C caller as one name: `#define f(x) _Generic((x), double: f_F64, float: f_F32)(x)` — §3.7 | ⬜ |
| `_Complex`, `_Bool`, `_Alignas` | `Complex`, `Bool`, nothing | 🟡 |
| C23 `constexpr`, `auto`, `nullptr`, `[[nodiscard]]`, `_BitInt(N)` | `const`, nothing, `nothing`, nothing, nothing natural | ✗ mostly |
| `volatile` | a hardware register in embedded code: an `unsafe_load` on a `Ptr` marked by the user | ⬜ |
| `#pragma omp parallel for`, `#pragma omp simd` | `Threads.@threads`, `@simd` | ⬜ |
| `__builtin_popcount`, `__builtin_clz`, `__builtin_expect` | `count_ones`, `leading_zeros`, nothing | ⬜ |
| `__attribute__((pure))`, `((const))` | provable from the IR for functions without side effects; extension only | ⬜ |
| `static` locals (state that persists between calls) | a closure over a `Ref`, or a mutable global — nothing clean | ✗ |
| `char *` strings | `String` | ⬜ |
| `FILE *` | `IOStream` | ⬜ |
| `size_t` | `Int` for sizes and indices — the sign difference is a real semantic gap | ⬜ |
| `uint8_t buf[N]` byte buffers | `Vector{UInt8}`, `NTuple{N,UInt8}` | ⬜ |
| `stdatomic.h` | `@atomic` | ⬜ |
| `time.h` | `time()`, `Dates` (the latter no) | ⬜ |
| `getenv` | `ENV["X"]` | ⬜ |

## 3. Proposals

Each of these is a way, or a couple of ways, the mapping could go, with the
recommended one first and what's unresolved after it.

### 3.1 Structs

Julia's IR is already flat: `Base.getproperty(p, :x)` with the field as a
literal symbol, the type itself as the constructor callee, and
`Base.setproperty!(c, :n, v)` only on a `mutable struct`.

- **Immutable `struct Point; x::Float64; y::Float64; end`** → a `typedef
  struct { double x; double y; } Point;` emitted once, ahead of the helpers,
  for every struct that appears in any signature or body. Passed and
  returned *by value*, which is exactly Julia's semantics for an immutable
  struct. `Point(x, y)` → `(Point){x, y}`; `p.x` → `p.x`; a struct result
  is a real return value, not an out-parameter, since C returns structs.
  Array fields become C arrays inside the struct (`double pos[3]`), copied
  with the struct.
- **`mutable struct`** is a reference in Julia — two variables can hold the
  same one — so it must be a pointer in C: a parameter `Counter *c`,
  `c.n += 1` → `c->n += 1;`, and a function that returns the same object
  returns the pointer it was given. One that *creates* a mutable struct
  has to allocate it: `malloc` and an ownership rule (the caller frees), or
  refuse creation inside transpiled code and let the C caller own the
  object. The second is the honest first step.
- **Parametric structs** at a concrete instantiation get one C struct each,
  mangled like functions: `Point_F32`, `Body_3` for a `Body{N}`.
- **Naming** is already covered: type and field names go through the same
  conversion as everything else. `==` on immutable structs compares field
  by field (not `memcmp`, because of padding and `NaN`).
- Open: nested structs (fine by value), a struct holding a mutable struct
  (a pointer field — ownership again), `Union` fields.

### 3.2 Tuples and multiple return values

`return a, b` is a `Tuple{Float64, Int64}`. Two honest C forms:

1. **A struct per tuple type**, `typedef struct { double a; int64_t b; }
   Tuple_F64_I64;`, returned by value. The Julia `x, y = f(v)` becomes
   `Tuple_F64_I64 t = f(v); x = t.a; y = t.b;` — or, since the IR
   destructures through `getfield(t, 1)`, the temps collapse and the reader
   sees `f(v).a`. Field names: `a`, `b`, … by the same letter rule as
   helper inputs, or `_1`, `_2` — the letters read better.
2. **Out-parameters**, `void f(const double v[3], double *x, int64_t *y)`.
   This is what C programmers most often write, but it composes badly
   (`g(f(v))` can't be said) and loses the "a function returns its result"
   shape.

Recommended: 1, with 2 available when one of the tuple's parts is an array
(arrays already go out through a parameter, and a struct holding a large
array returned by value is a copy a hand-written program wouldn't make).
Homogeneous `NTuple{N,T}` is just a static vector and needs nothing new.

### 3.3 `Nothing`, `missing`, and `Union{T, Nothing}`

- A function returning `Nothing` is `void`.
- `Union{Float64, Nothing}` as "no answer": `NaN` is the C idiom for floats
  and matches `missing` arithmetic; for anything else, a struct
  `{ bool present; T value; }` — or a pointer that may be `NULL` when `T` is
  a struct. The IR tests `x === nothing`, which maps to `!r.present` or
  `isnan(x)` or `p == NULL` according to the choice.
- `Union`s of several concrete isbits types: a tagged union
  `struct { int tag; union { double d; int64_t i; }; }` with a `switch` on
  the tag wherever Julia dispatches. Only when a real use turns up.

### 3.4 Dynamic arrays, VLAs, and views

Three different things hide under `Array`:

1. **A size that varies per call but not during the call** — most numeric
   code. The C99 form is a VLA parameter: `void f(int m, int n, const
   double A[m][n], double out[m])`. It reads exactly like the static case,
   indexes the same, and the helpers generalize by taking the sizes as
   leading parameters: `add(m, n, A, B, out)`. This is the natural next
   step from `staticarray=false`, and it keeps every rule in `math/array.md`.
   Locals of runtime size are VLAs on the stack (fine for numeric sizes)
   or `malloc`ed above a threshold.
2. **A vector that grows** (`push!`, `pop!`, `append!`, `resize!`) needs
   heap storage: a generated `typedef struct { double *data; size_t length,
   capacity; } Vector_F64;` with `push_F64`, `pop_F64`, `free_F64` helpers
   over `realloc`. Julia's GC is replaced by one rule: whoever receives a
   vector from a function owns it and calls `free_…`; a vector passed in is
   borrowed. That rule is checkable at transpile time within one function.
3. **Views** (`@view A[:, j]`, `view(v, 2:3)`) are a pointer when the slice
   is contiguous in row-major storage (`&v[1]`, a row `A[i]`), and a
   `{ double *data; size_t length, stride; }` struct otherwise. Column
   views of a row-major matrix are the common strided case. A *copying*
   slice (`v[2:3]`, `A[:, j]` without `@view`) is a helper into a static
   array of the known size, which is what Julia does too.

### 3.5 Closures and higher-order functions

The IR sees `map(f, v)` with `f` a known function or a closure type whose
captured variables are its fields. Two cases:

1. **The function is known at transpile time** — nearly always. `map(x ->
   2x + c, v)` is one loop with the body inlined: `out[i] = 2 * v[i] +
   c;`. `reduce`, `foldl`, `sum(f, v)`, `filter` (into a static array with
   a count, or a dynamic vector), `any(f, v)`, `sort!(v, by = f)` all
   become the loops they are. No function pointer, no call. This is what a
   C programmer writes.
2. **The function must be a value** — handed to an external C API, stored
   in a struct — it becomes a function pointer plus a `void *` context
   struct holding the captured variables: the C callback idiom, generated
   once per closure type.

Recommended: 1, with 2 only at a `ccall` boundary. Named user functions
passed as values fall under 1 as well (inline them, or emit a call if they
are also transpiled).

### 3.6 Strings and printing

- A string literal is `"…"`, `const char *`. A `String` argument that is
  only read is `const char *s`. A string that is built (`*`, interpolation,
  `string(…)`) is a `char buf[N]` with `snprintf` when the length is bounded
  — it usually is, in numeric code — and `malloc` when it isn't, with the
  ownership rule from §3.4.
- `println(x, " ", y)` → `printf("%g %lld\n", x, y)` with the format chosen
  from the types (`%g` for floats, `PRId64` for `Int64`, `%s`, `%d` for
  `Bool` as `true`/`false`). Julia prints the shortest round-trip decimal;
  `%g` doesn't. `%.17g` does round-trip but is uglier. Decide once,
  document it, and note it as a rounding-level difference the philosophy
  allows.
- `@printf`/`@sprintf` formats are already C formats and pass straight
  through.
- `length(s)` counts characters in Julia and bytes in `strlen`; a UTF-8
  character count is a small loop. `s[i]` is a byte index in both.

### 3.7 Dispatch and generics

Every transpiled function is a concrete instance, so within the C there is
nothing to dispatch. The interesting mapping is toward the *caller*: a
Julia function `f` transpiled at `Float64` and `Float32` gives `f_F64` and
`f_F32`; a companion header can offer the Julia name back with C11's
`_Generic`:

```c
#define f(x) _Generic((x), double: f_F64, float: f_F32)(x)
```

so C code calls `f(x)` and gets the right one at compile time — Julia's
dispatch, statically. Abstract types in a signature are an error until then;
a runtime-polymorphic container (a `Vector{Shape}`) would need the tagged
union of §3.3 and a `switch`, and is far down the list.

### 3.8 Errors

C has no exceptions; a hand-written C program uses one of two idioms, and
Julia code tells us which:

1. **A `throw` that nothing catches** ends the program with a message in
   Julia. The C is `fprintf(stderr, "DomainError: …\n"); abort();` (or
   `exit(1)`). This covers `error("…")`, `throw(ArgumentError(…))`,
   `@assert` (→ `assert`, which is the same thing with a flag to remove
   it), and Julia's own checks we choose to reproduce (`Int(2.5)`,
   `div(1, 0)`). Same logical intent, one line.
2. **`try`/`catch` across a call** is the status-code idiom: a function
   that can throw returns `int` (0 for success, a code per exception type)
   and its value through an out-parameter; the caller's `try` becomes
   `if ((err = f(x, &y)) != 0) { … }`. Within a single function, a `try`
   block whose `throw`s are all local is a structured `if`.
   `finally` is the code after the block, on both paths.

Recommended: 1 now, since it needs nothing new; 2 when a real `try` turns
up. `setjmp`/`longjmp` would reproduce non-local exits faithfully and is
what no C author would choose.

### 3.9 `ccall` and existing C

`ccall((:sqrtf, "libm"), Float32, (Float32,), x)` is, in C, `sqrtf(x)`.
The transpiler can emit the call directly and an `extern` prototype (or an
`#include` when the header is known), turning Julia-that-calls-C into
C-that-calls-C. The same mechanism gives §3.5's callbacks somewhere to go.
A user's own C library becomes usable from Julia code that transpiles
cleanly — a strong reason to do this early.

### 3.10 Hints and flags

`@inbounds` is nothing (C never checks). `@fastmath` would be
`-ffast-math` or `#pragma STDC FP_CONTRACT`; the philosophy's rule is one fixed
flag for everything, so the honest mapping is to *ignore* it and choose
once, globally, whether the emitted C is compiled with fast math. `@simd`
likewise: the compiler vectorizes plain loops with the loops written as we
write them, and `restrict` on `out` (§2) does more for that than a pragma.
`Threads.@threads for` → `#pragma omp parallel for` is one line, one flag
(`-fopenmp`), and a real win; it fits the rule because the pragma is
harmless without the flag.

### 3.11 An entry point

Julia 1.11's `function (@main)(args) … end` is `int main(int argc, char
**argv)`; `args` is `argv[1..]` as `const char *`, `ARGS` likewise, the
return value the exit code (`nothing` → 0). Combined with printing (§3.6)
and file I/O this makes a transpiled program runnable, not just linkable.

### 3.12 Random numbers

Julia's default generator is Xoshiro256++, a public-domain algorithm of a
few dozen lines. Emitting it in C with the same seeding gives the *same
stream*, bit for bit — closer than the philosophy asks for. `rand()` →
`rand_F64(&rng)` with an explicit state struct (C's `rand()` is neither the
same algorithm nor reentrant); `randn()` needs Julia's ziggurat tables to
match exactly, or a Box–Muller with a documented difference.

### 3.13 Size types and signedness

Julia indexes with `Int` (signed 64-bit); C sizes are `size_t` (unsigned).
The C so far uses `int` loop counters for static sizes, which is what
people write. For runtime sizes (§3.4) the parameters should be `size_t`
to match the C world the code will live in, with the loop counters
following; a negative size is an error at the boundary, as it is in Julia.

### 3.14 Structured matrices

The transpose rule is a special case of something general: a tag on the
*type*, never on the storage, that changes how an operand is read. A
structured matrix is the same idea with two ingredients:

1. **A storage map**: where element `(i, j)` lives, with a sign. Transposed:
   `A[j][i]`. Symmetric stored in the lower half: `A[i][j]` if `i ≥ j`,
   else `A[j][i]`. Skew: the same with a minus sign on the mirrored side.
   Diagonal: `d[i]`, stored as a vector.
2. **A support**: which `(i, j)` can be nonzero at all. Full for transposed
   and symmetric; `j ≤ i` for lower triangular; `j = i` for diagonal;
   `|i − j| ≤ b` for banded; an explicit list for sparse.

Every kind is a (map, support) pair, and the transpose is (swap, full).
One rule — `access` plus `support` — reaches every generator, as `access`
alone does today.

- **Speed comes from loop bounds, not branches.** The support drives the
  bounds of the loops (`for k <= i` for a lower-triangular operand, one
  loop for a diagonal one), and a mirror map splits a loop at the diagonal
  rather than testing inside it. Inner loops stay branch-free. Where a
  result has structure, its dead half is written as zeros, as Julia's
  parent storage has them: `memset` then the support loop.
- **Julia supplies the algebra.** `L * L` is `LowerTriangular`, `L + A` a
  full matrix, `D * D` a `Diagonal`, `Symmetric * Symmetric` plain:
  inference hands us the result type, exactly as for `A * B'`. We
  implement reading and looping, never what a result "is".
- **Algorithms improve.** `L \ b` is forward substitution, `U \ b` back
  substitution, `D \ b` a divide, `det(L)` the product of the diagonal,
  `inv(D)` reciprocals; a symmetric positive-definite solve is Cholesky.
- **Names and comments** put the tag before the shape, next to `T2x3`:
  `L3x3`, `U3x3`, `D3`, `S3x3`; "lower-triangular 3×3-matrix", "diagonal
  3-vector". Unambiguous, since a type abbreviation comes *after* the shape.
- **Landing** follows Julia's type, as for transposes: `LowerTriangular` is
  lazy, so it lands as its parent's storage; `Diagonal` as its vector.

Order, decided by what Julia offers: `Diagonal`, `LowerTriangular`,
`UpperTriangular`, their unit variants, `Symmetric`, `Hermitian` are
standard-library wrappers that work on static arrays — diagonal and
triangular first, symmetric next. Skew-symmetric, banded, and
fixed-pattern sparse have no static type in Julia; where such a type
should come from is an open decision. Given one — a banded type carrying
its bandwidths, a sparse one its pattern — the loops are fixed at
transpile time, and a sparse product unrolls to exactly the nonzero
multiplies a person writes for a known stencil.

## 4. Where to start

By value per effort, in this order: `restrict` on `out` (free speed, no
new syntax); calling other transpiled functions and `ccall` (§3.9), which
make real programs possible; structs (§3.1); tuples (§3.2); reductions and
slices; VLA parameters for runtime sizes (§3.4.1); printing and `main`
(§3.6, §3.11). Dynamic vectors, strings that grow, `Dict`, and exceptions
across calls come after, each on demand.
