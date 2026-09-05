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
    fundamental(T) = T <: AbstractArray ? eltype(T) : T
    alldouble = all(T -> fundamental(T) === Float64, types)
    sizes = [T <: AbstractArray ? dims(T) : "s" for T in types]
    typs = [abbrev(fundamental(T)) for T in types]
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
function helpercode(name::AbstractString, op::Symbol, types, R::Type)
    names = inputs(types)
    params = [declare(T, n; constant=true) for (T, n) in zip(types, names)]
    push!(params, declare(R, "out"; restrict=true))
    aligned = all(T -> !(T <: AbstractArray) || axis(T) == axis(R), types)
    sub(T, var, idx) = aligned ? (T <: AbstractArray ? var * brackets(idx) : var) : access(T, var, idx)
    walk(line) = elementwise(aligned ? shape(R) : extents(R), idx -> "$(sub(R, "out", idx)) = $(line(idx));"; taken=names)
    body = if op in (:add, :sub)
        a, b = types
        extents(a) == extents(b) || throw(ArgumentError("$op: dimensions don't match, $(dims(a)) and $(dims(b))"))
        walk(idx -> "$(sub(a, names[1], idx)) $(op == :add ? "+" : "-") $(sub(b, names[2], idx))")
    elseif op == :neg
        walk(idx -> "-" * sub(types[1], names[1], idx))
    elseif op == :copy
        walk(idx -> sub(types[1], names[1], idx))
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
    return definition("void", name, params, body; doc=prose(op, types, R))
end

# ---- the primitives every generator is built from ----------------------------------

# A helper's full C definition, with its comment above it: a one-line brief (see
# prose.jl), or that plus `@param` lines for the parameters whose meaning isn't in
# their name. `body` lines are relative to the function's own indent. A helper is
# `static inline` when it's straight-line code or plain loops — the small things a C
# programmer marks inline — and plain `static` when it calls other helpers, searches,
# or can abort: the solvers and factorizations, which nobody wants copied into every
# caller.
definition(ret, name, params, body; doc::Union{AbstractString, Vector{String}}="", inline::Bool=true) =
    join("/// " .* (doc isa AbstractString ? (isempty(doc) ? String[] : [doc]) : doc), "\n") * (isempty(doc) ? "" : "\n") *
    "static $(inline ? "inline " : "")$ret $name($(join(params, ", "))) {\n" * join("    " .* body, "\n") * "\n}\n"

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
function access(T::Type, var::AbstractString, idx)
    return var * join("[" * (extent(T, d) == 1 ? "0" : idx[d]) * "]" for d in axis(T))
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
    zero = ctype(E) == "float" ? "0.0f" : E <: AbstractFloat ? "0.0" : "0"
    ii, jj, kk = indices(3; taken=(an, bn))
    i, j, k = m > 1 ? ii : "0", n > 1 ? jj : "0", K > 1 ? kk : "0"
    term = "$(access(a, an, [i, k])) * $(access(b, bn, [k, j]))"
    if R === nothing
        return ["$(ctype(E)) sum = $zero;"; nest(live([(kk, K)]), ["sum += $term;"]); "return sum;"]
    end
    out = access(R, "out", [i, j])
    K == 1 && return nest(live([(ii, m), (jj, n)]), ["$out = $term;"])
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
        row = isrow(a) ? a : Transposed{eltype(a), shape(a), 1}
        body = contraction(row, b, an, bn, nothing, E)
        helpers[name] = definition(ctype(E), name, [declare(a, an; constant=true), declare(b, bn; constant=true)], body;
                                   doc=prose(op, types))
    end
    return name
end

# ---- the rest ----------------------------------------------------------------------

