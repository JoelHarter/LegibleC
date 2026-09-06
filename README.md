# LegibleC

Write numerical code in Julia. Get the C you would have written by hand.

## The problem it solves

Numerical work gets written twice. Once in a language made for thinking —
Julia, Python, MATLAB — where an idea becomes a working function in an
afternoon. Then again in C, because the code has to run on a
microcontroller, inside a flight computer, in a library someone else links,
or anywhere a reviewer must read what ships. The second writing takes weeks,
introduces its own bugs, and produces a file nobody wants to own. From then
on there are two versions, and they drift.

LegibleC removes the second writing. You keep the Julia — it still runs,
tests and plots as before — and the C is generated from it: fixed-size
arrays on the stack, small helpers named for the mathematics they do, your
comments and docstrings carried across, no allocation, no runtime, nothing
to link but the C standard library. It reads as if a careful engineer wrote
it, because that is the standard it is held to.

## An example

The Julia source, as a physicist writes it:

```julia
"One semi-implicit Euler step of a damped oscillator with natural frequency `ω₀` and damping ratio `ζ`."
function step(x::Float64, ẋ::Float64, ω₀::Float64, ζ::Float64, Δt::Float64)
    ẍ = -2ζ * ω₀ * ẋ - ω₀^2 * x
    ẋ += Δt * ẍ
    x += Δt * ẋ
    return x, ẋ
end

"Total energy of a particle of mass `m` at `r` moving at `v`, in a gravity well of strength `μ`."
energy(m::Float64, r::SVector{3,Float64}, v::SVector{3,Float64}, μ::Float64) = m * ((v ⋅ v) / 2 - μ / norm(r))

transpile(step, energy; outfile="body")
```

<h1 align="center">⬇</h1>

The C that LegibleC produces from nothing but that source. First the
header a caller includes, `body.h`:

```c
#ifndef BODY_H
#define BODY_H

/// the return value of step: x and xdot, as one struct since C returns one value
typedef struct {
    double x;
    double xdot;
} step_t;

/**
 * One semi-implicit Euler step of a damped oscillator with natural frequency `ω₀` and damping ratio `ζ`.
 *
 * Julia signature: step(x::Float64, ẋ::Float64, ω₀::Float64, ζ::Float64, Δt::Float64) @body.jl:4
 * @param[in] x       scalar
 * @param[in] xdot    scalar
 * @param[in] omega0  scalar
 * @param[in] zeta    scalar
 * @param[in] Deltat  scalar
 */
step_t step(double x, double xdot, double omega0, double zeta, double Deltat);

/**
 * Total energy of a particle of mass `m` at `r` moving at `v`, in a gravity well of strength `μ`.
 *
 * Julia signature: energy(m::Float64, r::SVector{3, Float64}, v::SVector{3, Float64}, μ::Float64) @body.jl:12
 * @param[in] m   scalar
 * @param[in] r   3-vector
 * @param[in] v   3-vector
 * @param[in] mu  scalar
 */
double energy(double m, const double r[3], const double v[3], double mu);

#endif
```

Then the functions, `body.c`:

```c
#include "helper.h"
#include "body.h"

step_t step(double x, double xdot, double omega0, double zeta, double Deltat) {
    // @body.jl:5: ẍ = -2ζ * ω₀ * ẋ - ω₀^2 * x
    double xddot = -2 * zeta * omega0 * xdot - omega0 * omega0 * x;

    // @body.jl:6: ẋ += Δt * ẍ
    xdot += Deltat * xddot;

    // @body.jl:7: x += Δt * ẋ
    x += Deltat * xdot;

    // @body.jl:8: return x, ẋ
    return (step_t){x, xdot};
}

double energy(double m, const double r[3], const double v[3], double mu) {
    // @body.jl:12: m * ((v ⋅ v) / 2 - μ / norm(r))
    return m * (dot_3(v, v) / 2 - mu / norm_3(r));
}
```

`helper.h` beside them holds `dot_3` and `norm_3`, each a few lines with
a two-line comment saying what it computes. That is the whole output: an
`out/` folder, C11, clean under `-Wall -Wextra -Werror`.

## What you get

- **C you can read, review and sign off.** Every helper says what it
  computes. Every function carries its docstring as a Doxygen block, in a
  header a caller can include. The Julia line each statement came from sits
  above it. Nothing betrays a machine's bookkeeping.
- **Your names, your structure.** `ω₀` is `omega0`, `ẋ` is `xdot`, `ħ` is
  `hbar` — the name you typed to get the character, from Julia's own table,
  or your own spelling if you prefer. A function returning `x, ẋ` returns a
  `step_t` with fields `x` and `xdot`. A constant a function reads becomes a
  named C constant; a name from another module keeps the module in front.
