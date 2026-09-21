# How Julia groups a product of several factors, and a power of a matrix.
#
# `A * B * v` is `A * (B * v)` in Julia. Three matrices are grouped by which order costs
# less, four by the cheapest of five, a row in front is multiplied in first, a number is
# folded in at the end, and `A^5` is `A * ((A * A) * (A * A))`. The grouping decides the
# rounding, and with mixed precision more than the rounding; it is also the cheapest order,
# so it is what the C should do for speed alone. The rules are Julia's and differ a little
# from one Julia to the next, so they are not copied here. Julia is asked: the product is
# run on stand-ins that compute nothing and remember what was multiplied with what.

# A stand-in for an array factor: its size, and either its place among the operands or the
# two things it is the product of. Mutable, so that one made once and used twice (the `A * A`
# inside `A^4`) is one object, and is computed once in the C.
mutable struct Factor{N} <: AbstractArray{Float64, N}
    size::NTuple{N, Int}
    parts::Any
end
Base.size(f::Factor) = f.size
Base.getindex(::Factor, i...) = error("a stand-in has no elements")     # whatever looks inside fails, and the fold from the left is used

# A stand-in for a number among the factors, or for a row times a column.
struct Weight <: Real
    parts::Any
end

let mats = (:(Factor{2}), :(LinearAlgebra.Adjoint{Float64, Factor{2}}), :(LinearAlgebra.Transpose{Float64, Factor{2}})),
    rows = (:(LinearAlgebra.Adjoint{Float64, Factor{1}}), :(LinearAlgebra.Transpose{Float64, Factor{1}}))
    for L in mats, R in mats
        @eval Base.:*(a::$L, b::$R) = Factor{2}((size(a, 1), size(b, 2)), (a, b))
    end
    for L in mats
        @eval Base.:*(a::$L, b::Factor{1}) = Factor{1}((size(a, 1),), (a, b))
    end
    for W in rows, R in mats
        @eval Base.:*(a::$W, b::$R) = adjoint(Factor{1}((size(b, 2),), (a, b)))       # a row again
    end
    for W in rows
        @eval Base.:*(a::$W, b::Factor{1}) = Weight((a, b))                           # a row times a column: a number
        @eval Base.:*(a::Factor{1}, b::$W) = Factor{2}((length(a), length(b)), (a, b))
    end
    for X in (mats..., rows..., :(Factor{1}))
        @eval Base.:*(s::Weight, a::$X) = like(a, (s, a))
        @eval Base.:*(a::$X, s::Weight) = like(a, (a, s))
    end
end
Base.:*(s::Weight, t::Weight) = Weight((s, t))
like(a::Factor{N}, parts) where {N} = Factor{N}(a.size, parts)
like(a::LinearAlgebra.Adjoint, parts) = adjoint(like(parent(a), parts))
like(a::LinearAlgebra.Transpose, parts) = transpose(like(parent(a), parts))

unwrapped(x) = x isa Union{LinearAlgebra.Adjoint, LinearAlgebra.Transpose} ? parent(x) : x

# The stand-in for operand `k`, of the type the transpiler holds it as: a number, a column,
# a row, a matrix. A matrix is wrapped as an adjoint only where Julia's own value is one
# (a static matrix's adjoint is made at once and is a plain matrix to Julia).
function standin(T::Type, k::Int)
    isarray(T) || return T <: Real || T <: Complex ? Weight(k) : nothing
    ndims(T) <= 2 || return nothing
    if isrow(T)
        v = Factor{1}((extent(T, 2),), k)
        return isconjugated(T) ? adjoint(v) : transpose(v)
    end
    ndims(T) == 1 && return Factor{1}((extent(T, 1),), k)
    J = juliatype(T)
    m = J <: LinearAlgebra.Adjoint ? adjoint(Factor{2}((extent(T, 2), extent(T, 1)), k)) :
        J <: LinearAlgebra.Transpose ? transpose(Factor{2}((extent(T, 2), extent(T, 1)), k)) : Factor{2}((extent(T, 1), extent(T, 2)), k)
    return m
