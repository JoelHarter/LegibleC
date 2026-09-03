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

The C name of the helper for `op` on `types`: the operation, then one description
per input, always — `add_2x2_2x2`, `mul_2x2_2`, `dot_3_3`. An array is described by
its dimensions (`2x2`, or `T3`, `T2x3` when transposed), a scalar by `s`; fundamental types
appear only when not every input is `Float64`, and then on every input — appended to
an array's dimensions, replacing a scalar's `s`. A pointwise (broadcast) operation
gets `P` after the operation: `mulP_3_3x2`, `addP_3_3`. Full rules in `doc/array.md`.
"""
function helpername(op::Symbol, types; pointwise::Bool=false)
    fundamental(T) = T <: AbstractArray ? eltype(T) : T
    alldouble = all(T -> fundamental(T) === Float64, types)
    sizes = [T <: AbstractArray ? dims(T) : "s" for T in types]
    typs = [abbrev(fundamental(T)) for T in types]
    descs = [alldouble ? sz : (T <: AbstractArray ? sz * t : t) for (T, sz, t) in zip(types, sizes, typs)]
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
    push!(params, declare(R, "out"))
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
    elseif op == :mul
        contraction(types..., names..., R, eltype(R))
    else
        throw(ArgumentError("unsupported array operation: $op"))
    end
    return definition("void", name, params, body; doc=prose(op, types, R))
end

# ---- the primitives every generator is built from ----------------------------------

# A helper's full C definition, with its one-line comment (see prose.jl) above it;
# `body` lines are relative to the function's own indent.
definition(ret, name, params, body; doc::AbstractString="") =
    (isempty(doc) ? "" : "/// $doc\n") * "static $ret $name($(join(params, ", "))) {\n" * join("    " .* body, "\n") * "\n}\n"

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

# A helper that returns a scalar: `dot_3_3`, or `mul_T3_3` for a row times a column.
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
        helpers[name] = definition("void", name, ["$(ctype(eltype(R))) a", declare(R, "out")], body; doc="$(describe(R)) fill")
    end
    return name
end

# The all-zero array of type `R`: `zero_3x4`. One `memset` — all-zero bytes are zero in
# every C type the transpiler emits.
function zerohelper!(helpers::Dict{String, String}, R::Type)
    name = "zero_" * outname(R)
    haskey(helpers, name) || (helpers[name] = definition("void", name, [declare(R, "out")], [zeroing(R)]; doc="zero $(describe(R))"))
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
        helpers[name] = definition("void", name, [declare(R, "out")], body; doc="identity $(describe(R))")
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
    helpers[name] = definition(ctype(E), name, [declare(T, A; constant=true)], body; doc="$(describe(T)) determinant")
    return name
end

# The output's description for a helper named by what it makes: `3x4`, `2x2I64` — the
# type appears by the same rule as for inputs, only when it isn't Float64.
outname(R::Type) = dims(R) * (eltype(R) === Float64 ? "" : abbrev(eltype(R)))

# The line that zeroes `out` of type `R`.
zeroing(R::Type) = "memset(out, 0, sizeof($(ctype(eltype(R)))$(join("[$n]" for n in shape(R)))));"

# The cross product. Only ever 3-vectors, but named like everything else: `cross_3_3`.
function crosshelper!(helpers::Dict{String, String}, types, R::Type)
    all(T -> shape(T) == (3,), types) || throw(ArgumentError("cross: both arguments must be 3-vectors"))
    name = helpername(:cross, types)
    if !haskey(helpers, name)
        (a, b), (an, bn) = types, inputs(types)
        helpers[name] = definition("void", name, [declare(a, an; constant=true), declare(b, bn; constant=true), declare(R, "out")],
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
        push!(params, declare(R, "out"))
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
        push!(params, declare(R, "out"))
        helpers[name] = definition("void", name, params, lines; doc=blockprose(kind, rows, types))
    end
    return name
end

# The shape a block construction produces: rows of blocks laid out as in Julia.
function catshape(rows, types)
    k = 1
    H = 0
    W = 0
    for nblocks in rows
        w = 0
        h = 0
        for _ in 1:nblocks
            bh, bw = extent(types[k], 1), extent(types[k], 2)
            h == 0 || h == bh || throw(ArgumentError("blocks in a row have different heights"))
            h = bh
            w += bw
            k += 1
        end
        W == 0 || W == w || throw(ArgumentError("rows have different widths"))
        W = w
        H += h
    end
    return (H, W)
end
