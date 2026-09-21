# Linear algebra helpers: one C function per (operation, argument types), generated on
# demand while a function is being emitted and written out once, ahead of everything
# that calls them.
#
# Arrays in C are fixed-size and row-major, passed as array parameters so the compiler
# knows their shape (`const double a[2][2]`), and every helper writes its output into
# its last parameter — except the ones whose result is a scalar, which return it.
#
# Every generator here is written once for the general case. An operand has only the
# dimensions it has — a vector one, a row vector one, a scalar none — and each lines up
# with an axis (`axis`); its size along any axis is `extent`, 1 where it has no
# dimension there. From those two, `access` produces the right C subscript for any
# operand, with `0` for a dimension of extent 1, and loops run only over extents
# greater than 1. So one `contraction` covers every kind of `*`, one broadcast body
# covers every combination of shapes, and one block-placement loop covers every block.

"""
    helper!(helpers, op, types, R) -> name

Make sure the helper for `op` on argument `types`, producing `R`, is in `helpers`,
and return its C name. `op` is one of `:add`, `:sub`, `:neg`, `:mul`, `:copy`.
"""
function helper!(helpers::Dict{String, String}, op::Symbol, types, R::Type)
    name = helpername(op, types)
    haskey(helpers, name) || (helpers[name] = helpercode(name, op, types, R))
    return name
end

"""
    ishelpername(name) -> Bool

Could `name` be a helper's? The family is every size and type of every operation, so it
is recognized by shape, not listed: an operation stem, then descriptors joined by `_` —
`mul_3x3_3x3`, `add_2x2F32`, `solve_4x4_4`, `mulP_3F64_sI64`, `cross_F32`. Such a name is
the transpiler's vocabulary, as `sqrt` is libc's, whether or not this program happens to
emit it: a function of the author's under one is renamed, so that its name never depends
on what else the program computes, and a reader never meets an impostor. Without the
pointwise `P` the stem has to be a real operation, so `step_2` and `rk_4` stay the
author's. `writehelpers` checks every real helper against this, so it can't fall behind.
"""
function ishelpername(name::AbstractString)
    typ = "(?:" * join((a for (_, _, a) in scalars), "|") * "|S)"
    occursin(Regex("^(?:" * join(fixedhelpers, "|") * ")$typ*\$"), name) && return true      # `powi`, `moduloF32`
    desc = "(?:C?[TH]?\\d+(?:x\\d+)*$typ*|C?s$typ*|$typ+)"
    m = match(Regex("^([A-Za-z][A-Za-z0-9]*?)(P?)((?:_$desc)+)\$"), name)
    m === nothing && return false
    return m[2] == "P" || replace(m[1], r"\d+$" => "") in helperstems || m[1] in helperstems
end

# The operations that have helpers, as their names begin — what the suite, the demos and
# the library generator actually produce, no more: a stem listed on a guess would rename
# an author's function for nothing (`zero_3` and `identity_2x2` are not helpers; zeroing
# and the identity are written inline). Pointwise helpers need no entry, the `P` says it.
# The tests insist every helper they meet is recognized, so a new one can't be forgotten.
const helperstems = Set(["add", "sub", "mul", "div", "neg", "dot", "cross", "det", "inv", "invLLT", "pinv", "solve", "rsolve", "solveLLT",
                         "lu", "llt", "pivot", "tr", "norm", "norm1", "normInf", "mean", "var", "std", "sum", "prod", "minimum", "maximum", "extrema", "diff", "cumsum", "cumprod",
                         "addI", "subI", "rsubI", "all", "any", "count", "argmax", "argmin", "printarray"])
const unrecognized = Set{String}()      # helpers met that `ishelpername` didn't know: for the tests
# The few helpers with a name of their own, which a type may follow: `powi`, `moduloF32`.
const fixedhelpers = Set(["cross", "powi", "modulo", "utf8len", "abs2", "printarray", "gcd", "lcm", "isqrt", "sind", "cosd", "tand", "ulp"])

"""
    helpername(op, types; pointwise=false) -> String

The C name of the helper for `op` on `types`. The name says exactly what the
operation's contract leaves open. Each input is described by its shape — `2x2`, `3`,
`T2x3` transposed, `s` for a scalar — then its type when not every input is `Float64`
(`2x2F32`, `sF32`). An operation that leaves the shapes open lists every input:
`mul_2x2_2x3`, `mul_s_2x2`, and every pointwise one, with `P` after the operation:
`mulP_3_3x2`, `addP_3_3`. One whose contract fixes the shapes as identical writes the
shape once and then the types run together, one if they agree: `add_2x2`,
`add_2x2F32`, `add_2x2F32F64`, `dot_3`; `cross`, whose shapes are fixed entirely, has
only the types: `cross`, `cross_F32`. Full rules in `doc/helper.md`.
"""
function helpername(op::Symbol, types; pointwise::Bool=false)
    # Complex is a `C` in front, like the `T` of a transpose — `C3`, `CH3x2`, `Cs` — and
    # counts as double for the rule that leaves double unmarked; its precision, when it
    # isn't double, is marked as a real's is.
    fundamental(T) = T <: AbstractArray ? eltype(T) : T
    precision(E) = E <: Complex ? real(E) : E
    alldouble = all(T -> precision(fundamental(T)) === Float64, types)
    sizes = [T <: AbstractArray ? dims(T) : fundamental(T) <: Complex ? "Cs" : "s" for T in types]
    typs = [abbrev(precision(fundamental(T))) for T in types]
    if !pointwise && op in (:add, :sub, :dot, :cross) && allequal(sizes)
        # The contract fixes the shapes (a transposed operand still lists in full, since
        # the storage differs): one shape, then the types.
        t = alldouble ? "" : allequal(typs) ? typs[1] : join(typs)
        body = (op == :cross ? "" : sizes[1]) * t
        return isempty(body) ? string(op) : string(op, "_", body)
    end
    descs = [alldouble ? sz : sz * t for (sz, t) in zip(sizes, typs)]
    return string(op, pointwise ? "P_" : "_", join(descs, "_"))
end

# The C definition of one helper. The elementwise ones walk the output in storage
# order with plain subscripts when every array involved lines up with the axes the
# same way (the usual case, and the contiguous one); when one is transposed relative
# to the others — `A + B'` — they walk the output's axes and let `access` place each
# subscript.
# Whether an input is laid out exactly like the output — the same storage, the same
# axes — so that a caller may pass the same array as both, `add_3(v, w, v)`. Then the
# output cannot be declared `restrict`; an elementwise helper is safe in place, since
# each element it writes it has already read. Any other input can't be the output.
alike(T::Type, R::Type) = isarray(T) && axis(T) == axis(R) && shape(T) == shape(R) && eltype(T) == eltype(R)

function helpercode(name::AbstractString, op::Symbol, types, R::Type)
    names = inputs(types)
    params = [declare(T, n; constant=true) for (T, n) in zip(types, names)]
    push!(params, declare(R, "out"; restrict=!any(T -> alike(T, R), types)))
    aligned = all(T -> !(T <: AbstractArray) || axis(T) == axis(R), types)
    sub(T, var, idx) = aligned ? (T <: AbstractArray ? var * brackets(idx) : var) : access(T, var, idx)
    walk(line) = elementwise(aligned ? shape(R) : extents(R), idx -> "$(sub(R, "out", idx)) = $(line(idx));"; taken=names)
    body = if op in (:add, :sub)
        a, b = types
        extents(a) == extents(b) || throw(ArgumentError("$op: dimensions don't match, $(dims(a)) and $(dims(b))"))
        walk(idx -> "$(sub(a, names[1], idx)) $(op == :add ? "+" : "-") $(sub(b, names[2], idx))")
    elseif op == :neg
        walk(idx -> "-" * sub(types[1], names[1], idx))
    elseif op == :mul && !all(T -> T <: AbstractArray, types)
        # A scalar times an array: elementwise, whichever side the scalar is on.
        a, b = types
        walk(idx -> "$(sub(a, names[1], idx)) * $(sub(b, names[2], idx))")
    elseif op == :div
        # An array over a scalar: elementwise. Julia's `/` is always floating, so two
        # integers get a cast, as in the scalar case.
        a, b = types
        cast = eltype(a) <: Integer && b <: Integer ? "($(ctype(eltype(R))))" : ""
        walk(idx -> "$cast$(sub(a, names[1], idx)) / $(sub(b, names[2], idx))")
    elseif op == :mul
        contraction(types..., names..., R, eltype(R))
    else
        throw(ArgumentError("unsupported array operation: $op"))
    end
    spelled = [istransposed(T) ? n * tmark(T) : n for (T, n) in zip(types, names)]
    formula = op in (:add, :sub) ? "out = $(spelled[1]) $(op == :add ? "+" : "-") $(spelled[2])" :
              op == :neg ? "out = -$(spelled[1])" :
              op == :div ? "out = $(spelled[1]) / $(spelled[2])" :
              "out = $(spelled[1]) * $(spelled[2])"
    return definition("void", name, params, body; doc=[prose(op, types, R), formula])
