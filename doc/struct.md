# Struct

Structs and tuples. The C for both is a `typedef struct`, emitted once per
type ahead of everything else, with the fields declared by the same rules as
any variable (`double x;`, `double pos[3];`, a nested struct by value).

## Structs

An immutable `struct` is passed and returned **by value**, which is Julia's
semantics for it. `Point(x, y)` is `(Point){x, y}`; `p.x` is `p.x`;
`p == q` compares field by field; a struct with an array field is built field
by field, the array copied in, since C can't initialize an array member from
another array in a compound literal.

A `mutable struct` is a reference in Julia — two variables can hold the same
one — so in C it is always handled **through a pointer**: `Counter *c`,
`c->n`, and a function that returns the object it was given returns the
pointer. Creating a mutable struct inside transpiled code would need an
allocation and an ownership rule, so it's refused; the C caller owns those.

A parametric struct at a concrete instantiation is one C struct per
instantiation, named like a function at several signatures: `Pair2_F64`,
`Body_3`. Field and type names go through the usual conversion
(`naming.md`), which also drops the `!` from `bump!`.

Not yet: `@kwdef` constructors, structs holding mutable structs, `Union`
fields, `sizeof`.

## Tuples

A `Tuple{Float64, Int64}` — a multiple return value, a tuple stored in a
variable, an `NTuple` argument — is a struct `Tuple_F64_I64` with fields
`a`, `b`, `c`, … named like helper inputs (a matrix element is `A`). It's
returned by value; `x, y = f(v)` reads `x = temp.a; y = temp.b;` (Julia's
`indexed_iterate` machinery collapses to that); `t[2]` is `t.b`. A tuple that
only feeds a constructor or block construction — `SVector(a, b, c)`,
`[A B; C D]` — never exists in C, as before.
