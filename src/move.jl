# Moving data — copies, block construction, slices and slice assignment, zeroing and
# filling — is written inline, where it happens, the way a C programmer writes it:
# `memcpy` for a contiguous run, `memset` to zero, a loop otherwise. A helper is for
# computation; none of this earns a name of its own, and the source line above it says
# what it is. One primitive, `move!`, does all of it.

# One movement. For every element of a shape — `extents[a]` along axis `a`, with a loop
# only where that's more than 1 — the element of `src` at `ssub` goes to the element of
# `dst` at `dsub`. A side's subscripts are one per storage dimension, each `(offset,
# axis)`: `offset` is a C expression to which the loop index of `axis` is added, or the
# whole subscript when `axis` is 0; an `offset` with `#` in it is the subscript with the
# loop index in place of the `#` — `idx[#] - 1`, a gather through an index array. A
# scalar side has no subscripts. The run along the last looped axis goes through
# `memcpy` when it is contiguous on both sides — that axis is the last storage
# dimension of each, and neither gathers along it.
function move!(lines, sc::Scope, E::Type, dst, dsub, src, ssub, extents; conj::Bool=false)
    pairs, inner = movement(sc, E, dst, dsub, src, ssub, extents; conj)
    for line in nest(pairs, inner)
        emit!(lines, sc, line)
    end
end

# The loops (as index-extent pairs) and the innermost line of one movement, so that
# movements sharing the same loops can be written inside one nest.
# With `conj`, each element is conjugated on the way: an adjoint's storage made plain.
function movement(sc::Scope, E::Type, dst, dsub, src, ssub, extents; conj::Bool=false)
    looped = [a for a in eachindex(extents) if extents[a] > 1]
    vars = Dict(zip(looped, indices(length(looped); taken=union(sc.names, sc.outer))))
    sub(off, a) = a == 0 ? off : occursin("#", off) ? replace(off, "#" => get(vars, a, "0")) :
                  !haskey(vars, a) ? off : off == "0" ? vars[a] : "$off + $(vars[a])"
    at(name, subs) = name * join("[$(sub(o, a))]" for (o, a) in subs)
    run = isempty(looped) ? 0 : looped[end]
    if !conj && run != 0 && !isempty(dsub) && !isempty(ssub) && dsub[end][2] == run && ssub[end][2] == run &&
       !occursin("#", dsub[end][1]) && !occursin("#", ssub[end][1])
        # The start of the run on each side: a whole row is the row itself.
        start(name, subs) = subs[end][1] == "0" ? at(name, subs[1:end-1]) : "&" * at(name, subs[1:end-1]) * "[$(subs[end][1])]"
        inner = ["memcpy($(start(dst, dsub)), $(start(src, ssub)), sizeof($(ctype(E))[$(extents[run])]));"]
        pairs = [(vars[a], extents[a]) for a in looped[1:end-1]]
        push!(sc.headers, "string.h")
    else
        inner = ["$(at(dst, dsub)) = $(conj ? "$(mathname(E, "conj"))($(at(src, ssub)))" : at(src, ssub));"]
        pairs = [(vars[a], extents[a]) for a in looped]
    end
    return pairs, inner
end

# The subscripts of a whole array of type `T`: each storage dimension on its axis.
whole(T::Type) = [("0", a) for a in axis(T)]

# The C spelling of an array type's size, for `sizeof`.
sizeof_(T::Type) = ctype(eltype(T)) * join("[$n]" for n in shape(T))

# `dst = src`, both of one logical shape; `S` may be transposed relative to `D`. One
# `memcpy` when the storage lines up, a loop through the axes otherwise.
function copy!(lines, sc::Scope, src, S::Type, dst, D::Type)
    if axis(S) == axis(D)
        push!(sc.headers, "string.h")
        # `sizeof src` when the source is a whole local array; a parameter has decayed
        # to a pointer, so its type is spelled out.
        size = occursin(r"^\w+$", src) && !(src in sc.names[2:sc.ci.nargs]) && !(src in sc.pointers) ? "sizeof $src" : "sizeof($(sizeof_(D)))"
        emit!(lines, sc, "memcpy($dst, $src, $size);")
    else
        move!(lines, sc, eltype(D), dst, whole(D), src, whole(S), [extent(D, a) for a in 1:maximum(axis(D))]; conj=isconjugated(S) && !isconjugated(D))
    end
end