# The helper that fills an array of type `R` with one value: `fill_3`, `fill_2x2`. Its
# only input is a scalar, which says nothing about the size, so the output's goes in
# the name — the same reason `hvcat2x2_…` carries its grid.
function fillhelper!(helpers::Dict{String, String}, R::Type)
    name = "fill_" * outname(R)
    if !haskey(helpers, name)
        body = elementwise(shape(R), idx -> "out$(brackets(idx)) = a;")
        helpers[name] = definition("void", name, ["$(ctype(eltype(R))) a", declare(R, "out"; restrict=true)], body; doc="$(describe(R)) fill")
    end
    return name
end

# The all-zero array of type `R`: `zero_3x4`. One `memset` — all-zero bytes are zero in
# every C type the transpiler emits.
function zerohelper!(helpers::Dict{String, String}, R::Type)
    name = "zero_" * outname(R)
    haskey(helpers, name) || (helpers[name] = definition("void", name, [declare(R, "out"; restrict=true)], [zeroing(R)]; doc="zero $(describe(R))"))
    return name
end

# The identity matrix of type `R`: `identity_3x3`. Zeroed as a block, then ones down the
# diagonal — `min(m, n)` of them if it isn't square.
function identityhelper!(helpers::Dict{String, String}, R::Type)
    ndims(R) == 2 || throw(ArgumentError("the identity is a matrix, not a $(describe(R))"))
    name = "identity_" * outname(R)
    if !haskey(helpers, name)
        d = minimum(shape(R))
        one = ctype(eltype(R)) == "float" ? "1.0f" : eltype(R) <: AbstractFloat ? "1.0" : "1"
        i = d > 1 ? "i" : "0"
        body = [zeroing(R); nest(live([("i", d)]), ["out[$i][$i] = $one;"])]
        helpers[name] = definition("void", name, [declare(R, "out"; restrict=true)], body; doc="identity $(describe(R))")
    end
    return name
end

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
        one, zero = E <: AbstractFloat ? (ctype(E) == "float" ? ("1.0f", "0.0f") : ("1.0", "0.0")) : ("1", "0")
        cut = nest([("i", n - 1), ("k", n - 1)], ["M[i][k] = $(access(T, A, ["i + 1", "k < j ? k : k + 1"]));"])
        loop = nest([("j", n)], [cut; "det += sign * $(access(T, A, ["0", "j"])) * $(dethelper!(helpers, S, E))(M);"; "sign = -sign;"])
        ["$(ctype(E)) det = $zero;"; "$(ctype(E)) sign = $one;"; declare(S, "M") * ";"; loop; "return det;"]
    end
    helpers[name] = definition(ctype(E), name, [declare(T, A; constant=true)], body; doc="$(describe(T)) determinant", inline=n <= 3)
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
    zero = E <: AbstractFloat ? (ctype(E) == "float" ? "0.0f" : "0.0") : "0"
    one = E <: AbstractFloat ? (ctype(E) == "float" ? "1.0f" : "1.0") : "1"
    body = op == :sum     ? ["$(ctype(E)) sum = $zero;"; nest(pairs, ["sum += $a;"]); "return sum;"] :
           op == :prod    ? ["$(ctype(E)) product = $one;"; nest(pairs, ["product *= $a;"]); "return product;"] :
           op == :maximum ? ["$(ctype(E)) max = $first;"; nest(pairs, ["if ($a > max) {", "    max = $a;", "}"]); "return max;"] :
           op == :minimum ? ["$(ctype(E)) min = $first;"; nest(pairs, ["if ($a < min) {", "    min = $a;", "}"]); "return min;"] :
           op == :any     ? [nest(pairs, ["if ($a) {", "    return true;", "}"]); "return false;"] :
           op == :all     ? [nest(pairs, ["if (!$a) {", "    return false;", "}"]); "return true;"] :
           op == :norm    ? ["$(ctype(E)) sum = $zero;"; nest(pairs, ["sum += $a * $a;"]); "return $(ctype(E) == "float" ? "sqrtf" : "sqrt")(sum);"] :
           throw(ArgumentError("unsupported reduction: $op"))
    helpers[name] = definition(ctype(E), name, [declare(T, A; constant=true)], body; doc=prose(op, (T,)))
    return name
