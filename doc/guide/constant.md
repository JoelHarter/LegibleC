# Constant

How a Julia constant comes out in C, and how to get a `#define`.

## A `const` is a `static const`

A global a function reads comes out with it, named as Julia named it and
`const` when the Julia binding is:

```julia
const c = 299_792_458.0   # speed of light, m/s
```

```c
// @codata.jl:5: const c = 299_792_458.0   # speed of light, m/s
static const double c = 2.99792458e8;
```

It lives in the header, so every file that includes it can fold it. An array
is written with its initializer, a matrix one row per line, and the
initializer is the Julia expression where a static initializer can hold it,
so `const τ = 2π` is `2 * LEGIBLEC_PI`. A typed global, `k::Float64 = 2.0`,
is a plain global in the `.c` and `extern` in the header. See
[target.md](target.md).

A function may give a typed scalar global a new value, `global count += 1`,
and the C does the same to its global: `count++;`. An array global's elements
can be written, `tally[2] += k`; the array itself can't be replaced.

Every global starts in C from the value it holds at the moment it is
transpiled: the C picks up where Julia is, and from there on the same calls
give the same results in both. For a counter that an earlier run has left at
15, that means the C starts at 15. The transpiler says so when it happens, as
a warning and as a comment beside the value, and there are two ways to start
elsewhere: transpile before running anything that changes it, or give the
value, `transpile(bump; counter = 0)`.

## A macro constant is an irrational

`π` is not `3.141592653589793` in the C; it is `LEGIBLEC_PI`, defined once
in the helper header:

```c
#define LEGIBLEC_PI 3.1415926535897932384626433832795028  // π to 128-bit precision
```

The rule behind it is general: any value of Julia's `AbstractIrrational`
type is written as a macro named `LEGIBLEC_` plus its symbol's C spelling in
capitals, defined to 128-bit precision, which the C compiler rounds to the
same double Julia uses. `ℯ` is `LEGIBLEC_E`, `Base.MathConstants.γ` is
`LEGIBLEC_GAMMA`, `catalan` is `LEGIBLEC_CATALAN`. Only the ones the output
uses are defined, and a file that uses one includes the helper header. Two
symbols that spell the same, `φ` and `ϕ`, get `LEGIBLEC_PHI` and
`LEGIBLEC_PHI_`. (The `posix` option writes `M_PI` and `M_E` for π and ℯ
instead; POSIX names nothing else.)

The name follows the symbol, never a value. A `3.141592653589793` you typed
stays digits, and a `const` of yours holding that value is your own `static
const`.

## Making your own

So a macro constant of your own is an irrational of your own. The quick way
is Julia's macro, with the value as a `BigFloat` expression:

```julia
Base.@irrational root2 sqrt(big(2))
Base.@irrational twopi 6.283185307179586 2 * big(π)
Base.@irrational ħ big"1.054571817e-34"
```

The two-argument form computes the `Float64` from the big value; the
three-argument form takes it explicitly and Julia checks the two agree. From
then on `root2` behaves like `π` everywhere in Julia and is
`LEGIBLEC_ROOT2` in the C, defined to 128-bit precision.

Two things to know. Julia's docstring for `Base.@irrational` warns that it is
meant for Base, because it makes a type `Irrational{:root2}` regardless of
where it is invoked, and two packages choosing the same name with different
values would clash; in your own program that is your own naming to keep
straight, and the transpiler handles a clash of *C* spellings. And the
macro is not marked public API. The public way is a type of your own:

```julia
struct Root2 <: AbstractIrrational end
const root2 = Root2()
Base.BigFloat(::Root2; precision=precision(BigFloat)) = sqrt(BigFloat(2; precision))
Base.Float64(::Root2) = 1.4142135623730951
Base.Float32(::Root2) = 1.4142135f0
Base.:(==)(::Root2, ::Root2) = true
Base.hash(::Root2, h::UInt) = hash(:root2, h)
```

which comes out the same, `LEGIBLEC_ROOT2`, named after the type.

## Don't feel bad about the name

Nothing requires the value to be irrational. Julia's own docstring for
`AbstractIrrational` describes the type as "an exact irrational value, which
is automatically rounded to the correct precision in arithmetic operations
with other numeric quantities", and goes straight on to subtypes "used to
represent values that may occasionally be rational", its example a
square-root type that is rational whenever the radicand is a square. The
type's meaning is *an exact constant, rounded to the precision of whatever it
meets*, which is exactly what a C macro constant is; the name is history. A
design parameter, a material property, a conversion factor you want as a
`#define` are all fine as irrationals.

The one thing an irrational is not is an integer. `const N = 8` comes out as
`static const int64_t N = 8;`, which C won't accept as an array bound at file
scope; a `#define N 8` for that is on the todo. Sizes in the Julia are
usually static already (`SVector{N}`), and then they are just numbers in the C.
