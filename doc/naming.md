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
it's unique: a variable `long` becomes `long_`. When two names meet — both
`omega` and `ω` in scope — which one keeps the name, and whether either has to
change at all, is [below](#when-two-names-meet). Function names are checked
the same way, after the mangling below.

An array parameter that Julia reassigns keeps its name for the parameter;
the working copy is `x_local` (`math/array.md`, *Assignment and aliasing*). A
scalar parameter is simply reassigned. A mutable array variable that moves
between arrays, `x, xnew = xnew, x`, is a pointer under the author's name,
and the array it starts with is `x_data`, a name of the transpiler's that
gives way to the author's like any other (`math/array.md`, *One array under
two names*).

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

## Modules

C has one namespace per program where Julia has one per module, so a name
carries its module path, joined with `_`, relative to the module the
`transpile` call was written in (its `scope`; `@transpile` sets it): from
`Main`, `Physics.c` is `Physics_c`, `Earth.Orbit.a` is `Earth_Orbit_a`, and
`Physics.speed` is `Physics_speed`; from inside `Physics`, `c` and `speed`
are bare, and `Earth.Orbit.a` from inside `Earth` is `Orbit_a`. `Main`
contributes nothing, being the program. This applies to functions, globals
and struct types alike, and reading a name through an import doesn't change
it: `c` after `using Physics` is still `Physics_c`, which says where it came
from. Whatever still collides after that gets `_` like any other collision.

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

There is no static/mutable distinction in the name: C has none, and every
array is the same thing in C. Asking for the same method
at `SMatrix{2,2}` and at `MMatrix{2,2}` yields one C function, emitted once.
The only error is two *different* Julia methods landing on the same C
signature — C can't hold both bodies.

A regular array is described exactly like a static one — it needs a size
from somewhere other than its type (`math/array.md`).

Implementation: `mangled` in `src/name.jl`.

## A type with parameters

A struct with type parameters is one C struct for each set of them, and its
name is the struct's with the parameters run on after it. The innermost
list is joined by one `x`. Each list around it is joined by one more `x`
than the deepest thing it holds. So what belongs together sits closest
together, and the widest gap is the outermost split. An array's size,
`3x3`, is the same rule and always was.

| Julia | C |
|---|---|
| `Pair2{Float64}` | `Pair2F64` |
| `Body{3}` | `Body3` |
| `Tuple{Float64, Int64}` | `TupleF64xI64` |
| `Obj{Bool, 3, 3}` | `ObjBx3x3` |
| `Obj{Bool, SMatrix{3,3,Float64}}` | `ObjBxx3x3` |
| `Obj{SVector{3,Float64}, 3}` | `Obj3xx3` |
| `Outer{Inner{Bool, 3}, 8}` | `OuterInnerBx3xx8` |
| `Outer{Inner{Bool}, 8}` | `OuterInnerBxx8` |

Read it by the gaps: split at the longest run of `x` first, then inside each
piece at the next longest. In `OuterInnerBx3xx8` the `xx` splits `Outer`'s
two parameters, `InnerBx3` and `8`, and the `x` splits `Inner`'s. An array
and a struct with one parameter count as a level even where nothing is
joined inside them, or `Outer{Inner{Bool}, 8}` and `Outer{Inner{Bool, 8}}`
would be one name.

The number of `x` in a name can change when a parameter becomes a deeper
type. That is a change to the type itself, so the name is right to change.

There is no underscore in a type's name, because in a function's name `_`
means "next argument" and nothing else. `scale_ObjBxx3x3_F64` is `scale` of
an `Obj{Bool, 3×3}` and a `Float64`, with one reading.

The name depends on the type alone. It is not shortened where that happens
to be unambiguous in one program and lengthened where it isn't, because then
adding a type somewhere else would rename this one underneath whoever calls
the C.

What it does not settle: where an author's own name ends, when that name
itself ends in a digit or holds a capital. `Vec3F64` is `Vec3{Float64}` to
whoever has the header, and the header always has the `typedef`.