end

# A slice of an array into a smaller one: a row or a column of a matrix, or a run of a
# vector. The position is a parameter, 0-based, so one helper serves every position.
function slicehelper!(helpers::Dict{String, String}, kind::Symbol, T::Type, R::Type)
    m = kind == :row ? "row" : kind == :col ? "col" : "slice"
    name = m * "_" * dims(T) * (kind == :slice ? "_" * dims(R) : "")
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    body, param, doc = if kind == :row
        nest([("j", shape(R)[1])], ["out[j] = $(access(T, A, ["i", "j"]));"]), "int i",
        ["row of a $(describe(T))", "@param i  the row, 0-based"]
    elseif kind == :col
        nest([("i", shape(R)[1])], ["out[i] = $(access(T, A, ["i", "j"]));"]), "int j",
        ["column of a $(describe(T))", "@param j  the column, 0-based"]
    else
        nest([("i", shape(R)[1])], ["out[i] = $(A)[from + i];"]), "int from",
        ["$(shape(R)[1])-element slice of a $(describe(T))", "@param from  where the slice starts, 0-based"]
    end
    helpers[name] = definition("void", name, [declare(T, A; constant=true), param, declare(R, "out"; restrict=true)], body; doc)
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
onezero(E::Type) = E <: AbstractFloat ? (ctype(E) == "float" ? ("1.0f", "0.0f") : ("1.0", "0.0")) : ("1", "0")

# Partial pivoting for column `k` of the LU work array: the row at or below `k` with the
# largest magnitude in that column is swapped into row `k`, in both `LU` and the
# permutation `p`. Shared by `lu_NxN` and anything else that eliminates.
function pivothelper!(helpers::Dict{String, String}, T::Type)
    n = shape(T)[1]
    E = eltype(T)
    name = "pivot_" * dims(T)
    haskey(helpers, name) && return name
    fabs = ctype(E) == "float" ? "fabsf" : "fabs"
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
                               doc=["LU decomposition of a $(describe(T)) with partial pivoting",
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
            doc = "$(describe(T)) \\ $(describe(B)) least squares by the normal equations"
        else
            G, y = shaped(E, (m, m)), shaped(E, (m,))
            body = ["$(ctype(E)) G[$m][$m];", "$(ctype(E)) y[$m];",
                    "$(helper!(helpers, :mul, (T, AT), G))($A, $A, G);",
                    "$(solveLLThelper!(helpers, G, B, y))(G, $b, y);",
                    "$(helper!(helpers, :mul, (AT, y), R))($A, y, out);"]
            doc = "$(describe(T)) \\ $(describe(B)) minimum-norm solve through A Aᵀ"
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
                                   doc="$(describe(T)) \\ $(describe(B)) solve, column by column", inline=false)
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
    doc = n <= 3 ? "$(describe(T)) \\ $(describe(B)) solve by Cramer's rule" : "$(describe(T)) \\ $(describe(B)) solve by LU with partial pivoting"
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
                               doc="$(describe(B)) / $(describe(A)) solve, row by row through the transpose", inline=false)
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
        ["$(invhelper!(helpers, T, R))($A, out);"], "pseudoinverse of a square $(describe(T)): the inverse"
    elseif m > n
        G = shaped(E, (n, n))
        ["$(ctype(E)) G[$n][$n];", "$(ctype(E)) Ginv[$n][$n];",
         "$(helper!(helpers, :mul, (AT, T), G))($A, $A, G);",
         "$(invLLThelper!(helpers, G, G))(G, Ginv);",
         "$(helper!(helpers, :mul, (G, AT), R))(Ginv, $A, out);"], "pseudoinverse of a tall $(describe(T)), (AᵀA)⁻¹Aᵀ"
    else
        G = shaped(E, (m, m))
        ["$(ctype(E)) G[$m][$m];", "$(ctype(E)) Ginv[$m][$m];",
         "$(helper!(helpers, :mul, (T, AT), G))($A, $A, G);",
         "$(invLLThelper!(helpers, G, G))(G, Ginv);",
         "$(helper!(helpers, :mul, (AT, G), R))($A, Ginv, out);"], "pseudoinverse of a short $(describe(T)), Aᵀ(AAᵀ)⁻¹"
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
    doc = n <= 3 ? "$(describe(T)) inverse by the adjugate" : "$(describe(T)) inverse by LU with partial pivoting"
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
    sqrt = ctype(E) == "float" ? "sqrtf" : "sqrt"
    _, zero = onezero(E)
    body = String[]
    if n <= 3
        # Written out: each entry of L from the ones already known.
        for j in 0:n-1, i in j:n-1
            s = access(T, A, [string(i), string(j)]) * join(" - L[$i][$k] * L[$j][$k]" for k in 0:j-1)
            if i == j
                push!(body, "L[$j][$j] = $s;")
                push!(body, "if (L[$j][$j] <= $zero) {", "    fprintf(stderr, \"PosDefException(%d)\\n\", $(j + 1));", "    abort();", "}")
                push!(body, "L[$j][$j] = $sqrt(L[$j][$j]);")
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
                "        s -= L[j][k] * L[j][k];",
                "    }",
                "    if (s <= $zero) {",
                "        fprintf(stderr, \"PosDefException(%d)\\n\", j + 1);",
                "        abort();",
                "    }",
                "    L[j][j] = $sqrt(s);",
                "    for (int i = j + 1; i < $n; i++) {",
                "        s = $(access(T, A, ["i", "j"]));",
                "        for (int k = 0; k < j; k++) {",
                "            s -= L[i][k] * L[j][k];",
                "        }",
                "        L[i][j] = s / L[j][j];",
                "    }",
                "    for (int i = 0; i < j; i++) {",
                "        L[i][j] = $zero;",
                "    }",
                "}"]
    end
    helpers[name] = definition("void", name, [declare(T, A; constant=true), "$(ctype(E)) L[restrict $n][$n]"], body;
                               doc="Cholesky factor of a $(describe(T)), A = L Lᵀ", inline=false)
    return name