end

# ---- the primitives every generator is built from ----------------------------------

# A helper's full C definition, with its comment above it: a one-line brief (see
# prose.jl), or that plus `@param` lines for the parameters whose meaning isn't in
# their name. `body` lines are relative to the function's own indent. A helper is
# `static inline` when it's straight-line code or plain loops — the small things a C
# programmer marks inline — and plain `static` when it calls other helpers, searches,
# or can abort: the solvers and factorizations, which nobody wants copied into every
# caller.
# A helper's text. A small one is `static inline`, and lives in `helper.h` so every file
# that includes it has the body; a large one (a solver, a factorization) is an ordinary
# function in `helper.c`, with its prototype in the header.
definition(ret, name, params, body; doc::Union{AbstractString, Vector{String}}="", inline::Bool=true) =
    join("/// " .* (doc isa AbstractString ? (isempty(doc) ? String[] : [doc]) : doc), "\n") * (isempty(doc) ? "" : "\n") *
    "$(inline ? "static inline " : "")$ret $name($(join(params, ", "))) {\n" * join("    " .* body, "\n") * "\n}\n"

# Is this helper's text a `static inline` one (for the header) or an ordinary function?
isinline(text) = occursin(r"^static inline ", text) || occursin("\nstatic inline ", text)

# The prototype of a helper, from its definition: the signature line, ended with `;`.
prototype(text) = (m = match(r"^(?:static inline )?([^\n]*) \{$"m, text); m === nothing ? "" : m[1] * ";")

# The (index name, extent) pairs that need a loop: those with more than one element.
live(pairs) = [p for p in pairs if p[2] > 1]

# Helper parameter names. The inputs march up the alphabet — `a`, `b`, `c`, … and, should
# there ever be more than 26, `aa`, `ab`, … like spreadsheet columns — capitalized for a
# matrix or higher-dimensional array and lowercase for a vector or scalar, so
# `mul(A, b, out)` reads like the mathematics. The output is always `out`.
function inputs(types)
    function letters(k)
        s = ""
        while k > 0
            k -= 1
            s = Char('a' + k % 26) * s
            k ÷= 26
        end
        return s
    end
    return [T <: AbstractArray && ndims(T) >= 2 ? uppercase(letters(k)) : letters(k) for (k, T) in enumerate(types)]
end

# Loop index names: `i`, `j`, `k` for up to three nested loops; past three, `i1`,
# `i2`, `i3`, … throughout, so a reader never has to wonder what comes after `k`. One
# that would collide with a parameter (the ninth input is `i`) gets `_` appended until
# it doesn't.
function indices(n::Integer; taken=())
    names = n <= 3 ? ["i", "j", "k"][1:n] : ["i$d" for d in 1:n]
    return [free(s, taken) for s in names]
end

# `s`, with `_` appended until it isn't in `taken`.
function free(s::AbstractString, taken)
    while s in taken
        s *= "_"
    end
    return s
end

# Nested `for` loops, one per (index name, extent) pair in nesting order, around
# `inner`. Lines come out relative to the outermost loop, so nests can be nested.
# Callers leave out extent-1 dimensions (and index them with `0`).
function nest(pairs, inner::Vector{String}; indent="    ")
    lines = String[]
    for (d, (name, n)) in enumerate(pairs)
        push!(lines, indent^(d - 1) * "for (int $name = 0; $name < $n; $name++) {")
    end
    append!(lines, indent^length(pairs) .* inner)
    for d in length(pairs):-1:1
        push!(lines, indent^(d - 1) * "}")
    end
    return lines
end

# Index expressions for looping over `shape`: a fresh index name for each dimension
# with more than one element, `0` for the rest — and the loops to go with them.
function loopindices(shape; taken=())
    looped = [d for d in eachindex(shape) if shape[d] > 1]
    names = indices(length(looped); taken)
    idx = [shape[d] > 1 ? names[findfirst(==(d), looped)] : "0" for d in eachindex(shape)]
    return idx, [(names[p], shape[d]) for (p, d) in enumerate(looped)]
end

# Nested loops over every element of `shape`, with `line(idx)` innermost, where `idx`
# is one index expression per dimension.
function elementwise(shape, line::Function; taken=(), indent="    ")
    idx, pairs = loopindices(shape; taken)
    return nest(pairs, [line(idx)]; indent)
end

brackets(idx) = join("[$x]" for x in idx)

# The C subscript for `var` of type `T` at `idx` (one index expression per axis): one
# subscript per dimension `T` actually has, taken from the axis it lines up with, and
# `0` wherever that dimension's extent is 1. A scalar gets no subscript at all.
# An adjoint operand's element is read conjugated: that is what `Adjointed` means.
function access(T::Type, var::AbstractString, idx)
    s = var * join("[" * (extent(T, d) == 1 ? "0" : idx[d]) * "]" for d in axis(T))
    return isconjugated(T) ? "$(mathname(eltype(T), "conj"))($s)" : s
end

# ---- multiplication ---------------------------------------------------------------

# The one body for every `*` of two arrays: `out(i,j) = Σ_k a(i,k) b(k,j)`, where an
# operand's extent is 1 along any axis it has no dimension on. That is matrix×matrix, matrix×vector, row×matrix,
# column×row (the outer product), and row×column (a scalar, returned when `R` is
# nothing) with no special cases — only the loops that have anything to loop over.
# Loop order is i-k-j: the inner loop walks a row of `out` and a row of `b`, both
# contiguous in row-major storage.
function contraction(a::Type, b::Type, an, bn, R, E::Type)
    m, K = extent(a, 1), extent(a, 2)
    K2, n = extent(b, 1), extent(b, 2)
    K == K2 || throw(ArgumentError("mul: dimensions don't match, $(dims(a)) and $(dims(b))"))
    zero = E === Float32 ? "0.0f" : E <: AbstractFloat ? "0.0" : "0"
    ii, jj, kk = indices(3; taken=(an, bn))
    i, j, k = m > 1 ? ii : "0", n > 1 ? jj : "0", K > 1 ? kk : "0"
    term = "$(access(a, an, [i, k])) * $(access(b, bn, [k, j]))"
    if R === nothing
        return ["$(ctype(E)) sum = $zero;"; nest(live([(kk, K)]), ["sum += $term;"]); "return sum;"]
    end
    out = access(R, "out", [i, j])
    K == 1 && return nest(live([(ii, m), (jj, n)]), ["$out = $term;"])
    # One output index (a matrix times a vector): accumulate in a local, as a person
    # writes it. With two, the loops run i, k, j so the inner loop walks a row of `b`
    # (see decision.md), and each output element is zeroed then accumulated.
    n == 1 && return nest(live([(ii, m)]), ["$(ctype(E)) sum = $zero;"; nest(live([(kk, K)]), ["sum += $term;"]); "$out = sum;"])
    return nest(live([(ii, m)]), [nest(live([(jj, n)]), ["$out = $zero;"]);
                                   nest(live([(kk, K), (jj, n)]), ["$out += $term;"])])
end

# The type of the result of `op` on `types`, with element type `E`. Nothing for a
# scalar (a row times a column). The kind of array follows Julia: a row times a
# matrix is a row, a matrix times a vector is a vector, everything else a matrix.
function resulttype(op::Symbol, types, E::Type)
    arrays = [T for T in types if T <: AbstractArray]
    op == :mul && length(arrays) == 2 || return retype(arrays[1], E)
    a, b = types
    m, K = extent(a, 1), extent(a, 2)
    K2, n = extent(b, 1), extent(b, 2)
    K == K2 || throw(ArgumentError("mul: dimensions don't match, $(dims(a)) and $(dims(b))"))
    isrow(a) && !isrow(b) && ndims(b) == 1 && return nothing
    isrow(a) && return Transposed{E, (n,), 1}
    ndims(a) == 2 && ndims(b) == 1 && !isrow(b) && return shaped(E, (m,))
    return shaped(E, (m, n))
