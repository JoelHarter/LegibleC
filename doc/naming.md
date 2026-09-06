# Naming

How the emitted C names things: first how Julia names are made valid in C,
then how the names the transpiler invents are chosen. The names of the
generated helpers (`add_2x2`, `mulP_3_3x2`) follow their own rule,
described in `helper.md`.

## Variables and functions

Julia allows nearly any Unicode in a name; C allows `[A-Za-z0-9_]`. Every
Julia name that reaches the output — variables, functions, types, fields,
anything — is converted before anything else happens, so the temp rules below
only ever see C-valid names.

The name is first put through Unicode compatibility decomposition (NFKD). That
turns subscripts, superscripts and fractions into plain characters (`₁` → `1`,
`¹` → `1`, `ᵃ` → `a`), font variants into their base letter (`ℝ` → `R`,
`ℓ` → `l`, `µ` → `μ`, `ϵ` → `ε`), and splits an accent off the letter it sits
on. Then, character by character:

| Julia | C | Rule |
|---|---|---|
| `finename` | `finename` | ASCII letters, digits, `_` are kept |
| `ω`, `Ω`, `ħ`, `∂`, `∞` | `omega`, `Omega`, `hbar`, `partial`, `infty` | **Julia's own table**: the name one types after `\` to get the character |
| `x₁`, `x¹` | `x1` | subscripts and superscripts become plain |
| `ẋ`, `x̂`, `x̄`, `ẍ`, `x⃗`, `x′` | `xdot`, `xhat`, `xbar`, `xddot`, `xvec`, `xprime` | combining marks are in the table too, appended with no `_` |
| `🤠` | `facewithcowboyhat` | emoji are in the table, as one word |
| `ε`, `φ`, `∇`, `ð` | `epsilon`, `phi`, `nabla`, `eth` | the handful of overrides, where the table's name isn't the reader's word |
| anything else | `U1F920` | `U` + code point in hex |

The table is the REPL's `\name<tab>` completion list, LaTeX names and emoji
names, read from Julia itself — so the C says what the author typed, and
nothing is spelled in two places. A character with several names takes the
shortest (`del` for `∇`, hence the override to `nabla`). A name is stripped to its letters and digits — `star-struck`
is `starstruck`, `e-mail` is `email`, and `face_with_cowboy_hat` loses its
underscores too, since the name stands for one indivisible character and
`_` is for separating words in a name — and if what's left doesn't start
with a letter (`100`), the hex form applies; `👍` is `thumbsup` by
override. Nothing is needed for names
that would start with a digit: Julia already forbids a leading digit,
subscript, or superscript.

**Your own spellings** sit on top of all of that: `transpile(…;
spelling=Dict('ħ' => "hred", '∂' => "d"))`. Keys are single characters that
Julia allows in a name, other than ASCII letters, digits and `_`, which are
themselves; values are C identifier text. A character in the dictionary is
spelled as given before any decomposition, so `'ε' => "eps"` names both
`ε` and `ϵ`, and the collision rule tells the two apart.

A trailing `!` — Julia's mark for a function that mutates its argument — is
dropped: `bump!` becomes `bump`. C has no such mark, and `bumpU21` would be
the alternative.

**Collisions.** After conversion, a name that is reserved, or that matches any
other name already in the same scope, gets `_` appended, repeatedly, until
it's unique: a variable `long` becomes `long_`; with both `omega` and `ω` in
scope, whichever comes second becomes `omega_`. Function names are checked the
same way, after the mangling below. Nothing is ever refused for its name.

An array parameter that Julia reassigns keeps its name for the parameter;
the working copy is the same name under this rule, `x_` (`math/array.md`,
*Assignment and aliasing*). A scalar parameter is simply reassigned.

A name that starts with `_` has its leading underscores moved to the end
(`_x` → `x_`, `__Foo` → `Foo__`), because C reserves every such name at file
scope and `_X…`/`__…` everywhere. The reserved list itself is described
below.

**Generated helpers** (`add_2x2`, `mulP_3_3x2`, …, see `helper.md`) live in
the same file as the user's functions, so their names can collide with the
user's. Their names are known only once everything has been generated, so
the check comes last: a *variable* that matches a helper is renamed with `_`
like any other collision (the function is generated again with the helper
names blocked); a *function* that matches one is an error, since a
function's name is the C interface and quietly changing it would mislead the
caller.