end

# The lines solving `L Lᵀ x = b` from a Cholesky factor: forward with L, back with Lᵀ.
function lltsolve(n, x, b)
    ["for (int i = 0; i < $n; i++) {",
     "    $x[i] = $b;",
     "    for (int k = 0; k < i; k++) {",
     "        $x[i] -= L[i][k] * $x[k];",
     "    }",
     "    $x[i] /= L[i][i];",
     "}",
     "for (int i = $(n - 1); i >= 0; i--) {",
     "    for (int k = i + 1; k < $n; k++) {",
     "        $x[i] -= L[k][i] * $x[k];",
     "    }",
     "    $x[i] /= L[i][i];",
     "}"]
end

# `cholesky(A) \ b`: `solveLLT_3x3_3`. The factor, then two triangular solves.
function solveLLThelper!(helpers::Dict{String, String}, T::Type, B::Type, R::Type)
    n = shape(T)[1]
    ndims(B) == 1 || throw(ArgumentError("cholesky(A) \\ B with a matrix B is not supported yet"))
    extent(B, 1) == n || throw(ArgumentError("\\: a $(describe(T)) can't be solved against a $(describe(B))"))
    E = eltype(R)
    name = helpername(:solveLLT, (T, B))
    haskey(helpers, name) && return name
    A, b = inputs((T, B))
    body = vcat(["$(ctype(E)) L[$n][$n];", "$(llthelper!(helpers, T))($A, L);"], lltsolve(n, "out", access(B, b, ["i", "0"])))
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(B, b; constant=true), declare(R, "out"; restrict=true)], body;
                               doc="$(describe(T)) \\ $(describe(B)) solve by Cholesky", inline=false)
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
                "    " .* lltsolve(n, "x", "i == j ? $one : $zero"),
                ["    for (int i = 0; i < $n; i++) {", "        out[i][j] = x[i];", "    }", "}"])
    helpers[name] = definition("void", name, [declare(T, A; constant=true), declare(R, "out"; restrict=true)], body;
                               doc="$(describe(T)) inverse by Cholesky", inline=false)
    return name