end

# The same array type with element type `E`.
retype(T::Type, E::Type) = istransposed(T) ? Transposed{E, shape(T), ndims(T)} : shaped(E, shape(T))

# A helper that returns a scalar: `dot_3`, or `mul_T3_3` for a row times a column.
# Both are the contraction of two single dimensions, the first on axis 2, the second
# on axis 1.
function scalarhelper!(helpers::Dict{String, String}, op::Symbol, types, E::Type)
    name = helpername(op, types)
    if !haskey(helpers, name)
        a, b = types
        an, bn = inputs(types)
        # `dot` conjugates its first argument: on complex elements that is an adjoint row.
        row = op == :dot && eltype(a) <: Complex ? Adjointed{eltype(a), shape(a), 1} : isrow(a) ? a : Transposed{eltype(a), shape(a), 1}
        body = contraction(row, b, an, bn, nothing, E)
        helpers[name] = definition(ctype(E), name, [declare(a, an; constant=true), declare(b, bn; constant=true)], body;
                                   doc=[prose(op, types), op == :dot ? "returns $an ⋅ $bn" : "returns $(an)$(tmark(a)) * $bn"])
    end
    return name
end

# `a^n` for a literal `n` as one C expression, the way `render` writes a scalar power:
# squares, cubes and the reciprocal written out, anything else through `powi`.
function powexpr(helpers, a::AbstractString, n::Integer, E::Type)
    one = E <: Union{AbstractFloat, Complex} ? (E === Float32 ? "1.0f" : "1.0") : "1"
    n == 0 && return one
    n == 1 && return a
    n == 2 && return "$a * $a"
    n == 3 && return "$a * $a * $a"
    n == -1 && return "$one / $a"
    return "$(powhelper!(helpers, E))($a, $n)"
end

# `x^n` for an integer `n`, by squaring: `powi(x, 13)`, one helper per base type
# (`powiF32`, `powiI64` off the double). The exponent is a literal at every call, so
# an optimizing compiler inlines this, unrolls the loop over its bits and folds the
# `1.0` start away, leaving exactly the multiply chain a person would write out —
# five multiplies for the 13th power — with no loop and no branch. A negative exponent
# is the reciprocal at the end; for an integer base Julia throws, so it isn't offered.
# Julia's own `Float64^Int` is a compensated squaring, a little more accurate and
# about three times the work; speed wins here.
function powhelper!(helpers::Dict{String, String}, E::Type)
    name = "powi" * (E === Float64 ? "" : abbrev(E))
    haskey(helpers, name) && return name
    t = ctype(E)
    one = E <: Union{AbstractFloat, Complex} ? (E === Float32 ? "1.0f" : "1.0") : "1"
    signed = E <: AbstractFloat
    body = [signed ? ["bool neg = n < 0;", "if (neg) {", "    n = -n;", "}"] : String[];
            "$t r = $one;"; "while (n > 0) {"; "    if (n & 1) {"; "        r *= x;"; "    }"; "    x *= x;"; "    n >>= 1;"; "}";
            "return " * (signed ? "neg ? $one / r : r;" : "r;")]
    helpers[name] = definition(t, name, ["$t x", "int n"], body;
                               doc=["integer power of $(E === Float64 ? "a scalar" : E <: AbstractFloat ? "a float" : "an integer"), by squaring",
                                    "returns x^n"])
    return name
end

# `gcd`, `lcm`, `isqrt` on integers: Julia's answers for every argument Julia answers for.
# Where the answer doesn't fit the type (`gcd(typemin(Int64), 0)`) Julia throws, and such a
# call never reaches C. The work is done on magnitudes as unsigned, so that the one value
# with no negative, the type's minimum, takes no special care.
function integerhelper!(helpers::Dict{String, String}, op::Symbol, E::Type)
    name = string(op) * (E === Int64 ? "" : abbrev(E))
    haskey(helpers, name) && return name
    t, u = ctype(E), ctype(unsigned(E))
    magnitude(x) = E <: Signed ? "$x < 0 ? -($u)$x : ($u)$x" : x
    if op === :gcd
        helpers[name] = definition(t, name, ["$t a", "$t b"],
            ["$u x = $(magnitude("a"));", "$u y = $(magnitude("b"));", "while (y != 0) {", "    $u r = x % y;", "    x = y;", "    y = r;", "}", "return ($t)x;"];
            doc=["greatest common divisor, by Euclid's algorithm; never negative", "returns gcd(a, b)"])
    elseif op === :lcm
        g = integerhelper!(helpers, :gcd, E)
        helpers[name] = definition(t, name, ["$t a", "$t b"],
            ["if (a == 0 || b == 0) {", "    return 0;", "}", "$t m = a * (b / $g(a, b));", "return " * (E <: Signed ? "m < 0 ? -m : m;" : "m;")];
            doc=["least common multiple; never negative", "returns lcm(a, b)"])
    else
        # In 64 bits whatever the type, so that `s * s` can't wrap; and `s` is held to 2^32 - 1,
        # the largest root there is, since `(double)n` rounds the largest values up to 2^64.
        helpers[name] = definition(t, name, ["$t n"],
            ["uint64_t s = (uint64_t)sqrt((double)n);", "if (s > 4294967295u) {", "    s = 4294967295u;", "}",
             "while (s * s > (uint64_t)n) {", "    s--;", "}", "while (s < 4294967295u && (s + 1) * (s + 1) <= (uint64_t)n) {", "    s++;", "}", "return ($t)s;"];
            doc=["integer square root: the floating one, then corrected, since a double holds 53 bits", "returns the largest s with s * s <= n"])
    end
    return name
end

# `eps(x)`: the distance from `|x|` to the next float up, which is the type's epsilon scaled
# by `x`'s exponent. Below the normal range it is the smallest float there is, and at the
# largest float it is still finite, which is why it is not `nextafter(x, INFINITY) - x`.
function ulphelper!(helpers::Dict{String, String}, E::Type)
    name = "ulp" * (E === Float64 ? "" : abbrev(E))
    haskey(helpers, name) && return name
    t, f, P = ctype(E), E === Float32 ? "f" : "", E === Float32 ? "FLT" : "DBL"
    body = ["$t a = fabs$f(x);", "if (!isfinite(a)) {", "    return NAN;", "}",
            "return a >= $(P)_MIN ? ldexp$f($(P)_EPSILON, ilogb$f(a)) : nextafter$f($(E === Float32 ? "0.0f, 1.0f" : "0.0, 1.0"));"]
    helpers[name] = definition(t, name, ["$t x"], body; doc=["distance from |x| to the next larger $(E === Float32 ? "float" : "double"), as Julia's eps(x)", "returns eps(x)"])
    return name
end

# `sind`, `cosd`, `tand`: the angle is brought into one turn and then into the octant where
# the sine or the cosine of a small angle gives the answer, as Julia does it, and for Julia's
# reason: the multiples of 90 come out exact, `sind(180.0) == 0.0`, where `sin(x * π / 180)`
# gives 1.2e-16. `fmod` keeps the sign of the angle, as Julia's `rem` does.
function degreehelper!(helpers::Dict{String, String}, op::Symbol)
    name = string(op)
    haskey(helpers, name) && return name
    k = "(" * macroname(π) * " / 180)"
    if op === :sind
        body = ["double r = fmod(x, 360.0);", "double a = fabs(r);",
                "if (r == 0.0) {", "    return r;", "}",
                "if (a < 45.0) {", "    return sin(r * $k);", "}",
                "if (a <= 135.0) {", "    return copysign(cos((90.0 - a) * $k), r);", "}",
                "if (a == 180.0) {", "    return copysign(0.0, r);", "}",
                "if (a < 225.0) {", "    return sin((r < 0.0 ? a - 180.0 : 180.0 - a) * $k);", "}",
                "if (a <= 315.0) {", "    return -copysign(cos((270.0 - a) * $k), r);", "}",
                "return sin((r - copysign(360.0, r)) * $k);"]
        doc = ["sine of an angle in degrees, exact at the multiples of 90", "returns sind(x)"]
    elseif op === :cosd
        # The zeros are said outright: under `-ffast-math` a compiler may turn `(90.0 - a) * k`
        # into `90.0 * k - a * k`, which is 3e-17 at `a == 90.0` and not zero.
        body = ["double a = fabs(fmod(x, 360.0));",
                "if (a == 90.0 || a == 270.0) {", "    return 0.0;", "}",
                "if (a <= 45.0) {", "    return cos(a * $k);", "}",
                "if (a < 135.0) {", "    return sin((90.0 - a) * $k);", "}",
                "if (a <= 225.0) {", "    return -cos((180.0 - a) * $k);", "}",
                "if (a < 315.0) {", "    return sin((a - 270.0) * $k);", "}",
                "return cos((360.0 - a) * $k);"]
        doc = ["cosine of an angle in degrees, exact at the multiples of 90", "returns cosd(x)"]
    else
        body = ["return $(degreehelper!(helpers, :sind))(x) / $(degreehelper!(helpers, :cosd))(x);"]
        doc = ["tangent of an angle in degrees", "returns tand(x)"]
    end
    helpers[name] = definition("double", name, ["double x"], body; doc)
    return name
