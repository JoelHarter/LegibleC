# Naming

How the emitted C names things: first how Julia names are made valid in C,
then how the names the transpiler invents are chosen.

## Variables and functions

Julia allows nearly any Unicode in a name; C allows `[A-Za-z0-9_]`. Every
Julia name that reaches the output — variables, functions, types, fields,
anything — is converted before anything else happens, so the temp rules below
only ever see C-valid names.

The name is first put through Unicode compatibility decomposition (NFKD). That
turns subscripts and superscripts into plain characters (`₁` → `1`, `¹` → `1`,
`ᵃ` → `a`), maps lookalikes to their base letter (`µ` → `μ`), and splits an
accent off the letter it sits on. Then, character by character:

| Julia | C | Rule |
|---|---|---|
| `finename` | `finename` | ASCII letters, digits, `_` are kept |
| `ω`, `Ω` | `omega`, `Omega` | Greek letters are spelled out, case preserved |
| `x₁`, `x¹` | `x1` | subscripts and superscripts become plain |
| `ẋ`, `x̂`, `x̄`, `ẍ`, `x⃗` | `xdot`, `xhat`, `xbar`, `xddot`, `xvec` | combining marks are named and appended, no `_` |
| `x′` | `xprime` | primes likewise (`dprime`, `tprime`) |
| `🤠` | `U1F920` | anything else: `U` + code point in hex |

The full set of mark names: `grave acute hat tilde bar breve dot ddot ring
check vec dddot prime dprime tprime` — repeated marks follow LaTeX (`ddot`,
`dddot`). Nothing is needed for names that would start with a digit: Julia
already forbids a leading digit, subscript, or superscript.

**Collisions.** After conversion, a name that is reserved, or that matches any
other name already in the same scope, gets `_` appended, repeatedly, until
it's unique: a variable `long` becomes `long_`; with both `omega` and `ω` in
scope, whichever comes second becomes `omega_`. Function names are checked the
same way, after the mangling below.

## Function names: the same function at several signatures

A function transpiled at one signature keeps its plain name. When several
instances of the same function are in one output, they're told apart by
appending a description of each argument — escalating only as far as needed
for the names to differ, and applied uniformly to the whole group:

1. **Array dimensions.** `3` for a 3-vector, `2x3` for a 2×3 matrix, `4x3x4`
   and so on. Scalars contribute nothing at this level, so two scalar-only
   instances fall straight through.
   `g_3`, `g_2x3`
2. **Array class,** in front of the dimensions: `S` for a static (immutable)
   array, `M` for a mutable one, nothing for a regular array. Added only if
   the classes actually differ somewhere in the group; if every array is
   static, the `S` stays off.
   `g_S3`, `g_M3`
3. **Type abbreviation,** after — from the table in `type.md`, an array
   described by its element type. A function whose arguments are all
   `Float64` leaves the abbreviations off entirely.
   `poly`, `poly_I64_I64`, `poly_F32_F32`
   `fun4_2x2_2x2`, `fun4_2x2F32_2x2F32`
   `h_3`, `h_3F64_I64`

A regular array's size isn't in its type, so for now it's described by its
dimension count: `1D`, `2D`. See `type.md`.

Implementation: `mangled` in `src/name.jl`.

**Linear algebra helpers** are named on their own, stricter rule — always
size and type, never class — described in `array.md`.

**Reserved words** are a hand-maintained list in `src/reserved.jl`: C keywords,
the names from every standard header the output *might* include, and anything
the transpiler's own naming scheme claims.

Header names are reserved **always** — even in a file that doesn't include
that header. A Julia variable called `exp` becomes `exp_` whether or not
`math.h` is anywhere in sight. Two reasons:

- *The C changes less between development updates.* If reservation depended
  on what each file happened to include, then adding `math.h` to the
  emitter later would silently rename `exp` to `exp_` in output that used
  to say `exp`. Reserving up front means a name that was fine stays fine.
- *The C is more compatible with code from outside.* Someone linking our
  output against their own C, which may include any of those headers, never
  finds our names fighting with the standard library's.

The headers currently covered are `stdint.h`, `stdbool.h`, `stddef.h`, and
`math.h`; when a new one joins the set the output can emit, add its names.

Implementation: `identifier` and `identifiers` in `src/name.jl`; the list in
`src/reserved.jl`.

## Temporaries

An intermediate value that has no Julia name becomes a C local called a
*temp*. Within each function:

**Base.** Temps are numbered in order of creation: `temp1`, `temp2`, `temp3`, …

**Suffix.** The names of the variables used *directly* in the calculation are
appended, in order of first appearance, separated by `_`:

```c
double temp1_a_b = a + b;
```

- Literals and other unnamed terms contribute nothing:
  `temp2_a_b = a + b + 58.3`
- A variable appears at most once: `temp7_a = a * a`
- A temp passes along its *suffix*, never its base:
  `temp8_a_b = temp7_a + b` and `temp9_a = temp6 + a`
- A temp with no named inputs is just its base: `temp6 = 58`
- There is one rule for what a name contributes, and it doesn't care whether
  the name is one of our temps or the user's own: chop a leading `temp<N>_`
  if there is one, then split at `_`. So `temp5_joel_was_here_eh =
  temp4_joel_was_here * eh` whether `temp4_joel_was_here` was ours or the
  user's, and a variable named plain `temp3` contributes nothing, like any
  bare temp. Since pieces are deduplicated, `temp4_joel_was_here * here`
  gives `temp5_joel_was_here`.

**Skipped numbers.** If any variable in the function is named `temp<N>` or
`temp<N>_…`, the number N is never used for a temp, so a reader can't confuse
the two. Only that exact number is blocked: a variable `temp1001` blocks
`temp1001` and nothing else. A name has to have digits after `temp` to block
anything — plain `temp` blocks nothing.

**Length limit.** If the full mangled name would be longer than `templimit`
(a `transpile` option, default 40 characters), the suffix is dropped and the
temp is just its base:

```c
double temp11 = thisisahugelongvariablename + andanotherreallylongname;
```

The limit applies to the whole name, base included. A temp that lost its suffix
this way passes nothing along to later temps, same as any bare temp.

## Results

If the function returns a named variable — `return x`, or `x` as the last
line — the C returns that variable. If the last thing is an unnamed
calculation, that calculation is the function's result and is named `result`
rather than as a temp:

```c
double fun45(double a, double c) {
    double temp1_c = c * c;
    double result = a + temp1_c;
    return result;
}
```

`result` is an ordinary name in the function's scope and collides like any
other: if the user already has a `result`, the result is `result_`. (`out`
was considered and rejected: in C it connotes an output parameter. Anything
more specific than `result` should be written as a named variable in the
Julia, and will come through as such.)

A temp that gets stored into a variable is referred to by that variable from
then on (provided the variable isn't reassigned), so `d = (a + b) * c / 2` as
the last line returns `d`, not the temp behind it.

## Not a naming rule: copies don't become temps

When the IR merely copies a value — reading a variable, or aliasing one SSA
value to another — no temp is created; later references use the original
name. That is a separate concern from how temps are named; the conditions
under which it's safe, and what's deliberately left undone, are in
`copy.md`.

## Implementation

`temp!` in `src/c.jl` applies the temp rules and `contribution` decides what a
value passes along; `Scope` holds the per-function state (counter, blocked
numbers, and what each SSA value is called in C).