end

# A block of a matrix copied out: `block_3x4_2x2(A, i0, j0, out)`, the corner 0-based.
function blockhelper!(helpers::Dict{String, String}, T::Type, R::Type)
    name = "block_" * dims(T) * "_" * dims(R)
    haskey(helpers, name) && return name
    A = inputs((T,))[1]
    body = nest([("i", shape(R)[1]), ("j", shape(R)[2])], ["out[i][j] = $(access(T, A, ["i0 + i", "j0 + j"]));"])
    helpers[name] = definition("void", name, [declare(T, A; constant=true), "int i0", "int j0", declare(R, "out"; restrict=true)], body;
                               doc=["$(describe(R)) block of a $(describe(T))", "@param i0  the block's first row, 0-based", "@param j0  the block's first column, 0-based"])
    return name
end

# A whole array assigned into part of a mutable one: `setrow_2x4_4(A, i, v)`,
# `setcol_2x4_2(A, j, v)`, `set_2x4_2x2(A, i0, j0, B)` for a block, `set_5_2(v, from, w)`
# for a run of a vector — the mirror images of `row_`, `col_`, `block_`, `slice_`. Named
# for the target and the source; the position is 0-based.
function sethelper!(helpers::Dict{String, String}, kind::Symbol, T::Type, S::Type)
    name = (kind == :row ? "setrow" : kind == :col ? "setcol" : "set") * "_" * dims(T) * "_" * dims(S)
    haskey(helpers, name) && return name
    A, b = inputs((T, S))
    body, params, doc = if kind == :run
        nest([("i", extent(S, 1))], ["$A[from + i] = $(access(S, b, ["i"]));"]), ["int from"],
        ["run of a $(describe(T)) set from a $(describe(S))", "@param from  where the run starts, 0-based"]
    elseif kind == :row
        nest([("j", extent(S, 1))], ["$A[i][j] = $(access(S, b, ["j"]));"]), ["int i"],
        ["row of a $(describe(T)) set from a $(describe(S))", "@param i  the row, 0-based"]
    elseif kind == :col
        nest([("i", extent(S, 1))], ["$A[i][j] = $(access(S, b, ["i"]));"]), ["int j"],
        ["column of a $(describe(T)) set from a $(describe(S))", "@param j  the column, 0-based"]
    else
        nest([("i", extent(S, 1)), ("j", extent(S, 2))], ["$A[i0 + i][j0 + j] = $(access(S, b, ["i", "j"]));"]), ["int i0", "int j0"],
        ["block of a $(describe(T)) set from a $(describe(S))", "@param i0  the block's first row, 0-based", "@param j0  the block's first column, 0-based"]
    end
    helpers[name] = definition("void", name, [declare(T, A; restrict=true); params; declare(S, b; constant=true)], body; doc)
    return name
end

# The output's description for a helper named by what it makes: `3x4`, `2x2I64` — the
# type appears by the same rule as for inputs, only when it isn't Float64.
outname(R::Type) = dims(R) * (eltype(R) === Float64 ? "" : abbrev(eltype(R)))

# The line that zeroes `out` of type `R`.
zeroing(R::Type) = "memset(out, 0, sizeof($(ctype(eltype(R)))$(join("[$n]" for n in shape(R)))));"