## Reserved words

A hand-maintained list in `src/reserved.jl`: the C keywords, `main`, and
the names of every standard header the output might include *or that C
written around the output commonly does* — `stdint`, `stdlib`, `string`,
`stdio`, `math` in all three widths, `time`, `ctype`, `limits`, `float`,
`errno`, `assert`; and the POSIX names with external linkage (`read`,
`write`, `pipe`, `select`, `signal`…), which the output never includes but
which a function of the author's would *replace* for the whole program if it
came out under one. A name on the list gets `_`: a Julia `exp`, `time`, or
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

## When two names meet

Julia keeps apart things that C would let collide, and C's way of resolving a
collision inside a function is to let the inner name hide the outer one,
silently. So the question is never "are these two names equal" but "would C
resolve any mention differently from Julia". The aim, in this order: never a
wrong answer from a name; then keep the author's name, since their naming is
part of their craft.

### When a shared name is harmful

Two different things with one C identifier are a problem in exactly three
cases, which follow from C's own rules (its name spaces, its scopes, and
macros outside both):

1. **The same block.** Two locals at one level, a parameter and a local of the
   function's outer block, two functions or globals at file scope, two members
   of one struct. C refuses to compile.
2. **Nested, and the inner block mentions the outer thing.** The mention lands
   on the inner one. If the inner block never mentions the outer thing,
   nothing can go wrong.
3. **A macro or a word of C's own.** A macro rewrites every later use of its
   name, whatever that names, members included.

Everything else is harmless: siblings, cousins, and a shadow of something the
block never mentions. A parameter `A` beside a global `A` the function doesn't
use is legal C (it draws `-Wshadow`, which the Julia's own shadow earned). A
local `area` in a function `area` that doesn't call itself is legal and draws
nothing.

Such a pair can come from four places: **Julia names more finely than C**
(modules, methods, type parameters, a `let x = x + 1` whose first value reads
the outer `x`); **our spelling is not one-to-one** (`ω` and `omega`, `φ` and
`ϕ`, `bump!` and `bump`), the dangerous one, since Julia never hid one from the
other and the inner block can mention the outer anywhere; **names the
transpiler invents** (`out`, `result`, the index `i`, temps, working copies,
helpers, macros, include guards); and **C's own vocabulary**, libc's symbols
included even where no header is included, since a function that came out as
`write` would replace libc's for the whole program.

### So names are kept

- **Siblings share.** Two loops each have their `k` and `w`.
- **A shadow the Julia wrote is kept as written.** A parameter `g` beside a
  global `g`; a loop's own `g` with the global read after the loop; a `let a`
  beside an outer `a` its body never mentions. This is safe exactly because
  each variable is declared in the block that holds its uses
  ([block.md](block.md)): the C scope is never wider than the Julia's.
- **A function keeps clear only of what it mentions.** A local spelled like a
  global, function or struct yields only if the block it lives in names that
  thing. A parameter `long_` beside an unrelated function `long_` stays.

### And when one must yield

The one that keeps the name is, in order: the one declared **further out**;
then a **parameter** before a **local** before a **working copy**; then the
one whose Julia name **already is** the C name (`omega` keeps it, `ω` yields,
whichever came first), which gives way only to that exact literal name and
never to something respelled into it; then the first.

The one that yields takes **`_local`** when it is the local version of the
very name it yields to, which says why it differs:

| Julia | C |
|---|---|
| `let x = x + 1.0` | `double x_local = x + 1.0;` |
| `for i in 1:i` | `for (int64_t i_local = 1; i_local <= i; i_local++)` |
| an array parameter `x` the function reassigns | its working copy, `x_local` |

and a plain **`_`** where there is no such story: `long_`, `omega_` beside
`omega`, `out_` beside the author's `out`. A temp computed from `x_local` is
still named after `x`: the suffix is ours, not the author's.

Names the transpiler invents rank below all of these, and keep clear of every
name in the function and every file-scope name the function mentions: an
index `i` beside a global `i` the loop reads is `i_`.

### How it is known

The function is walked twice ([block.md](block.md)). On the first walk every
variable is given a name that can't be mistaken for anything, `v5__omega`, so
the text that walk produces shows, block by block, which variables and which
outer names are mentioned, exactly as C will see them: comments and strings
aside, an inlined expression counted where it is written, a loop's header
counted as part of its loop (which is what makes `for i in 1:i` yield).
`names!` then names every variable, outermost first, and the second walk
writes the C.

### File scope

A function or a global gets its C name in one place, `claim!`, which keeps it
clear of every other kind: names already claimed, struct and tuple typedefs,
helpers, foreign wrappers, C's own words.

Names are claimed as things are met while the C is being written, which is
first come, first served, and would make a name depend on the order targets
were listed. So `audit` looks afterwards at what each thing asked for and
got. Of two things with different Julia names asking for one C name, the one
spelled that way in the Julia keeps it; if that isn't how it came out, it is
settled so and **the program is built again**. When neither is spelled that
way (`φ` and `ϕ`, both `phi`), there is no rule to choose by, and a silent `_`
on one of two interface names is not a choice to make for the author: it is
refused, naming both. A macro of ours gives way to a name of the author's:
beside a global `LEGIBLEC_PI`, π is `LEGIBLEC_PI_`. An include guard, being a
macro, is checked against every word of the program.

**Helper names are reserved by their shape.** A function of the author's
called `add_3` or `mul_3x3_3x3` is renamed, `add_3_`, whether or not the
program emits that helper. Its name can't depend on what else the program
computes (it used to be accepted until the day the helper was needed, and
then refused), and `mul_3x3_3x3` is the transpiler's word with a fixed
meaning, as `sqrt` is libc's, so a reader never meets an impostor. The family
is every size and type of every operation, so `ishelpername` recognizes it by
shape, from the stems real helpers use and the pointwise `P`; `step_2` and
`rk_4` stay the author's. The tests insist that every helper they meet is
recognized, so a new operation can't be forgotten.

A generated helper's own internals (`a`, `b`, `out`, `i`) are checked against
nothing at file scope. A helper is closed text that mentions only its own
parameters, other helpers and the standard library, all names the transpiler
chose; and its header is included first, so the compiler never even sees a
shadow. The day a helper can call a function of the author's (broadcasting
one), that one name has to be checked against the helper's vocabulary.