end

# `abs2(z)` of a complex number: the squared magnitude without the square root of `cabs`.
function abs2helper!(helpers::Dict{String, String}, E::Type)
    name = "abs2" * (E === ComplexF32 ? "F32" : "")
    haskey(helpers, name) && return name
    R = real(E)
    re, im = mathname(E, "real"), mathname(E, "imag")
    helpers[name] = definition(ctype(R), name, ["$(ctype(E)) z"], ["return $re(z) * $re(z) + $im(z) * $im(z);"];
                               doc=["squared magnitude of a complex number", "returns |z|²"])
    return name
end

# Julia's `mod` on floats: the remainder with the divisor's sign, where C's `fmod` gives
# the dividend's. `modulo(x, y)`, `moduloF32` for floats — Julia's definition, in C.
function modhelper!(helpers::Dict{String, String}, E::Type)
    name = "modulo" * (E === Float64 ? "" : abbrev(E))
    haskey(helpers, name) && return name
    t = ctype(E)
    f = E === Float32 ? "f" : ""
    zero = E === Float32 ? "0.0f" : "0.0"
    body = ["$t r = fmod$f(x, y);",
            "if (r == $zero) {", "    return copysign$f(r, y);", "}",
            "return (r > $zero) != (y > $zero) ? r + y : r;"]
    helpers[name] = definition(t, name, ["$t x", "$t y"], body; doc=["remainder with the divisor's sign, as Julia's mod", "returns mod(x, y)"])
    return name
end

# `length(s)` of a UTF-8 string: the characters, not the bytes — every byte that isn't a
# continuation byte starts one. `ncodeunits` is `strlen`; this is the other count.
function lengthhelper!(helpers::Dict{String, String})
    name = "utf8len"
    haskey(helpers, name) && return name
    body = ["int64_t n = 0;", "for (; *s; s++) {", "    if ((*s & 0xC0) != 0x80) {", "        n++;", "    }", "}", "return n;"]
    helpers[name] = definition("int64_t", name, ["const char *s"], body; doc=["number of characters in a UTF-8 string", "returns length(s)"])
    return name
end

# ---- the rest ----------------------------------------------------------------------

# The determinant of a square matrix of type `T`, returned as `E`: `det_3x3`. Sizes 1–3
# are written out, the way a person writes them. From 4 on it's cofactor expansion along
# the first row: each minor is cut into `M` and handed to the next size down, so
# `det_5x5` calls `det_4x4` calls `det_3x3`.
function dethelper!(helpers::Dict{String, String}, T::Type, E::Type)
    ndims(T) == 2 && allequal(shape(T)) || throw(ArgumentError("det needs a square matrix, got a $(describe(T))"))
    name = helpername(:det, (T,))
    haskey(helpers, name) && return name
    n = shape(T)[1]
    A = inputs((T,))[1]
    a(i, j) = access(T, A, [string(i), string(j)])
    body = if n == 1
        ["return $(a(0, 0));"]
    elseif n == 2
        ["return $(a(0, 0)) * $(a(1, 1)) - $(a(0, 1)) * $(a(1, 0));"]
    elseif n == 3
        ["return $(a(0, 0)) * ($(a(1, 1)) * $(a(2, 2)) - $(a(1, 2)) * $(a(2, 1)))",
         "     - $(a(0, 1)) * ($(a(1, 0)) * $(a(2, 2)) - $(a(1, 2)) * $(a(2, 0)))",
         "     + $(a(0, 2)) * ($(a(1, 0)) * $(a(2, 1)) - $(a(1, 1)) * $(a(2, 0)));"]
    else
        S = shaped(E, (n - 1, n - 1))
        one, zero = E <: Union{AbstractFloat, Complex} ? (E === Float32 ? ("1.0f", "0.0f") : ("1.0", "0.0")) : ("1", "0")
        cut = nest([("i", n - 1), ("k", n - 1)], ["M[i][k] = $(access(T, A, ["i + 1", "k < j ? k : k + 1"]));"])
        loop = nest([("j", n)], [cut; "det += sign * $(access(T, A, ["0", "j"])) * $(dethelper!(helpers, S, E))(M);"; "sign = -sign;"])
        ["$(ctype(E)) det = $zero;"; "$(ctype(E)) sign = $one;"; declare(S, "M") * ";"; loop; "return det;"]
    end
    helpers[name] = definition(ctype(E), name, [declare(T, A; constant=true)], body; doc=["$(describe(T)) determinant", "returns det($(istransposed(T) ? A * "ᵀ" : A))"], inline=n <= 3)
    return name
end

# A reduction of every element of `T` to one value of type `E`: `sum_3`, `maximum_2x2`,
# `norm_3`. One loop in storage order; `maximum`/`minimum` compare, so a NaN is passed
# over where Julia would return it.
function reducehelper!(helpers::Dict{String, String}, op::Symbol, T::Type, E::Type)
    name = helpername(op, (T,))
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    idx, pairs = loopindices(shape(T))
    a = A * brackets(idx)
    first = A * brackets(["0" for _ in shape(T)])
    zero = E <: Union{AbstractFloat, Complex} ? (E === Float32 ? "0.0f" : "0.0") : "0"
    one = E <: Union{AbstractFloat, Complex} ? (E === Float32 ? "1.0f" : "1.0") : "1"
    v = eltype(T) === Bool && booltype[] !== Bool ? "($a != 0)" : a       # an integer as bool: nonzero is true
    body = op == :sum     ? ["$(ctype(E)) sum = $zero;"; nest(pairs, ["sum += $v;"]); "return sum;"] :
           op == :prod    ? ["$(ctype(E)) product = $one;"; nest(pairs, ["product *= $v;"]); "return product;"] :
           op == :maximum ? ["$(ctype(E)) max = $first;"; nest(pairs, ["if ($a > max) {", "    max = $a;", "}"]); "return max;"] :
           op == :minimum ? ["$(ctype(E)) min = $first;"; nest(pairs, ["if ($a < min) {", "    min = $a;", "}"]); "return min;"] :
           op == :any     ? [nest(pairs, ["if ($a) {", "    return true;", "}"]); "return false;"] :
           op == :all     ? [nest(pairs, ["if (!$a) {", "    return false;", "}"]); "return true;"] :
           op == :norm    ? ["$(ctype(E)) sum = $zero;"; nest(pairs, ["sum += $(eltype(T) <: Complex ? "$(mathname(eltype(T), "real"))($a) * $(mathname(eltype(T), "real"))($a) + $(mathname(eltype(T), "imag"))($a) * $(mathname(eltype(T), "imag"))($a)" : "$a * $a");"]); "return $(E === Float32 ? "sqrtf" : "sqrt")(sum);"] :
           op in (:norm1, :normInf) ? (mag = eltype(T) <: Integer ? "fabs((double)$a)" : "$(mathname(eltype(T), "fabs"))($a)";
                                       op == :norm1 ? ["$(ctype(E)) sum = $zero;"; nest(pairs, ["sum += $mag;"]); "return sum;"] :
                                                      ["$(ctype(E)) max = $zero;"; nest(pairs, ["if ($mag > max) {", "    max = $mag;", "}"]); "return max;"]) :
           op == :mean    ? ["$(ctype(E)) sum = $zero;"; nest(pairs, ["sum += $a;"]); "return sum / $(prod(shape(T)));"] :
           op in (:var, :std) ? ["$(ctype(E)) mean = $zero;"; nest(pairs, ["mean += $a;"]); "mean /= $(prod(shape(T)));";
                                 "$(ctype(E)) sum = $zero;"; nest(pairs, ["sum += ($a - mean) * ($a - mean);"]);
                                 op == :var ? "return sum / $(prod(shape(T)) - 1);" : "return $(E === Float32 ? "sqrtf" : "sqrt")(sum / $(prod(shape(T)) - 1));"] :
           op == :count   ? ["int64_t count = 0;"; nest(pairs, ["if ($a) {", "    count++;", "}"]); "return count;"] :
           op == :tr      ? ["$(ctype(E)) sum = $zero;"; "for (int i = 0; i < $(shape(T)[1]); i++) {"; "    sum += $A[i][i];"; "}"; "return sum;"] :
           # `argmax`, `argmin`: Julia's 1-based index of the first extreme element.
           op == :argmax  ? ["int64_t best = 1;"; "$(ctype(eltype(T))) max = $first;"; nest(pairs, ["if ($a > max) {", "    max = $a;", "    best = $(idx[1]) + 1;", "}"]); "return best;"] :
           op == :argmin  ? ["int64_t best = 1;"; "$(ctype(eltype(T))) min = $first;"; nest(pairs, ["if ($a < min) {", "    min = $a;", "    best = $(idx[1]) + 1;", "}"]); "return best;"] :
           op == :extrema ? ["$(ctype(eltype(T))) min = $first;"; "$(ctype(eltype(T))) max = $first;";
                             nest(pairs, ["if ($a < min) {", "    min = $a;", "}", "if ($a > max) {", "    max = $a;", "}"]); "return ($(ctype(E))){min, max};"] :
           throw(ArgumentError("unsupported reduction: $op"))
    helpers[name] = definition(ctype(E), name, [declare(T, A; constant=true)], body; doc=[prose(op, (T,)), "returns $op($A)"])
    return name