- **Speed a C programmer would accept.** Static sizes, stack arrays,
  `static inline` helpers, `restrict` where it is safe, `sincos` as the two
  calls the compiler fuses. The compiler is given what it would have been
  given by hand.
- **No runtime.** Nothing to allocate, initialize or link. The folder
  compiles on its own, on anything with a C compiler.
- **Errors at transpile time, never wrong C.** Julia the transpiler doesn't
  understand is refused with a message. What comes out computes what the
  Julia computes, in the same order, to rounding.
- **One source of truth.** The Julia is the program; the C is a view of it.
  Change the Julia, regenerate, and the two never drift.

## Where it fits

Embedded and real-time control. Flight and vehicle software. Simulation
kernels that must run where there is no runtime. Numerical libraries exposed
through a C ABI to every other language. Anywhere the code that ships has to
be read by a person who didn't write it.

## How it differs

- **From compiling to a binary** — `juliac`, PackageCompiler, StaticCompiler,
  and their counterparts for other languages. They run the language's own
  compiler, so what they produce is the program exactly, and they take far
  more of the language than this does. But what they produce is machine
  code: nothing to read, nothing to review, nothing to keep when the
  toolchain moves on. And it comes with the language's runtime on board —
  trimming it down is possible and hard — where this needs nothing but the
  C standard library. This produces source, and source is the artifact
  every other tool in an engineering process knows what to do with.
- **From generic C generators** — MATLAB Coder, Cython, f2c. Their C is
  correct and complete, and it will compile years from now. It also reads
  like it was generated: names nobody chose, arrays behind a runtime of
  their own, control flow no person would write. Here legibility is a
  design tenet, behind only correctness and speed: the output is held to
  the standard of hand-written C, and it shows.
- **From writing the C yourself.** Nothing beats it, which is why the goal
  here is to be indistinguishable from it: this is what a competent C
  programmer would have written, generated for you, and generated again
  every time the Julia changes, so keeping the two in sync costs nothing.
  The one thing you give up is editing the C by hand, since the next run
  writes over it — the Julia is where changes go.
- **From asking an AI.** Models are astonishing at code, and any of them
  will turn what you paste into C on request. What comes back depends on
  the model, the day, the wording, and whether the bill was paid. This is
  deterministic: the same input gives the same output, every time, offline,
  in a CI job, with no model and no network — and where it can't translate
  something, it says so instead of guessing.

## What it is not

- **Not a Julia compiler.** No garbage collector, dynamic dispatch, strings
  built at run time, growing arrays, closures or exceptions. Every size is
  known at transpile time. Code that needs Julia's runtime needs Julia.
- **Not bit-exact.** The C computes the same thing by the same steps; the
  last bit of a rounded result may differ.
- **Not a way to make Julia faster.** Julia is already fast. This is for
  when the code has to leave Julia.

## Using it

```julia
] dev /path/to/LegibleC        # or: ] add https://github.com/JoelHarter/LegibleC
using LegibleC
transpile(f, g, (h, Float64, 3, Float64, 2, 3); outfile="name", outpath=dir)
```

A target is a function with one concrete method, or a function with its
argument types spelled out, where a type followed by integers is an array of
that element type and size. Arrays are `StaticArrays` types, or `Array`s
given a size in the call. An `out/` folder comes out: `<outfile>.h` for
callers, `<outfile>.c` with the functions, `helper.h` and `helper.c` with
the generated helpers they need — and anything a listed function calls
comes with it. Constants a function reads come along too, and any you list
by keyword, `transpile(f; g, μ)`; `@transpile` does the same from inside a
module. `transpile` and `@transpile` are the package's only exported names,
so your own functions can be named anything.

[doc/guide/](doc/guide/README.md) is the user guide: what's accepted,
targets, every option, calling the C, how names come out and how to
override them.

## Documentation

- [doc/philosophy.md](doc/philosophy.md) — the tenets behind every
  decision: logic, speed, craft, generality, in that order.
- [doc/guide/](doc/guide/README.md) — the user guide.
- [doc/](doc/) — how the transpiler works, one topic per file; its README
  gives a reading order.
- [doc/dev/](doc/dev/) — the decision log, and the survey of what could
  still map between Julia and C.
- [doc/dev/todo.md](doc/dev/todo.md) — what's open.

## Tests

```
julia test/runtests.jl
```

Every test transpiles a few Julia functions, builds a C program that calls
them on fixed inputs, and compares what C prints with what Julia computes
for the same calls.
