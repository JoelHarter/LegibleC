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

```julia
"One step of gravity toward the origin: position and velocity after `dt`."
function orbit(x::SVector{3,Float64}, v::SVector{3,Float64}, dt::Float64)
    r = norm(x)
    a = -x / r^3
    v = v + dt * a
    x = x + dt * v
    return [x; v]
end

transpile(orbit; outfile="body")
```

```c
/// 3-vector norm
/// returns norm(a)
static inline double norm_3(const double a[3]) {
    double sum = 0.0;
    for (int i = 0; i < 3; i++) {
        sum += a[i] * a[i];
    }
    return sqrt(sum);
}

/**
 * One step of gravity toward the origin: position and velocity after `dt`.
 *
 * Julia signature: orbit(x::SVector{3, Float64}, v::SVector{3, Float64}, dt::Float64), body.jl:8
 * @param[in]  x    3-vector
 * @param[in]  v    3-vector
 * @param[in]  dt   scalar
 * @param[out] out  6-vector, the return value
 */
void orbit(const double x[3], const double v[3], double dt, double out[restrict 6]) {
    // copy x and v to prevent modification within this function
    double x_[3];
    memcpy(x_, x, sizeof x_);
    double v_[3];
    memcpy(v_, v, sizeof v_);

    // body.jl:9: r = norm(x)
    double r = norm_3(x_);

    // body.jl:10: a = -x / r^3
    double a[3];
    div_3_s(x_, -(r * r * r), a);

    // body.jl:11: v = v + dt * a
    double temp1_dt_a[3];
    mul_s_3(dt, a, temp1_dt_a);  // temp1_dt_a = dt * a
    add_3(v_, temp1_dt_a, v_);  // v_ = v_ + temp1_dt_a

    // body.jl:12: x = x + dt * v
    double temp2_dt_v[3];
    mul_s_3(dt, v_, temp2_dt_v);  // temp2_dt_v = dt * v_
    add_3(x_, temp2_dt_v, x_);  // x_ = x_ + temp2_dt_v

    // body.jl:13: return [x; v]
    memcpy(out, x_, sizeof(double[3]));
    memcpy(&out[3], v_, sizeof(double[3]));
}
```

The other three helpers are in the same file, each with its two-line
comment. That is the whole output: one `.c`, C11, clean under
`-Wall -Wextra -Werror`.

## What you get

- **C you can read, review and sign off.** Every helper says what it
  computes. Every function carries its docstring as a Doxygen block. The
  Julia line each statement came from sits above it. Nothing betrays a
  machine's bookkeeping.
- **Speed a C programmer would accept.** Static sizes, stack arrays,
  `static inline` helpers, `restrict` where it is safe. The compiler is given
  what it would have been given by hand.
- **No runtime.** Nothing to allocate, initialize or link. The file compiles
  on its own, on anything with a C compiler.
- **Errors at transpile time, never wrong C.** Julia the transpiler doesn't
  understand is refused with a message. What comes out computes what the
  Julia computes.
- **One source of truth.** The Julia is the program; the C is a view of it.
  Change the Julia, regenerate, and the two never drift.

## Where it fits

Embedded and real-time control. Flight and vehicle software. Simulation
kernels that must run where there is no runtime. Numerical libraries exposed
through a C ABI to every other language. Anywhere the code that ships has to
be read by a person who didn't write it.

## How it differs

- **From compiling Julia to a binary.** That gives you an executable or an
  object file. This gives you source: something to read, audit, edit, and
  keep when the toolchain changes.
- **From generic C backends.** Their output is correct and unreadable. Here
  legibility is a design tenet, behind only correctness and speed.
- **From writing the C yourself.** It is the same C, without the weeks and
  the transcription errors, and it stays in step with the Julia for as long
  as the Julia lives.

## What it is not

- **Not a Julia compiler.** No garbage collector, dynamic dispatch, strings,
  growing arrays, closures or exceptions. Every size is known at transpile
  time. Code that needs Julia's runtime needs Julia.
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
given a size in the call. One `.c` file comes out — prototypes, the helpers
it needs, the functions — and anything a listed function calls comes with
it. `transpile` is the package's one exported name, so your own functions
can be named anything.

[doc/guide.md](doc/guide.md) is the user guide: targets, every option,
calling the C, how names come out and how to override them.
[doc/syntax.md](doc/syntax.md) is the one-page list of every piece of Julia
accepted.

## Documentation

- [doc/philosophy.md](doc/philosophy.md) — the tenets behind every
  decision: logic, speed, craft, generality, in that order.
- [doc/](doc/) — how the transpiler works, one topic per file; its README
  gives a reading order.
- [doc/dev/](doc/dev/) — the decision log, and the survey of what could
  still map between Julia and C.
- [todo.md](todo.md) — what's open.

## Tests

```
julia test/runtests.jl
```

Every test transpiles a few Julia functions, builds a C program that calls
them on fixed inputs, and compares what C prints with what Julia computes
for the same calls.