end

# An operation along dimension `d` of an array of type `T`, into an array of type `R`:
# `sum1_2x3` (sum along dimension 1 of a 2×3, into a 1×3), `maximum2_2x3`, `diff2_2x3`
# (into a 2×2), `cumsum1_2x3`. The dimension sits on the operation's name, since it says
# how the operation works, not what it is given; a vector has only the one, so `diff_4`
# and `cumsum_4` leave it off — `sum1_4` keeps it, because `sum_4` is the sum to a
# scalar. Loops over the other dimensions outside, the one worked along inside.
function dimhelper!(helpers::Dict{String, String}, op::Symbol, d::Integer, T::Type, R::Type)
    reduction = op in (:sum, :prod, :maximum, :minimum)
    name = helpername(ndims(T) == 1 && !reduction ? op : Symbol(op, d), (T,))
    haskey(helpers, name) && return name
    E = eltype(R)
    t = ctype(E)
    A = inputs((T,))[1]
    s = shape(T)
    names = indices(ndims(T))
    idx = [s[k] > 1 ? names[k] : "0" for k in eachindex(s)]
    outer = [(names[k], s[k]) for k in eachindex(s) if k != d && s[k] > 1]
    inner = s[d] > 1 ? [(names[d], s[d])] : Tuple{String, Int}[]
    a = access(T, A, idx)
    out = access(R, "out", idx)
    one, zero = onezero(E)
    body = if op == :sum || op == :prod
        acc, init, sym = op == :sum ? ("sum", zero, "+=") : ("product", one, "*=")
        nest(outer, ["$t $acc = $init;"; nest(inner, ["$acc $sym $a;"]); "$out = $acc;"])
    elseif op == :maximum || op == :minimum
        acc, cmp = op == :maximum ? ("max", ">") : ("min", "<")
        first = access(T, A, [k == d ? "0" : idx[k] for k in eachindex(s)])
        nest(outer, ["$t $acc = $first;"; nest(inner, ["if ($a $cmp $acc) {", "    $acc = $a;", "}"]); "$out = $acc;"])
    elseif op == :diff
        # Loops over the result's shape; the dimension worked along is one shorter.
        so = shape(R)
        idx = [so[k] > 1 ? names[k] : "0" for k in eachindex(so)]
        next = [k == d ? (idx[k] == "0" ? "1" : idx[k] * " + 1") : idx[k] for k in eachindex(so)]
        nest([(names[k], so[k]) for k in eachindex(so) if so[k] > 1], ["$(access(R, "out", idx)) = $(access(T, A, next)) - $(access(T, A, idx));"])
    else
        acc, init, sym = op == :cumsum ? ("sum", zero, "+=") : ("product", one, "*=")
        nest(outer, ["$t $acc = $init;"; nest(inner, ["$acc $sym $a;", "$out = $acc;"])])
    end
    what = op == :sum ? "sum" : op == :prod ? "product" : op == :maximum ? "maximum" : op == :minimum ? "minimum" :
           op == :diff ? "differences" : op == :cumsum ? "cumulative sum" : "cumulative product"
    typed = eltype(T) !== Float64
    along = ndims(T) == 1 ? "" : " along dimension $d"
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(R, "out")], body;
                               doc=["$(describe(T; typed)) $what$along", "out = $op($A$(ndims(T) == 1 ? "" : "; dims=$d"))"])
    return name
end

# `A + λI`, `A - λI`, `λI - A` for a square matrix: `addI_3x3(A, s, out)`, `subI_3x3`,
# `rsubI_3x3` — the matrix copied (negated, for `rsubI`), then `s` on the diagonal.
function scalinghelper!(helpers::Dict{String, String}, mode::Symbol, T::Type, R::Type)
    name = helpername(mode, (T,))
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    n = shape(T)[1]
    idx, pairs = loopindices(shape(T))
    a = access(T, A, idx)
    copy = nest(pairs, ["out$(brackets(idx)) = $(mode == :rsubI ? "-" : "")$a;"])
    diag = nest(live([("i", n)]), ["out[$(n > 1 ? "i" : "0")][$(n > 1 ? "i" : "0")] $(mode == :subI ? "-=" : "+=") s;"])
    what = mode == :addI ? "plus" : mode == :subI ? "minus" : "subtracted from"
    formula = mode == :addI ? "out = $A + s I" : mode == :subI ? "out = $A - s I" : "out = s I - $A"
    helpers[name] = definition("void", name, [declare(T, A; constant=true), "$(ctype(eltype(R))) s", declare(R, "out")], [copy; diag];
                               doc=["$(describe(T)) $what a multiple of the identity", formula])
    return name
end

# ---- solving and inverting ---------------------------------------------------------
#
# The rule for every algorithm here: sizes 1–3 are written out in full, the way
# StaticArrays writes them (Cramer's rule straight from the determinant, the adjugate
# for the inverse); from 4 on it's a deterministic algorithm that guards against
# singularity — LU with partial pivoting, the pivot chosen by `pivot_NxN`. Everything
# lives on the stack in arrays of the static size: no allocation anywhere.

# The literal one and zero of `E`.
onezero(E::Type) = E <: Union{AbstractFloat, Complex} ? (E === Float32 ? ("1.0f", "0.0f") : ("1.0", "0.0")) : ("1", "0")

# Partial pivoting for column `k` of the LU work array: the row at or below `k` with the
# largest magnitude in that column is swapped into row `k`, in both `LU` and the
# permutation `p`. Shared by `lu_NxN` and anything else that eliminates.
function pivothelper!(helpers::Dict{String, String}, T::Type)
    n = shape(T)[1]
    E = eltype(T)
    name = "pivot_" * dims(T)
    haskey(helpers, name) && return name
    fabs = mathname(E, "fabs")
    body = ["int best = k;",
            "for (int i = k + 1; i < $n; i++) {",
            "    if ($fabs(LU[i][k]) > $fabs(LU[best][k])) {",
            "        best = i;",
            "    }",
            "}",
            "if (best != k) {",
            "    for (int j = 0; j < $n; j++) {",
            "        $(ctype(E)) t = LU[k][j];",
            "        LU[k][j] = LU[best][j];",
            "        LU[best][j] = t;",
            "    }",
            "    int t = p[k];",
            "    p[k] = p[best];",
            "    p[best] = t;",
            "}"]
    helpers[name] = definition("void", name, ["$(ctype(E)) LU[restrict $n][$n]", "int p[restrict $n]", "int k"], body;
                               doc=["partial pivot of a $(describe(T)) at column k",
                                    "@param LU  the work array being decomposed; rows k and best are swapped",
                                    "@param p   the row permutation so far, swapped alongside",
                                    "@param k   the column, 0-based"], inline=false)
    return name