end

"""
    grouping(types) -> the product as Julia groups it, or `nothing`

`types` are the operands' types. The result is a stand-in whose `parts` say what was
multiplied with what, down to the operands' places. `nothing` when Julia's own method looks
inside its arguments (a broadcast, say) or an operand is no plain number or array: the
caller then folds from the left, which is what Julia does where it has no rule of its own.
"""
function grouping(types)
    leaves = [standin(T, k) for (k, T) in enumerate(types)]
    any(isnothing, leaves) && return nothing
    return try *(leaves...) catch; nothing end
end

# `A^p` for a literal `p`: the sequence of squarings and products Julia's own power makes.
power(T::Type, p::Integer) = p >= 1 && isarray(T) && ndims(T) == 2 ? (try Base.power_by_squaring(standin(T, 1), p) catch; nothing end) : nothing

"""
    product!(lines, sc, i, args, node, dest; declaration) -> (type, C text)

Write the product `node` stands for, innermost first: each product of two into a temp, the
last into `dest`. A row times a column is a number, written where it is used. With `dest`
nothing the whole product is a number, and its text is returned for the caller to write.
"""
function product!(lines, sc::Scope, i, args, node, dest; declaration::Bool=false, done=IdDict{Any, Any}(), root::Bool=true)
    x = unwrapped(node)
    if x.parts isa Int
        a = args[x.parts]
        others = [valuetype(sc, b) for b in args if isarray(valuetype(sc, b))]
        return coefficient(sc, a, isempty(others) ? Float64 : first(others))
    end
    haskey(done, x) && return done[x]
    l, r = x.parts
    lt, ln = product!(lines, sc, i, args, l, nothing; done, root=false)
    rt, rn = product!(lines, sc, i, args, r, nothing; done, root=false)
    elt(X) = X <: AbstractArray ? eltype(X) : X
    E = promote_type(elt(lt), elt(rt))
    if !isarray(lt) && !isarray(rt)
        return done[x] = (E, "$ln * $rn")
    end
    R = resulttype(:mul, (lt, rt), E)
    if R === nothing                       # a row times a column
        push!(sc.headers, "math.h")
        return done[x] = (E, "$(scalarhelper!(sc.helpers, :mul, (lt, rt), E))($ln, $rn)")
    end
    # A temp is named after what went into it, as every temp is: `temp1_A_B`.
    under(n) = (n = unwrapped(n); n.parts isa Int ? contribution(sc, args[n.parts]) : [under(n.parts[1]); under(n.parts[2])])
    out = root && dest !== nothing ? dest : temp!(sc, nothing, unique(under(x)))
    (root && dest !== nothing ? declaration : true) && emit!(lines, sc, declare(R, out) * ";")
    emit!(lines, sc, "$(helper!(sc.helpers, :mul, (lt, rt), R))($ln, $rn, $out);")
    step!(lines, sc, "$out = $(spell(lt, ln)) * $(spell(rt, rn))")
    return done[x] = (R, out)
end

# One operand as (type, C text). An integer literal beside a floating array takes the array's
# element type: `-3A` is `mul_s_2x2(-3.0, A, out)`, not a helper of mixed types and an `int64_t`.
function coefficient(sc::Scope, x, other)
    x isa Integer && isarray(other) && eltype(other) <: AbstractFloat && return eltype(other), value(sc, eltype(other)(x))
    x isa Integer && isarray(other) && eltype(other) <: Complex && return real(eltype(other)), value(sc, real(eltype(other))(x))   # `2y` on complex: a real 2.0
    return valuetype(sc, x), value(sc, x)
end

# Is this a product of several factors, arrays among them? Such a product is written over
# several lines, so it is never written inside another expression.
manyfactors(sc::Scope, st) = st isa Expr && st.head === :call && length(st.args) >= 4 && callee_or_nothing(sc.ci, st.args[1]) === Base.:* &&
                             any(a -> isarray(valuetype(sc, a)), st.args[2:end])