# `dst .= 0`: one `memset`. All-zero bytes are zero in every type emitted here.
function zero!(lines, sc::Scope, dst, D::Type)
    push!(sc.headers, "string.h")
    emit!(lines, sc, "memset($dst, 0, sizeof($(sizeof_(D))));")
end

# `dst .= x`: a loop.
fill!(lines, sc::Scope, dst, D::Type, x) = move!(lines, sc, eltype(D), dst, whole(D), x, [], [extent(D, a) for a in 1:ndims(D)])

# `dst = I`: zero, then ones down the diagonal — `min(m, n)` of them if it isn't square.
function identity!(lines, sc::Scope, dst, D::Type; diagonal=nothing)
    zero!(lines, sc, dst, D)
    one = diagonal !== nothing ? diagonal : eltype(D) <: AbstractFloat ? (eltype(D) === Float32 ? "1.0f" : "1.0") : "1"
    d = minimum(shape(D))
    i = indices(1; taken=union(sc.names, sc.outer))[1]
    for line in nest(live([(i, d)]), ["$dst[$(d > 1 ? i : "0")][$(d > 1 ? i : "0")] = $one;"])
        emit!(lines, sc, line)
    end
end

# ---- block construction ------------------------------------------------------------

# A block construction is a tree: a block, or the concatenation of subtrees along one
# dimension. `[A B; C D]` is the concatenation along 1 of two concatenations along 2;
# `[A; B;; C; D]` the concatenation along 2 of two along 1; `;;;` adds a level. Each
# subtree's pieces only have to agree in the dimensions it doesn't join along, which is
# how `[A; B;; B; A]` with a scalar `A` and a 2-vector `B` is a 3×2. `layout` gives the
# shape of the whole and, for every block, where it lands.
function layout(node, types)
    if node isa Integer
        T = types[node]
        n = isarray(T) ? maximum(axis(T)) : 0
        return [extent(T, a) for a in 1:n], [(node, zeros(Int, n))]
    end
    d, children = node
    parts = [layout(c, types) for c in children]
    N = max(d, maximum(length(p[1]) for p in parts))
    pad(v) = [v; ones(Int, N - length(v))]
    shapes = [pad(p[1]) for p in parts]
    for s in shapes, e in 1:N
        e == d || s[e] == shapes[1][e] || throw(ArgumentError("blocks don't line up along dimension $e: $(join(("$(describe(types[b])) " for (b, _) in reduce(vcat, (p[2] for p in parts))), ", "))"))
    end
    shape = copy(shapes[1])
    shape[d] = sum(s[d] for s in shapes)
    places = Tuple{Int, Vector{Int}}[]
    o = 0
    for (p, s) in zip(parts, shapes)
        for (b, off) in p[2]
            off = [off; zeros(Int, N - length(off))]
            off[d] += o
            push!(places, (b, off))
        end
        o += s[d]
    end
    return shape, places
end

# The tree for `hvncat(dims, rowfirst, …)`: the blocks grouped `dims[1]` at a time along
# dimension 1, those groups `dims[2]` at a time along 2, and so on — with the first two
# dimensions swapped when the blocks were listed row by row.
function grouped(dims, rowfirst, blocks)
    order = rowfirst && length(dims) >= 2 ? [2, 1, 3:length(dims)...] : collect(1:length(dims))
    nodes = Any[blocks...]
    for d in order
        n = dims[d]
        length(nodes) % n == 0 || throw(ArgumentError("[;;] needs $(prod(dims)) blocks, got $(length(blocks))"))
        nodes = Any[(d, nodes[k:k+n-1]) for k in 1:n:length(nodes)]
    end
    return only(nodes)
end

# Build the construction whose tree is `tree` into `dst` of type `R`: every block moved
# into place at its offsets.
function construct!(lines, sc::Scope, tree, blocks, dst, R::Type)
    types = [valuetype(sc, b) for b in blocks]
    _, places = layout(tree, types)
    N = ndims(R)
    # Blocks that take the same loops — the four of `[A B; C D]` — share one nest, as
    # a person would write them.
    groups = Pair{Vector, Vector{String}}[]
    for (b, off) in places
        S = types[b]
        off = [off; zeros(Int, N - length(off))]
        # A block that lives at this very place in `out` already (`outplacement!`).
        dst == sc.resultname && all(==(0), off[2:end]) && outplacedat(sc, blocks[b], off[1]) && continue
        dsub = [(string(off[j]), j) for j in 1:N]
        extents = [isarray(S) ? extent(S, a) : 1 for a in 1:N]
        pairs, inner = movement(sc, eltype(R), dst, dsub, value(sc, blocks[b]), isarray(S) ? whole(S) : [], extents; conj=isarray(S) && isconjugated(S))
        !isempty(groups) && groups[end].first == pairs ? append!(groups[end].second, inner) : push!(groups, pairs => inner)
    end
    for (pairs, inner) in groups, line in nest(pairs, inner)
        emit!(lines, sc, line)
    end