### What is out of sight

Two things can't be settled from inside one `transpile` call. **Link time**: a
function meeting another library's symbol of the same name, or two separately
generated outputs linked together, our own out-of-line helpers included
(`solve_4x4_4` twice); Julia's modules kept them apart and C has one external
name space. **The platform**: a compiler's predefined macros, or a header the
author's own C includes before ours. A strict `-std=c11` removes most of the
first. C's vocabulary can't be listed to the end, so the reserved list is a
fence kept up by adding to it, not a wall.

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
trailing parameter. When every exit of the function returns the same
variable of the author's — `return a`, or `a = …` as the last line, which
returns the same thing — that parameter *is* the variable: `void f(…,
double a[restrict 3])`, and `a` is built there from the start, with no
copy at the end. Otherwise the parameter is called `out`, as an output
parameter in C is — `out_` if the Julia already uses `out` — which is
also the name every generated helper uses for its output, so `add_2x2(A,
B, out)` and `void add(…, double out[2][2])` read alike. Functions whose
exits return different things, or an expression, keep `out`. `out` was
deliberately not used for a returned scalar, where it would suggest a
parameter that isn't there.

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

`identifier` in `src/name.jl` spells one name. `names!` in `src/flow.jl` names
a function's variables by scope; `claim!` in `src/c.jl` and `audit` in
`src/transpile.jl` settle the file-scope names; `ishelpername` in
`src/helper.jl` is the shape of a helper's name. `temp!` in `src/c.jl` applies
the temp rules and `contribution` decides what a value passes along; `Scope`
holds the per-function state (counter, blocked numbers, and what each SSA
value is called in C).