end

# LU decomposition with partial pivoting of `A` into `LU` (L below the diagonal with a
# unit diagonal, U on and above it) and the row permutation `p`. A zero pivot is a
# singular matrix, which Julia reports as `SingularException`; the C prints that and
# stops.
function luhelper!(helpers::Dict{String, String}, T::Type)
    n = shape(T)[1]
    E = eltype(T)
    name = "lu_" * dims(T)
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    _, zero = onezero(E)
    body = ["for (int i = 0; i < $n; i++) {",
            "    for (int j = 0; j < $n; j++) {",
            "        LU[i][j] = $(access(T, A, ["i", "j"]));",
            "    }",
            "    p[i] = i;",
            "}",
            "for (int k = 0; k < $n; k++) {",
            "    $(pivothelper!(helpers, T))(LU, p, k);",
            "    if (LU[k][k] == $zero) {",
            "        fprintf(stderr, \"SingularException(%d)\\n\", k + 1);",
            "        abort();",
            "    }",
            "    for (int i = k + 1; i < $n; i++) {",
            "        LU[i][k] /= LU[k][k];",
            "        for (int j = k + 1; j < $n; j++) {",
            "            LU[i][j] -= LU[i][k] * LU[k][j];",
            "        }",
            "    }",
            "}"]
    helpers[name] = definition("void", name, [declare(T, A; constant=true), "$(ctype(E)) LU[restrict $n][$n]", "int p[restrict $n]"], body;
                               doc=["LU decomposition of a $(describe(T)) with partial pivoting", "L * U = $A[p, :]",
                                    "@param LU  L below the diagonal (unit diagonal implied), U on and above it",
                                    "@param p   the row permutation: row i of LU is row p[i] of $A"], inline=false)
    return name
end

# The lines solving `A x = b` from an existing LU: forward substitution with the
# permuted right-hand side (`b` given as an expression in `i`), then back substitution,
# into `x`.
function lusolve(n, x, b)
    ["for (int i = 0; i < $n; i++) {",
     "    $x[i] = $b;",
     "    for (int k = 0; k < i; k++) {",
     "        $x[i] -= LU[i][k] * $x[k];",
     "    }",
     "}",
     "for (int i = $(n - 1); i >= 0; i--) {",
     "    for (int k = i + 1; k < $n; k++) {",
     "        $x[i] -= LU[i][k] * $x[k];",
     "    }",
     "    $x[i] /= LU[i][i];",
     "}"]
end

# `A \ b` for a square `A` and a vector `b`: `solve_3x3_3`. Sizes 1–3 by Cramer's rule,
# written out exactly as StaticArrays writes them; from 4 on through `lu_NxN`.
function solvehelper!(helpers::Dict{String, String}, T::Type, B::Type, R::Type)
    m, n = extent(T, 1), extent(T, 2)
    ndims(T) == 2 && extent(B, 1) == m || throw(ArgumentError("\\: a $(describe(T)) can't be solved against a $(describe(B))"))
    E = eltype(R)
    name = helpername(:solve, (T, B))
    haskey(helpers, name) && return name
    A, b = inputs((T, B))
    if m != n && ndims(B) == 1
        # Not square: least squares. Tall, the normal equations `AᵀA x = Aᵀb` through
        # Cholesky; short, the minimum-norm solution `x = Aᵀ (A Aᵀ)⁻¹ b`. Julia goes
        # through QR; this is faster and agrees to rounding for a well-conditioned `A`.
        AT = transposed(T)
        if m > n
            G, c = shaped(E, (n, n)), shaped(E, (n,))
            body = ["$(ctype(E)) G[$n][$n];", "$(ctype(E)) c[$n];",
                    "$(helper!(helpers, :mul, (AT, T), G))($A, $A, G);",
                    "$(helper!(helpers, :mul, (AT, B), c))($A, $b, c);",
                    "$(solveLLThelper!(helpers, G, c, R))(G, c, out);"]
            doc = ["$(describe(T)) \\ $(describe(B)) least squares by the normal equations", "out = $A \\ $b, least squares"]
        else
            G, y = shaped(E, (m, m)), shaped(E, (m,))
            body = ["$(ctype(E)) G[$m][$m];", "$(ctype(E)) y[$m];",
                    "$(helper!(helpers, :mul, (T, AT), G))($A, $A, G);",
                    "$(solveLLThelper!(helpers, G, B, y))(G, $b, y);",
                    "$(helper!(helpers, :mul, (AT, y), R))($A, y, out);"]
            doc = ["$(describe(T)) \\ $(describe(B)) minimum-norm solve through A Aᵀ", "out = $A \\ $b, minimum norm"]
        end
        helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(B, b; constant=true), declare(R, "out"; restrict=true)], body; doc, inline=false)
        return name
    end
    if ndims(B) == 2
        # A matrix right-hand side: one column at a time through the vector solve.
        k = extent(B, 2)
        V = shaped(eltype(B), (m,))
        body = ["$(ctype(eltype(B))) column[$m];", "$(ctype(E)) x[$n];",
                "for (int j = 0; j < $k; j++) {",
                "    for (int i = 0; i < $m; i++) {",
                "        column[i] = $(access(B, b, ["i", "j"]));",
                "    }",
                "    $(solvehelper!(helpers, T, V, shaped(E, (n,))))($A, column, x);",
                "    for (int i = 0; i < $n; i++) {",
                "        out[i][j] = x[i];",
                "    }",
                "}"]
        helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(B, b; constant=true), declare(R, "out"; restrict=true)], body;
                                   doc=["$(describe(T)) \\ $(describe(B)) solve, column by column", "out = $A \\ $b"], inline=false)
        return name
    end
    a(i, j) = access(T, A, [string(i), string(j)])
    bb(i) = access(B, b, [string(i), "0"])
    body = if n == 1
        ["out[0] = $(bb(0)) / $(a(0, 0));"]
    elseif n == 2
        ["$(ctype(E)) d = $(dethelper!(helpers, T, E))($A);",
         "out[0] = ($(a(1, 1)) * $(bb(0)) - $(a(0, 1)) * $(bb(1))) / d;",
         "out[1] = ($(a(0, 0)) * $(bb(1)) - $(a(1, 0)) * $(bb(0))) / d;"]
    elseif n == 3
        ["$(ctype(E)) d = $(dethelper!(helpers, T, E))($A);",
         "out[0] = (($(a(1, 1)) * $(a(2, 2)) - $(a(1, 2)) * $(a(2, 1))) * $(bb(0))",
         "        + ($(a(0, 2)) * $(a(2, 1)) - $(a(0, 1)) * $(a(2, 2))) * $(bb(1))",
         "        + ($(a(0, 1)) * $(a(1, 2)) - $(a(0, 2)) * $(a(1, 1))) * $(bb(2))) / d;",
         "out[1] = (($(a(1, 2)) * $(a(2, 0)) - $(a(1, 0)) * $(a(2, 2))) * $(bb(0))",
         "        + ($(a(0, 0)) * $(a(2, 2)) - $(a(0, 2)) * $(a(2, 0))) * $(bb(1))",
         "        + ($(a(0, 2)) * $(a(1, 0)) - $(a(0, 0)) * $(a(1, 2))) * $(bb(2))) / d;",
         "out[2] = (($(a(1, 0)) * $(a(2, 1)) - $(a(1, 1)) * $(a(2, 0))) * $(bb(0))",
         "        + ($(a(0, 1)) * $(a(2, 0)) - $(a(0, 0)) * $(a(2, 1))) * $(bb(1))",
         "        + ($(a(0, 0)) * $(a(1, 1)) - $(a(0, 1)) * $(a(1, 0))) * $(bb(2))) / d;"]
    else
        vcat(["$(ctype(E)) LU[$n][$n];", "int p[$n];", "$(luhelper!(helpers, T))($A, LU, p);"], lusolve(n, "out", access(B, b, ["p[i]", "0"])))
    end
    doc = [n <= 3 ? "$(describe(T)) \\ $(describe(B)) solve by Cramer's rule" : "$(describe(T)) \\ $(describe(B)) solve by LU with partial pivoting",
           "out = $(istransposed(T) ? A * tmark(T) : A) \\ $b"]
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(B, b; constant=true), declare(R, "out"; restrict=true)], body; doc, inline=n <= 3)
    return name
