# Linear algebra helpers: one C function per (operation, argument types), generated on
# demand while a function is being emitted and written out once, ahead of everything
# that calls them.
#
# Arrays in C are fixed-size and row-major, passed as array parameters so the compiler
# knows their shape (`const double a[2][2]`), and every helper writes its output into
# its last parameter — except the ones whose result is a scalar, which return it.
#
# Every generator here is written once for the general case. An operand is described
# by its logical shape (`bshape`: a vector is N×1, a row 1×N, a scalar 1×1) and by
# which of those dimensions it stores (`stored`); `access` turns that into the right C
# subscript for any of them. Loops run over logical dimensions and skip any of
# extent 1. So one `contraction` covers every kind of `*`, one broadcast body covers
# every combination of shapes, and one block-placement loop covers every block.

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
    helpername(op, types; broadcast=false) -> String

The C name of the helper for `op` on `types`. Names always carry size and type; the
full rules, with examples, are in `doc/array.md`. In short: an array is described by
its dimensions (`2x2`, or `r3` for a row vector), a scalar by `s`; fundamental types
appear only when not every input is `Float64`, and then on every input — appended to
an array's dimensions, replacing a scalar's `s`. Identical descriptions are written
once.

A broadcast operation gets `E` (element-wise) if every input has the same size, with
that size written once and the types, if needed, run together after it in input
order; otherwise `B` (broadcast), with every input listed.
"""
function helpername(op::Symbol, types; broadcast::Bool=false)
    fundamental(T) = T <: AbstractArray ? eltype(T) : T
    alldouble = all(T -> fundamental(T) === Float64, types)
    sizes = [T <: AbstractArray ? dims(T) : "s" for T in types]
    typs = [abbrev(fundamental(T)) for T in types]
    if broadcast && allequal(sizes)
        ts = alldouble ? "" : allequal(typs) ? typs[1] : join(typs)
        return string(op, "E_", sizes[1], ts)
    end
    descs = [alldouble ? sz : (T <: AbstractArray ? sz * t : t) for (T, sz, t) in zip(types, sizes, typs)]
    !broadcast && allequal(descs) && (descs = descs[1:1])
    return string(op, broadcast ? "B_" : "_", join(descs, "_"))
end

# The C definition of one helper.
function helpercode(name::AbstractString, op::Symbol, types, R::Type)
    argnames = ["a", "b"][1:length(types)]
    params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
    push!(params, declare(R, "out"))
    body = if op in (:add, :sub)
        a, b = types
        shape(a) == shape(b) || throw(ArgumentError("$op: dimensions don't match, $(dims(a)) and $(dims(b))"))
        elementwise(shape(R), idx -> "out$(brackets(idx)) = a$(brackets(idx)) $(op == :add ? "+" : "-") b$(brackets(idx));")
    elseif op == :neg
        elementwise(shape(R), idx -> "out$(brackets(idx)) = -a$(brackets(idx));")
    elseif op == :copy
        elementwise(shape(R), idx -> "out$(brackets(idx)) = a$(brackets(idx));")
    elseif op == :mul && !all(T -> T <: AbstractArray, types)
        # A scalar times an array: elementwise, whichever side the scalar is on.
        a, b = types
        elementwise(shape(R), idx -> "out$(brackets(idx)) = $(access(a, "a", idx)) * $(access(b, "b", idx));")
    elseif op == :mul
        contraction(types..., R, eltype(R))
    else
        throw(ArgumentError("unsupported array operation: $op"))
    end
    return definition("void", name, params, body)
end

# ---- the primitives every generator is built from ----------------------------------

# A helper's full C definition: `body` lines are relative to the function's own indent.
definition(ret, name, params, body) = "static $ret $name($(join(params, ", "))) {\n" * join("    " .* body, "\n") * "\n}\n"

# The (index name, extent) pairs that need a loop: those with more than one element.
live(pairs) = [p for p in pairs if p[2] > 1]

# Loop index names: `i`, `j`, `k` for up to three nested loops; past three, `i1`,
# `i2`, `i3`, … throughout, so a reader never has to wonder what comes after `k`.
indices(n::Integer) = n <= 3 ? ["i", "j", "k"][1:n] : ["i$d" for d in 1:n]

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
function loopindices(shape)
    looped = [d for d in eachindex(shape) if shape[d] > 1]
    names = indices(length(looped))
    idx = [shape[d] > 1 ? names[findfirst(==(d), looped)] : "0" for d in eachindex(shape)]
    return idx, [(names[p], shape[d]) for (p, d) in enumerate(looped)]
end

# Nested loops over every element of `shape`, with `line(idx)` innermost, where `idx`
# is one index expression per dimension.
function elementwise(shape, line::Function; indent="    ")
    idx, pairs = loopindices(shape)
    return nest(pairs, [line(idx)]; indent)
end

brackets(idx) = join("[$x]" for x in idx)

# The C subscript for element `idx` (one expression per *logical* dimension) of `var`
# of type `T`: nothing for a scalar, and for an array only the dimensions it stores,
# with `0` wherever its own extent is 1.
function access(T::Type, var::AbstractString, idx)
    T <: AbstractArray || return var
    s = bshape(T)
    ext(d) = d <= length(s) ? s[d] : 1
    return var * join("[" * (ext(d) == 1 ? "0" : idx[d]) * "]" for d in stored(T))
end

# ---- multiplication ---------------------------------------------------------------

# The one body for every `*` of two arrays: `out(i,j) = Σ_k a(i,k) b(k,j)` over the
# operands' logical shapes. That is matrix×matrix, matrix×vector, row×matrix,
# column×row (the outer product), and row×column (a scalar, returned when `R` is
# nothing) with no special cases — only the loops that have anything to loop over.
# Loop order is i-k-j: the inner loop walks a row of `out` and a row of `b`, both
# contiguous in row-major storage.
function contraction(a::Type, b::Type, R, E::Type)
    (m, K) = bshape(a)
    (K2, n) = bshape(b)
    K == K2 || throw(ArgumentError("mul: dimensions don't match, $(dims(a)) and $(dims(b))"))
    zero = ctype(E) == "float" ? "0.0f" : E <: AbstractFloat ? "0.0" : "0"
    i, j, k = m > 1 ? "i" : "0", n > 1 ? "j" : "0", K > 1 ? "k" : "0"
    term = "$(access(a, "a", [i, k])) * $(access(b, "b", [k, j]))"
    if R === nothing
        return ["$(ctype(E)) sum = $zero;"; nest(live([("k", K)]), ["sum += $term;"]); "return sum;"]
    end
    out = access(R, "out", [i, j])
    K == 1 && return nest(live([("i", m), ("j", n)]), ["$out = $term;"])
    return nest(live([("i", m)]), [nest(live([("j", n)]), ["$out = $zero;"]);
                                    nest(live([("k", K), ("j", n)]), ["$out += $term;"])])
end

# The type of the result of `op` on `types`, with element type `E`. Nothing for a
# scalar (a row times a column). The kind of array follows Julia: a row times a
# matrix is a row, a matrix times a vector is a vector, everything else a matrix.
function resulttype(op::Symbol, types, E::Type)
    arrays = [T for T in types if T <: AbstractArray]
    op == :mul && length(arrays) == 2 || return retype(arrays[1], E)
    a, b = types
    (m, K) = bshape(a)
    (K2, n) = bshape(b)
    K == K2 || throw(ArgumentError("mul: dimensions don't match, $(dims(a)) and $(dims(b))"))
    isrow(a) && !isrow(b) && ndims(b) == 1 && return nothing
    isrow(a) && return Row{E, n}
    ndims(a) == 2 && ndims(b) == 1 && !isrow(b) && return shaped(E, (m,))
    return shaped(E, (m, n))
end

# The same array type with element type `E`.
retype(T::Type, E::Type) = isrow(T) ? Row{E, shape(T)[1]} : shaped(E, shape(T))

# A helper that returns a scalar: `dot_3`, or `mul_r3_3` for a row times a column.
# Both are the contraction of a 1×N with an N×1.
function scalarhelper!(helpers::Dict{String, String}, op::Symbol, types, E::Type)
    name = helpername(op, types)
    if !haskey(helpers, name)
        a, b = types
        row = isrow(a) ? a : Row{eltype(a), shape(a)[1]}
        body = contraction(row, b, nothing, E)
        helpers[name] = definition(ctype(E), name, [declare(a, "a"; constant=true), declare(b, "b"; constant=true)], body)
    end
    return name
end

# ---- the rest ----------------------------------------------------------------------

# The helper that fills an array of type `R` with one value: `fill_3`, `fill_2x2`. Named
# by what it makes, since the value is a scalar and the array is the output.
function fillhelper!(helpers::Dict{String, String}, R::Type)
    name = "fill_" * dims(R)
    if !haskey(helpers, name)
        body = elementwise(shape(R), idx -> "out$(brackets(idx)) = x;")
        helpers[name] = definition("void", name, ["$(ctype(eltype(R))) x", declare(R, "out")], body)
    end
    return name
end

# The cross product: always 3-vectors, so no size in the name — only a type when it
# isn't Float64.
function crosshelper!(helpers::Dict{String, String}, types, R::Type)
    all(T -> shape(T) == (3,), types) || throw(ArgumentError("cross: both arguments must be 3-vectors"))
    alldouble = all(T -> eltype(T) === Float64, types)
    name = "cross" * (alldouble ? "" : "_" * (allequal(abbrev.(eltype.(types))) ? abbrev(eltype(types[1])) : join("_" .* abbrev.(eltype.(types)))))
    if !haskey(helpers, name)
        a, b = types
        helpers[name] = definition("void", name, [declare(a, "a"; constant=true), declare(b, "b"; constant=true), declare(R, "out")],
                                   ["out[0] = a[1] * b[2] - a[2] * b[1];", "out[1] = a[2] * b[0] - a[0] * b[2];", "out[2] = a[0] * b[1] - a[1] * b[0];"])
    end
    return name
end

# The transpose of a matrix.
function transposehelper!(helpers::Dict{String, String}, T::Type, R::Type)
    name = helpername(:transpose, (T,))
    if !haskey(helpers, name)
        body = elementwise(shape(R), idx -> "out$(brackets(idx)) = a$(brackets(reverse(idx)));")
        helpers[name] = definition("void", name, [declare(T, "a"; constant=true), declare(R, "out")], body)
    end
    return name
end

# A broadcast: `f` applied elementwise over `types`, with Julia's rules — dimensions
# line up from the left, and a size of 1 (or a missing dimension) stretches to match.
# `access` does the stretching: an argument's extent-1 dimensions are indexed by 0.
function broadcasthelper!(helpers::Dict{String, String}, op::Symbol, cfn, types, R::Type)
    name = helpername(op, types; broadcast=true)
    if !haskey(helpers, name)
        idx, pairs = loopindices(bshape(R))
        argnames = ["a", "b"][1:length(types)]
        accesses = [access(T, n, idx) for (T, n) in zip(types, argnames)]
        expr = cfn isa String ? "$cfn($(join(accesses, ", ")))" :
               cfn == :neg ? "-" * accesses[1] :
               cfn == :div && all(T -> (T <: AbstractArray ? eltype(T) : T) <: Integer, types) ?
                   "($(ctype(eltype(R))))$(accesses[1]) / ($(ctype(eltype(R))))$(accesses[2])" :
               join(accesses, " " * Dict(:add => "+", :sub => "-", :mul => "*", :div => "/")[cfn] * " ")
        body = nest(pairs, ["$(access(R, "out", idx)) = $expr;"])
        params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
        push!(params, declare(R, "out"))
        helpers[name] = definition("void", name, params, body)
    end
    return name
end

# The shape of a broadcast over `types`, as a full logical shape, or nothing if it's
# invalid.
function broadcastshape(types)
    shapes = [bshape(T) for T in types]
    nd = maximum(length, shapes)
    out = Int[]
    for d in 1:nd
        sizes = unique([length(s) >= d ? s[d] : 1 for s in shapes])
        big = filter(!=(1), sizes)
        length(big) <= 1 || return nothing
        push!(out, isempty(big) ? 1 : big[1])
    end
    return Tuple(out)
end

# Block construction: `[A B; C D]` (`rows` gives the blocks per row), `[u; v]`, `[u v]`.
# Every input is listed in the name — the number of blocks matters. Each block is
# copied into place by one loop over its logical shape; a scalar is a 1×1 block.
function cathelper!(helpers::Dict{String, String}, kind::Symbol, rows, types, R::Type)
    descs = [T <: AbstractArray ? dims(T) : abbrev(T) for T in types]
    name = (kind == :hvcat ? "hvcat" * join(rows, "x") : string(kind)) * "_" * join(descs, "_")
    if !haskey(helpers, name)
        argnames = ["b$k" for k in 1:length(types)]
        lines = String[]
        offset(base, x) = x == "0" ? string(base) : base == 0 ? x : "$base + $x"
        r0 = 0
        k = 1
        for nblocks in rows
            c0 = 0
            height = 0
            for _ in 1:nblocks
                T = types[k]
                (h, w) = bshape(T)
                height == 0 || height == h || throw(ArgumentError("$kind: blocks in a row have different heights"))
                height = h
                i, j = h > 1 ? "i" : "0", w > 1 ? "j" : "0"
                inner = "$(access(R, "out", [offset(r0, i), offset(c0, j)])) = $(access(T, argnames[k], [i, j]));"
                append!(lines, nest(live([("i", h), ("j", w)]), [inner]))
                c0 += w
                k += 1
            end
            r0 += height
        end
        params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
        push!(params, declare(R, "out"))
        helpers[name] = definition("void", name, params, lines)
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
            (bh, bw) = bshape(types[k])
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