## Function names: the same function at several signatures

A function transpiled at one signature keeps its plain name. When several
instances of the same function are in one output, they're told apart by
appending a description of each argument — escalating only as far as needed
for the names to differ, and applied uniformly to the whole group:

1. **Array dimensions.** `3` for a 3-vector, `2x3` for a 2×3 matrix, `4x3x4`
   and so on. Scalars contribute nothing at this level, so two scalar-only
   instances fall straight through.
   `g_3`, `g_2x3`
2. **Type abbreviation,** after — from the table in `math/scalar.md`, an array
   described by its element type. A function whose arguments are all
   `Float64` leaves the abbreviations off entirely.
   `poly`, `poly_I64_I64`, `poly_F32_F32`
   `fun4_2x2_2x2`, `fun4_2x2F32_2x2F32`
   `h_3`, `h_3F64_I64`

There is no static/mutable distinction in the name: C has none, and under
`staticarray` every array is the same thing in C. Asking for the same method
at `SMatrix{2,2}` and at `MMatrix{2,2}` yields one C function, emitted once.
The only error is two *different* Julia methods landing on the same C
signature — C can't hold both bodies.

A regular array is described exactly like a static one under the
`staticarray` option — it needs a size from somewhere other than its type
(`math/array.md`).

Implementation: `mangled` in `src/name.jl`.

## Reserved words

A hand-maintained list in `src/reserved.jl`: the C keywords, `main`, and
the names of every standard header the output might include *or that C
written around the output commonly does* — `stdint`, `stdlib`, `string`,
`stdio`, `math` in all three widths, `time`, `ctype`, `limits`, `float`,
`errno`, `assert`. A name on the list gets `_`: a Julia `exp`, `time`, or
`index` comes out as `exp_`, `time_`, `index_`.

Header names are reserved **always**, even in a file that doesn't include
that header. Two reasons:

- *The C changes less between development updates.* If reservation depended
  on what each file happened to include, then adding `math.h` to the
  emitter later would silently rename `exp` to `exp_` in output that used
  to say `exp`. Reserving up front means a name that was fine stays fine.
- *The C is more compatible with code from outside.* Someone linking our
  output against their own C, which may include any of those headers, never
  finds our names fighting with the standard library's.

When a new header joins the set the output can emit, add its names.
Implementation: `identifier` and `identifiers` in `src/name.jl`.

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
- The temp holding the result of a call to one of the author's functions is
  named after what that function returns, when it returns a variable of
  the author's: `omega(x, y) = (ω = x + y; ω)` gives `temp1_omega = omega(x, y)`.
  For an unnamed tuple being unpacked, `return x, ẋ`, it is the function
  itself: `temp1_step`. Otherwise — the callee returns an expression — the
  call's operands, like any operation
- The suffixes are the `tempsuffix` option of `transpile`, on by default;
  off, every temp is its bare `temp<N>`. Numbering never depends on the
  suffix, so a name can only ever look odd, not be wrong
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
line — the C returns that variable. An unnamed scalar calculation is returned
as written, `return a + c * c;`, like any other scalar work the author didn't
name (`copy.md`). Only a value that can't be written inside the `return` —
the result of a `ccall`, or one returned from more than one place — is stored
first, in a variable named `result` rather than as a temp:

```c
double fun45(double a, double c) {
    return a + c * c;
}

double resulttaken(double a, double result) {
    double result_ = fabs(a * result);
    return result_;
}
```

`result` is an ordinary name in the function's scope and collides like any
other: if the user already has a `result`, as above, the result is `result_`.
Anything more specific than `result` should be written as a named variable in
the Julia, and will come through as such.

When the result is an *array* it can't be returned; it comes out through a
trailing parameter, and an output parameter in C is called `out` — `out_` if
the Julia already uses `out`. That is the same name every generated helper
uses for its output, so `add_2x2(A, B, out)` and `void add(…, double
out[2][2])` read alike. `out` was deliberately not used for a returned
scalar, where it would suggest a parameter that isn't there.

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