end

# `B / A`: `rsolve_2x3_3x3`. Each row of `B` is a right-hand side of `Aᵀ x = rowᵀ`, so
# the work is the vector solve with `A` read transposed — the same helper as `\`,
# `solve_T3x3_3`, which costs nothing to read the other way round.
function rsolvehelper!(helpers::Dict{String, String}, B::Type, A::Type, R::Type)
    n = shape(A)[1]
    ndims(A) == 2 && allequal(shape(A)) && extent(B, 2) == n || throw(ArgumentError("/: a $(describe(B)) can't be divided by a $(describe(A))"))
    m = extent(B, 1)
    E = eltype(R)
    name = helpername(:rsolve, (B, A))
    haskey(helpers, name) && return name
    Bn, An = inputs((B, A))
    inner = solvehelper!(helpers, transposed(A), shaped(eltype(B), (n,)), shaped(E, (n,)))
    i = m > 1 ? "i" : "0"
    body = vcat(["$(ctype(eltype(B))) row[$n];", "$(ctype(E)) x[$n];"],
                nest(live([("i", m)]), vcat(nest([("j", n)], ["row[j] = $(access(B, Bn, [i, "j"]));"]),
                                            ["$inner($An, row, x);"],
                                            nest([("j", n)], ["$(access(R, "out", [i, "j"])) = x[j];"]))))
    helpers[name] = definition("void", name, [declare(B, Bn; constant=true), declare(A, An; constant=true), declare(R, "out"; restrict=true)], body;
                               doc=["$(describe(B)) / $(describe(A)) solve, row by row through the transpose", "out = $Bn / $An"], inline=false)
    return name
end

# `pinv(A)`: `pinv_4x3`. Square, it is the inverse; tall, `(AᵀA)⁻¹ Aᵀ`; short,
# `Aᵀ (A Aᵀ)⁻¹` — the Gram matrix through Cholesky, since it's positive definite
# whenever `A` has full rank. Julia goes through the SVD, which also copes with a
# rank-deficient `A`; this doesn't, and says so (`PosDefException`).
function pinvhelper!(helpers::Dict{String, String}, T::Type, R::Type)
    m, n = extent(T, 1), extent(T, 2)
    ndims(T) == 2 || throw(ArgumentError("pinv needs a matrix, got a $(describe(T))"))
    E = eltype(R)
    name = helpername(:pinv, (T,))
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    AT = transposed(T)
    body, doc = if m == n
        ["$(invhelper!(helpers, T, R))($A, out);"], ["pseudoinverse of a square $(describe(T)): the inverse", "out = $(A)⁻¹"]
    elseif m > n
        G = shaped(E, (n, n))
        ["$(ctype(E)) G[$n][$n];", "$(ctype(E)) Ginv[$n][$n];",
         "$(helper!(helpers, :mul, (AT, T), G))($A, $A, G);",
         "$(invLLThelper!(helpers, G, G))(G, Ginv);",
         "$(helper!(helpers, :mul, (G, AT), R))(Ginv, $A, out);"], ["pseudoinverse of a tall $(describe(T))", "out = ($(A)ᵀ$A)⁻¹$(A)ᵀ"]
    else
        G = shaped(E, (m, m))
        ["$(ctype(E)) G[$m][$m];", "$(ctype(E)) Ginv[$m][$m];",
         "$(helper!(helpers, :mul, (T, AT), G))($A, $A, G);",
         "$(invLLThelper!(helpers, G, G))(G, Ginv);",
         "$(helper!(helpers, :mul, (AT, G), R))($A, Ginv, out);"], ["pseudoinverse of a short $(describe(T))", "out = $(A)ᵀ($A$(A)ᵀ)⁻¹"]
    end
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(R, "out"; restrict=true)], body; doc, inline=false)
    return name
end

# `inv(A)`: `inv_3x3`. Sizes 1–3 by the adjugate over the determinant, written out;
# from 4 on, `lu_NxN` and one solve per column of the identity.
function invhelper!(helpers::Dict{String, String}, T::Type, R::Type)
    n = shape(T)[1]
    ndims(T) == 2 && allequal(shape(T)) || throw(ArgumentError("inv needs a square matrix, got a $(describe(T))"))
    E = eltype(R)
    name = helpername(:inv, (T,))
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    a(i, j) = access(T, A, [string(i), string(j)])
    one, zero = onezero(E)
    body = if n == 1
        ["out[0][0] = $one / $(a(0, 0));"]
    elseif n == 2
        ["$(ctype(E)) d = $(dethelper!(helpers, T, E))($A);",
         "out[0][0] = $(a(1, 1)) / d;", "out[0][1] = -$(a(0, 1)) / d;",
         "out[1][0] = -$(a(1, 0)) / d;", "out[1][1] = $(a(0, 0)) / d;"]
    elseif n == 3
        cof(i, j) = (i1, i2, j1, j2) = ((i + 1) % 3, (i + 2) % 3, (j + 1) % 3, (j + 2) % 3)
        lines = ["$(ctype(E)) d = $(dethelper!(helpers, T, E))($A);"]
        for i in 0:2, j in 0:2
            # out[i][j] is the cofactor of a(j, i) over the determinant.
            r1, r2, c1, c2 = (j + 1) % 3, (j + 2) % 3, (i + 1) % 3, (i + 2) % 3
            push!(lines, "out[$i][$j] = ($(a(r1, c1)) * $(a(r2, c2)) - $(a(r1, c2)) * $(a(r2, c1))) / d;")
        end
        lines
    else
        vcat(["$(ctype(E)) LU[$n][$n];", "int p[$n];", "$(ctype(E)) x[$n];", "$(luhelper!(helpers, T))($A, LU, p);",
              "for (int j = 0; j < $n; j++) {"],
             "    " .* lusolve(n, "x", "p[i] == j ? $one : $zero"),
             ["    for (int i = 0; i < $n; i++) {", "        out[i][j] = x[i];", "    }", "}"])
    end
    doc = [n <= 3 ? "$(describe(T)) inverse by the adjugate" : "$(describe(T)) inverse by LU with partial pivoting", "out = $(A)⁻¹"]
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(R, "out"; restrict=true)], body; doc, inline=n <= 3)
    return name
end

# The Cholesky factor `L` (lower, `A = L Lᵀ`) of a symmetric positive-definite `A`:
# `llt_3x3`. Written out for sizes 1–3, a loop beyond. A non-positive pivot is Julia's
# `PosDefException`; the C prints that and stops.
function llthelper!(helpers::Dict{String, String}, T::Type)
    n = shape(T)[1]
    ndims(T) == 2 && allequal(shape(T)) || throw(ArgumentError("cholesky needs a square matrix, got a $(describe(T))"))
    E = eltype(T)
    name = "llt_" * dims(T)
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    # Complex: the factor is L Lᴴ, the products against a conjugate, the pivots real.
    cx = E <: Complex
    R = cx ? real(E) : E
    sqrt = mathname(R, "sqrt")
    conj(x) = cx ? "$(mathname(E, "conj"))($x)" : x
    re(x) = cx ? "$(mathname(E, "real"))($x)" : x
    _, zero = onezero(R)
    body = String[]
    if n <= 3
        # Written out: each entry of L from the ones already known.
        for j in 0:n-1, i in j:n-1
            s = access(T, A, [string(i), string(j)]) * join(" - L[$i][$k] * $(conj("L[$j][$k]"))" for k in 0:j-1)
            if i == j
                push!(body, "L[$j][$j] = $(re(j == 0 ? s : "($s)"));")
                push!(body, "if ($(re("L[$j][$j]")) <= $zero) {", "    fprintf(stderr, \"PosDefException(%d)\\n\", $(j + 1));", "    abort();", "}")
                push!(body, "L[$j][$j] = $sqrt($(re("L[$j][$j]")));")
            else
                push!(body, "L[$i][$j] = $(j == 0 ? s : "($s)") / L[$j][$j];")
            end
        end
        for i in 0:n-1, j in i+1:n-1
            push!(body, "L[$i][$j] = $zero;")
        end
    else
        body = ["for (int j = 0; j < $n; j++) {",
                "    $(ctype(E)) s = $(access(T, A, ["j", "j"]));",
                "    for (int k = 0; k < j; k++) {",
                "        s -= L[j][k] * $(conj("L[j][k]"));",
                "    }",
                "    if ($(re("s")) <= $zero) {",
                "        fprintf(stderr, \"PosDefException(%d)\\n\", j + 1);",
                "        abort();",
                "    }",
                "    L[j][j] = $sqrt($(re("s")));",
                "    for (int i = j + 1; i < $n; i++) {",
                "        s = $(access(T, A, ["i", "j"]));",
                "        for (int k = 0; k < j; k++) {",
                "            s -= L[i][k] * $(conj("L[j][k]"));",
                "        }",
                "        L[i][j] = s / L[j][j];",
                "    }",
                "    for (int i = 0; i < j; i++) {",
                "        L[i][j] = $zero;",
                "    }",
                "}"]
    end
    helpers[name] = definition("void", name, [declare(T, A; constant=true), "$(ctype(E)) L[restrict $n][$n]"], body;
                               doc=["Cholesky factor of a $(describe(T))", "$A = L L$(cx ? "ᴴ" : "ᵀ")"], inline=false)
    return name
