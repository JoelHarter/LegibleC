# Target

What `transpile` accepts as a target.

`transpile` takes any number of targets, and one call makes one file.

| target | meaning |
|---|---|
| `energy` | a function with exactly one method, all argument types concrete |
| `(f, Float64, 3, Float64, 2, 3)` | `f` at these argument types; a type followed by integers is an array of that element type and size, static or a sized `Array` |
| `transpile(f, Float64, Float64)` | the same for a single function, without the tuple |
| `(poly, Int64, Int64)`, `(poly, Float64, Float64)` | the same function at two signatures; the C names get the types appended, `poly_I64_I64`, `poly_F64_F64` |
| a `Core.MethodInstance` | a specialization you already have |
| `Point`, `Point{Float64}` | a struct type: its `typedef`, with the docstring as a Doxygen block; concrete parameters only. List it before any function, since a type right after a function reads as that function's argument type |
| `transpile(fall; g, μ)` | variables, by keyword: `const double g = 9.81;` — see below |
| `:width => width`, `GlobalRef(P, :k)` | a variable whose name is an option's, or one in another module |

Anything a target calls is transpiled too, and anything *that* calls, so
listing the entry points is enough. The same goes for globals: a function
that reads `g` brings `g` into the file as a C global, referenced by name.

## Variables

A global the transpiler meets — read by a function, or listed by keyword —
becomes a declaration with its value near the top of the functions file:
`const double g = 9.81;`, `const double w[3] = {1.0, 2.0, 3.0};`,
`const char *title = "LegibleC";`, a struct as `{…}`. It is `const` when the
Julia binding is, and a plain global when the Julia is `k::Float64 = 2.0`.
A global read by a function must be `const` or typed, since an untyped
mutable global has no type Julia can compile against; the transpiler says
so if it meets one. A constant defined in a module keeps the comment on
its definition line — `const c = 299_792_458.0  # speed of light, m/s`
gives `static const double CODATA_c = 2.99792458e8;  // speed of light,
m/s` in the header, where every file that includes it can fold it — and
only the constants a function reads come out, however many the module
defines. A mutable global is defined in the `.c` and `extern` in the header.

Listing a variable by keyword, `transpile(fall; g)`, or `; g, μ` for
several, adds it whether or not anything reads it, so a constant can sit in
the file for the C side to use. The keyword's name is looked up in `scope`
to decide `const`; a value with no binding there is a constant. The macro
form sets `scope` to wherever it is written:

```julia
@transpile(fall, Point; g, μ, outfile="body")
```

which is the one to use from inside a module. A variable named like an
option (`width`, `source`, …) goes as a pair, `:width => width`.

## Where definitions come from

Anywhere Julia can see them. A function typed at the REPL transpiles like
one from a file; what it lacks is source to carry over, so it gets a bare
Doxygen block and no `// @file.jl:12:` lines. Regenerating the C later needs
the Julia in a file, which is where it belongs anyway. One call generates everything: the
targets share one set of names, one `helper.h`, one copy of each callee.
List every function you want in a single call; a later call writes its own
files into `out/` over the earlier ones.