# The cross product. Only ever 3-vectors, which the name therefore leaves out: `cross`.
function crosshelper!(helpers::Dict{String, String}, types, R::Type)
    all(T -> shape(T) == (3,), types) || throw(ArgumentError("cross: both arguments must be 3-vectors"))
    name = helpername(:cross, types)
    if !haskey(helpers, name)
        (a, b), (an, bn) = types, inputs(types)
        helpers[name] = definition("void", name, [declare(a, an; constant=true), declare(b, bn; constant=true), declare(R, "out"; restrict=true)],
                                   ["out[0] = $an[1] * $bn[2] - $an[2] * $bn[1];", "out[1] = $an[2] * $bn[0] - $an[0] * $bn[2];",
                                    "out[2] = $an[0] * $bn[1] - $an[1] * $bn[0];"]; doc=prose(:cross, types, R))
    end
    return name
end

# A broadcast: `f` applied elementwise over `types`, with Julia's rules — dimensions
# line up from the left, and a size of 1 stretches to match. An operand with no
# dimension on some axis just contributes nothing there; `access` does the stretching
# by indexing a dimension of extent 1 with `0`.
function broadcasthelper!(helpers::Dict{String, String}, op::Symbol, cfn, types, R::Type)
    name = helpername(op, types; pointwise=true)
    if !haskey(helpers, name)
        argnames = inputs(types)
        idx, pairs = loopindices(extents(R); taken=argnames)
        accesses = [access(T, n, idx) for (T, n) in zip(types, argnames)]
        expr = cfn isa String ? "$cfn($(join(accesses, ", ")))" :
               cfn == :neg ? "-" * accesses[1] :
               cfn == :div && all(T -> (T <: AbstractArray ? eltype(T) : T) <: Integer, types) ?
                   "($(ctype(eltype(R))))$(accesses[1]) / ($(ctype(eltype(R))))$(accesses[2])" :
               join(accesses, " " * Dict(:add => "+", :sub => "-", :mul => "*", :div => "/")[cfn] * " ")
        body = nest(pairs, ["$(access(R, "out", idx)) = $expr;"])
        params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
        push!(params, declare(R, "out"; restrict=true))
        helpers[name] = definition("void", name, params, body; doc=prose(op, types, R; pointwise=true))
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

# Block construction of any dimension: each block copied into place by one loop over
# its own dimensions, with its offsets added. `[A B; C D]`, `[u; v]`, `[A;; B]`, and
# `[B;; C;;; D;; E]` all come here; only the offsets differ. A scalar block takes one
# cell. Named for the form and the blocks: `hvcat2x2_2x2_2x2_2x2_2x2`, `vcat_3_3`,
# `hvncat1x2x2_…`.
function cathelper!(helpers::Dict{String, String}, form::AbstractString, types, offsets, R::Type; grid)
    descs = [T <: AbstractArray ? dims(T) : abbrev(T) for T in types]
    name = form * "_" * join(descs, "_")
    haskey(helpers, name) && return name
    argnames = inputs(types)
    N = ndims(R)
    lines = String[]
    for (k, T) in enumerate(types)
        idx, pairs = loopindices(Tuple(extent(T, d) for d in 1:N); taken=argnames)
        place(o, x) = x == "0" ? string(o) : o == 0 ? x : "$o + $x"
        subs = [place(offsets[k][d], idx[d]) for d in 1:N]
        inner = "$(access(R, "out", subs)) = $(access(T, argnames[k], idx));"
        append!(lines, nest(pairs, [inner]))
    end
    params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
    push!(params, declare(R, "out"; restrict=true))
    helpers[name] = definition("void", name, params, lines; doc=blockprose(grid, types))
    return name
end

# The output's description for a helper named by what it makes: `3x4`, `2x2I64` — the
# type appears by the same rule as for inputs, only when it isn't Float64.
outname(R::Type) = dims(R) * (eltype(R) === Float64 ? "" : abbrev(eltype(R)))

# The line that zeroes `out` of type `R`.
zeroing(R::Type) = "memset(out, 0, sizeof($(ctype(eltype(R)))$(join("[$n]" for n in shape(R)))));"