end

# The lines solving `L Lᵀ x = b` from a Cholesky factor: forward with L, back with Lᵀ.
function lltsolve(n, x, b, E::Type)
    conj(t) = E <: Complex ? "$(mathname(E, "conj"))($t)" : t   # back-substitution is with Lᴴ
    ["for (int i = 0; i < $n; i++) {",
     "    $x[i] = $b;",
     "    for (int k = 0; k < i; k++) {",
     "        $x[i] -= L[i][k] * $x[k];",
     "    }",
     "    $x[i] /= L[i][i];",
     "}",
     "for (int i = $(n - 1); i >= 0; i--) {",
     "    for (int k = i + 1; k < $n; k++) {",
     "        $x[i] -= $(conj("L[k][i]")) * $x[k];",
     "    }",
     "    $x[i] /= L[i][i];",
     "}"]
end

# `cholesky(A) \ b`: `solveLLT_3x3_3`. The factor, then two triangular solves.
function solveLLThelper!(helpers::Dict{String, String}, T::Type, B::Type, R::Type)
    n = shape(T)[1]
    extent(B, 1) == n || throw(ArgumentError("\\: a $(describe(T)) can't be solved against a $(describe(B))"))
    E = eltype(R)
    name = helpername(:solveLLT, (T, B))
    haskey(helpers, name) && return name
    A, b = inputs((T, B))
    # A vector right-hand side is solved in place; a matrix, one column at a time.
    body = ndims(B) == 1 ?
        vcat(["$(ctype(E)) L[$n][$n];", "$(llthelper!(helpers, T))($A, L);"], lltsolve(n, "out", access(B, b, ["i", "0"]), E)) :
        vcat(["$(ctype(E)) L[$n][$n];", "$(ctype(E)) x[$n];", "$(llthelper!(helpers, T))($A, L);", "for (int j = 0; j < $(extent(B, 2)); j++) {"],
             "    " .* lltsolve(n, "x", access(B, b, ["i", "j"]), E),
             ["    for (int i = 0; i < $n; i++) {", "        out[i][j] = x[i];", "    }", "}"])
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(B, b; constant=true), declare(R, "out"; restrict=true)], body;
                               doc=["$(describe(T)) \\ $(describe(B)) solve by Cholesky", "out = $A \\ $b, $A positive definite"], inline=false)
    return name
end

# `inv(cholesky(A))`: `invLLT_3x3`. The factor, then one solve per column of the identity.
function invLLThelper!(helpers::Dict{String, String}, T::Type, R::Type)
    n = shape(T)[1]
    E = eltype(R)
    name = helpername(:invLLT, (T,))
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    one, zero = onezero(E)
    body = vcat(["$(ctype(E)) L[$n][$n];", "$(ctype(E)) x[$n];", "$(llthelper!(helpers, T))($A, L);",
                 "for (int j = 0; j < $n; j++) {"],
                "    " .* lltsolve(n, "x", "i == j ? $one : $zero", E),
                ["    for (int i = 0; i < $n; i++) {", "        out[i][j] = x[i];", "    }", "}"])
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(R, "out"; restrict=true)], body;
                               doc=["$(describe(T)) inverse by Cholesky", "out = $(A)⁻¹, $A positive definite"], inline=false)
    return name
end

# The cross product. Only ever 3-vectors, which the name therefore leaves out: `cross`.
function crosshelper!(helpers::Dict{String, String}, types, R::Type)
    all(T -> shape(T) == (3,), types) || throw(ArgumentError("cross: both arguments must be 3-vectors"))
    name = helpername(:cross, types)
    if !haskey(helpers, name)
        (a, b), (an, bn) = types, inputs(types)
        helpers[name] = definition("void", name, [declare(a, an; constant=true), declare(b, bn; constant=true), declare(R, "out"; restrict=true)],
                                   ["out[0] = $an[1] * $bn[2] - $an[2] * $bn[1];", "out[1] = $an[2] * $bn[0] - $an[0] * $bn[2];",
                                    "out[2] = $an[0] * $bn[1] - $an[1] * $bn[0];"]; doc=[prose(:cross, types, R), "out = $an × $bn"])
    end
    return name
end

# A broadcast: `f` applied elementwise over `types`, with Julia's rules — dimensions
# line up from the left, and a size of 1 stretches to match. An operand with no
# dimension on some axis just contributes nothing there; `access` does the stretching
# by indexing a dimension of extent 1 with `0`.
# The C operator behind a pointwise operation, and its dotspelling Julia spelling.
const csymbol = Dict(:add => "+", :sub => "-", :mul => "*", :div => "/", :lt => "<", :le => "<=", :gt => ">", :ge => ">=",
                     :eq => "==", :ne => "!=", :and => "&", :or => "|")
const dotspelling = Dict(:add => ".+", :sub => ".-", :mul => ".*", :div => "./", :pow => ".^", :lt => ".<", :le => ".<=", :gt => ".>",
                    :ge => ".>=", :eq => ".==", :ne => ".!=", :and => ".&", :or => ".|")

function broadcasthelper!(helpers::Dict{String, String}, op::Symbol, cfn, types, R::Type)
    name = helpername(op, types; pointwise=true)
    if !haskey(helpers, name)
        argnames = inputs(types)
        idx, pairs = loopindices(extents(R); taken=argnames)
        accesses = [access(T, n, idx) for (T, n) in zip(types, argnames)]
        expr = cfn isa String ? "$cfn($(join(accesses, ", ")))" :
               cfn isa Integer ? powexpr(helpers, accesses[1], cfn, eltype(R)) :
               cfn == :neg ? "-" * accesses[1] :
               cfn == :not ? "!" * accesses[1] :
               cfn == :ifelse ? "$(accesses[1]) ? $(accesses[2]) : $(accesses[3])" :
               cfn == :div && all(T -> (T <: AbstractArray ? eltype(T) : T) <: Integer, types) ?
                   "($(ctype(eltype(R))))$(accesses[1]) / ($(ctype(eltype(R))))$(accesses[2])" :
               join(accesses, " " * csymbol[cfn] * " ")
        body = nest(pairs, ["$(access(R, "out", idx)) = $expr;"])
        params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
        push!(params, declare(R, "out"; restrict=!any(T -> alike(T, R), types)))
        spelled = [istransposed(T) ? n * tmark(T) : n for (T, n) in zip(types, argnames)]
        formula = cfn isa Integer ? "out = $(spelled[1]) .^ $cfn" :
                  length(types) == 1 ? (cfn == :neg ? "out = .-$(spelled[1])" : cfn == :not ? "out = .!$(spelled[1])" : "out = $op.($(spelled[1]))") :
                  length(types) == 2 && haskey(dotspelling, op) ? "out = $(spelled[1]) $(dotspelling[op]) $(spelled[2])" : "out = $op.($(join(spelled, ", ")))"
        helpers[name] = definition("void", name, params, body; doc=[prose(op, types, R; pointwise=true), formula])
    end
    return name
end

# The shape of a broadcast over `types`: one extent per axis up to the last axis any
# operand reaches, every dimension the operands brought kept (extent-1 ones included).
# Nothing if the extents don't line up.
function broadcastshape(types)
    nd = maximum(T -> isempty(axis(T)) ? 0 : maximum(axis(T)), types)
    out = Int[]
    for d in 1:nd
        big = unique(filter(!=(1), [extent(T, d) for T in types]))
        length(big) <= 1 || return nothing
        push!(out, isempty(big) ? 1 : big[1])
    end
    return Tuple(out)
end