end

# ---- slices ------------------------------------------------------------------------

# `A[i, :]`, `A[:, j]`, `A[1:2, 2:3]`, `v[2:4]`, `A[2:end, [1, 3]]`, in any dimension: a
# copy, as in Julia, into `dst`. `spans` gives each index of `A` as `(offset, extent,
# scalar, list)` (see `span`); the non-scalar ones are the dimensions the result has.
function slice!(lines, sc::Scope, src, S::Type, spans, dst, D::Type)
    groups = Pair{Vector, Vector{String}}[]
    gather!(groups, sc, src, S, spans, dst, D, fill("0", ndims(D)))
    for (pairs, inner) in groups, line in nest(pairs, inner)
        emit!(lines, sc, line)
    end
end

# The movements of a slice, grouped by the loops they share. A list of indices written
# out, `[1, 3]`, is one movement per listed index — the slice at that index, landing at
# its place in `dst`, `doff` being the offset along each storage dimension of `dst` —
# and those taking the same loops are written in one nest, as a person would. A list
# held at run time is a loop over it, reading through `idx[j] - 1`.
function gather!(groups, sc::Scope, src, S::Type, spans, dst, D::Type, doff)
    spanned = [d for d in eachindex(spans) if !spans[d].scalar]
    k = findfirst(d -> spans[d].list isa AbstractVector, eachindex(spans))
    if k !== nothing
        j = findfirst(j -> spanned[axis(D)[j]] == k, 1:ndims(D))
        for (n, o) in enumerate(spans[k].list)
            each = copy(spans)
            each[k] = (offset=string(o), extent=1, scalar=false, list=nothing)
            off = copy(doff)
            off[j] = string(n - 1)
            gather!(groups, sc, src, S, each, dst, D, off)
        end
        return
    end
    ssub = [(spans[a].list === nothing ? spans[a].offset : "$(spans[a].list)[#] - 1", spans[a].scalar ? 0 : a) for a in axis(S)]
    dsub = [(doff[j], spanned[axis(D)[j]]) for j in 1:ndims(D)]
    pairs, inner = movement(sc, eltype(D), dst, dsub, src, ssub, [s.extent for s in spans])
    !isempty(groups) && groups[end].first == pairs ? append!(groups[end].second, inner) : push!(groups, pairs => inner)
end

# `A[i, :] = v`, `A[:, 3:4] = B`, `v[2:3] = w`, `A[:, [1, 3]] = B`: the same, the other
# way round.
function setslice!(lines, sc::Scope, dst, D::Type, spans, src, S::Type)
    groups = Pair{Vector, Vector{String}}[]
    scatter!(groups, sc, dst, D, spans, src, S, fill("0", isarray(S) ? ndims(S) : 0))
    for (pairs, inner) in groups, line in nest(pairs, inner)
        emit!(lines, sc, line)
    end
end

function scatter!(groups, sc::Scope, dst, D::Type, spans, src, S::Type, soff)
    spanned = [d for d in eachindex(spans) if !spans[d].scalar]
    k = findfirst(d -> spans[d].list isa AbstractVector, eachindex(spans))
    if k !== nothing
        j = isarray(S) ? findfirst(j -> spanned[axis(S)[j]] == k, 1:ndims(S)) : nothing
        for (n, o) in enumerate(spans[k].list)
            each = copy(spans)
            each[k] = (offset=string(o), extent=1, scalar=false, list=nothing)
            off = copy(soff)
            j === nothing || (off[j] = string(n - 1))
            scatter!(groups, sc, dst, D, each, src, S, off)
        end
        return
    end
    dsub = [(spans[a].list === nothing ? spans[a].offset : "$(spans[a].list)[#] - 1", spans[a].scalar ? 0 : a) for a in axis(D)]
    ssub = isarray(S) ? [(soff[j], spanned[axis(S)[j]]) for j in 1:ndims(S)] : []
    pairs, inner = movement(sc, eltype(D), dst, dsub, src, ssub, [s.extent for s in spans])
    !isempty(groups) && groups[end].first == pairs ? append!(groups[end].second, inner) : push!(groups, pairs => inner)
end