# The cross product. Only ever 3-vectors, which the name therefore leaves out: `cross`.
function crosshelper!(helpers::Dict{String, String}, types, R::Type)
    all(T -> shape(T) == (3,), types) || throw(ArgumentError("cross: both arguments must be 3-vectors"))
    name = helpername(:cross, types)
    if !haskey(helpers, name)
        (a, b), (an, bn) = types, inputs(types)
        helpers[name] = definition("void", name, [declare(a, an; constant=true), declare(b, bn; constant=true), declare(R, "out"; restrict=true)],
                                   ["out[0] = $an[1] * $bn[2] - $an[2] * $bn[1];", "out[1] = $an[2] * $bn[0] - $an[0] * $bn[2];",
                                    "out[2] = $an[0] * $bn[1] - $an[1] * $bn[0];"]; doc=prose(:cross, types, R))
    end
    return name
end

# A broadcast: `f` applied elementwise over `types`, with Julia's rules — dimensions
# line up from the left, and a size of 1 stretches to match. An operand with no
# dimension on some axis just contributes nothing there; `access` does the stretching
# by indexing a dimension of extent 1 with `0`.
function broadcasthelper!(helpers::Dict{String, String}, op::Symbol, cfn, types, R::Type)
    name = helpername(op, types; pointwise=true)
    if !haskey(helpers, name)
        argnames = inputs(types)
        idx, pairs = loopindices(extents(R); taken=argnames)
        accesses = [access(T, n, idx) for (T, n) in zip(types, argnames)]
        expr = cfn isa String ? "$cfn($(join(accesses, ", ")))" :
               cfn == :neg ? "-" * accesses[1] :
               cfn == :div && all(T -> (T <: AbstractArray ? eltype(T) : T) <: Integer, types) ?
                   "($(ctype(eltype(R))))$(accesses[1]) / ($(ctype(eltype(R))))$(accesses[2])" :
               join(accesses, " " * Dict(:add => "+", :sub => "-", :mul => "*", :div => "/")[cfn] * " ")
        body = nest(pairs, ["$(access(R, "out", idx)) = $expr;"])
        params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
        push!(params, declare(R, "out"; restrict=true))
        helpers[name] = definition("void", name, params, body; doc=prose(op, types, R; pointwise=true))
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

# Block construction: `[A B; C D]` (`rows` gives the blocks per row), `[u; v]`, `[u v]`.
# Each block is copied into place by one loop over its own dimensions; a scalar takes
# one cell.
function cathelper!(helpers::Dict{String, String}, kind::Symbol, rows, types, R::Type)
    descs = [T <: AbstractArray ? dims(T) : abbrev(T) for T in types]
    name = (kind == :hvcat ? "hvcat" * join(rows, "x") : string(kind)) * "_" * join(descs, "_")
    if !haskey(helpers, name)
        argnames = inputs(types)
        ii, jj = indices(2; taken=argnames)
        lines = String[]
        offset(base, x) = x == "0" ? string(base) : base == 0 ? x : "$base + $x"
        r0 = 0
        k = 1
        for nblocks in rows
            c0 = 0
            height = 0
            for _ in 1:nblocks
                T = types[k]
                h, w = extent(T, 1), extent(T, 2)
                height == 0 || height == h || throw(ArgumentError("$kind: blocks in a row have different heights"))
                height = h
                i, j = h > 1 ? ii : "0", w > 1 ? jj : "0"
                inner = "$(access(R, "out", [offset(r0, i), offset(c0, j)])) = $(access(T, argnames[k], [i, j]));"
                append!(lines, nest(live([(ii, h), (jj, w)]), [inner]))
                c0 += w
                k += 1
            end
            r0 += height
        end
        params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
        push!(params, declare(R, "out"; restrict=true))
        helpers[name] = definition("void", name, params, lines; doc=blockprose(kind, rows, types))
    end
    return name
end

