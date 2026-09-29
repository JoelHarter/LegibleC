# One array under two names.
#
# In C an array variable is its storage and its name in one: `double v[3];`. Julia's mutable
# arrays keep them apart: `m = v` is a second name for the same array, and a write through
# either is seen through both. `x, xnew = xnew, x` moves two names between two arrays and
# copies nothing. So an array variable is one of three kinds, decided here before any C is
# written:
#
#   storage       the only name for what it holds, which is almost every variable:
#                 `double v[3];`, as it always was
#   second name   given once, another variable's array: `double *const m = v;`
#   moving name   given other variables' arrays more than once, a swap:
#                 `double x_data[3];`, `double *x = x_data;` and then `x = xnew;`
#
# Indexing doesn't change: `m[i]` and `M[i][j]` read the same through a pointer. Parameters are
# pointers already, so two parameters swapped need no declaration at all.
#
# Only where it matters: a mutable array, and a write somewhere among the names. Where nothing
# is written a copy means the same thing, and an immutable array is a value in both languages.
#
# One case is refused, by line: a variable given a freshly made array while another name may
# still hold the one it had. C would write the new array over the old one's storage, which
# the other name still reads.

# The slot a statement's right side is, read directly or through a statement of its own.
function moved(sc::Scope, rhs)
    rhs isa Core.SSAValue && sc.ci.code[rhs.id] isa Core.SlotNumber && (rhs = sc.ci.code[rhs.id])
    return rhs isa Core.SlotNumber ? rhs.id : nothing
end

# The mutable struct variable whose array field a statement's right side reads, `h.v`, or nothing.
function fieldof(sc::Scope, rhs; mutable::Bool=true)
    rhs isa Core.SSAValue && (rhs = sc.ci.code[rhs.id])
    rhs isa Expr && rhs.head === :call && length(rhs.args) == 3 && callee_or_nothing(sc.ci, rhs.args[1]) in (Core.getfield, Base.getproperty) || return nothing
    s = moved(sc, rhs.args[2])
    return s !== nothing && isstruct(slottype(sc, s)) && ismutabletype(slottype(sc, s)) == mutable ? s : nothing
end

# A struct that isn't `mutable` is passed and copied by value in C, the arrays it holds with it.
# In Julia the array it holds is shared by every copy, so a write into it is seen by them all,
# the caller's included. Refused: there is no C for it short of another layout for the struct,
# and `mutable struct`, passed by pointer, says what is meant.
function frozen(sc::Scope, s, i)
    throw(ArgumentError("a write into an array that `$(sc.ci.slotnames[s])` holds, and `$(nameof(slottype(sc, s)))` is not `mutable`: C passes and copies such a struct by value, its arrays with it, so the write would reach one copy only, where in Julia every copy shares the array. Declare it `mutable struct $(nameof(slottype(sc, s)))`, which is passed by pointer (line $(sc.stmtline[i]))"))
end

function storage!(sc::Scope)
    ci = sc.ci
    code = ci.code
    mutable(s) = (T = ci.slottypes[s]; T isa Core.PartialStruct && (T = T.typ); T isa Type && isarray(widen(T)) && ismutabletype(widen(T)))
    stores(s) = [i for (i, st) in enumerate(code) if st isa Expr && st.head === :(=) && st.args[1] isa Core.SlotNumber && st.args[1].id == s && !(i in sc.gone)]
    # `m = h.v`, the array a mutable struct holds, and then a write through `m`: a second name for
    # the field, where a copy would lose the write.
    for (i, st) in enumerate(code)
        st isa Expr && st.head === :(=) && st.args[1] isa Core.SlotNumber && mutable(st.args[1].id) && st.args[1].id in sc.mutated && !(i in sc.gone) || continue
        (p = fieldof(sc, st.args[2]; mutable=false)) === nothing || frozen(sc, p, i)
        h = fieldof(sc, st.args[2])
        h === nothing && continue
        s = st.args[1].id
        length(stores(s)) == 1 ||
            throw(ArgumentError("`$(ci.slotnames[s])` is the array that `$(ci.slotnames[h])` holds at line $(sc.stmtline[i]), is written through, and is given another array elsewhere: give each a name of its own"))
        sc.second[s] = h
        sc.storage[sc.names[s]] = get(sc.storage, sc.names[h], sc.names[h])
    end
    fresh(i) = moved(sc, code[i].args[2]) === nothing
    # A parameter's working copy that is later given a freshly made array stays a copy, as it
    # was: `a = a .+ 1.0` and then `a[1] = 0.0` writes the new array, not the caller's.
    working(s) = haskey(sc.rebound, s) && any(fresh, stores(s))
    moves = [(i, st.args[1].id, moved(sc, st.args[2])) for (i, st) in enumerate(code) if st isa Expr && st.head === :(=) && st.args[1] isa Core.SlotNumber &&
             mutable(st.args[1].id) && moved(sc, st.args[2]) !== nothing && !(i in sc.gone) && !working(st.args[1].id)]
    isempty(moves) && return
    # The names that can come to hold one array: joined by every move between them.
    group = Dict{Int, Int}()
    find(s) = (while get(group, s, s) != s; s = group[s]; end; s)
    for (_, dst, src) in moves
        a, b = find(dst), find(src)
        group[max(a, b)] = min(a, b)
        get!(group, dst, find(dst))
        get!(group, src, find(src))
    end
    members = Dict{Int, Vector{Int}}()
    foreach(s -> push!(get!(members, find(s), Int[]), s), collect(keys(group)))
    inloop(i) = any(F -> F.start <= i < F.exit, values(sc.fors)) || any(W -> W.header <= i <= W.backedge, values(sc.whiles))
    for slots in values(members)
        any(s -> s in sc.mutated, slots) || continue              # nothing is written: a copy means the same
        union!(sc.mutated, slots)                                 # a write through one name is a write to what the others hold
        for s in sort(slots)
            s <= ci.nargs && continue                             # a parameter is a pointer as it stands
            at = stores(s)
            # A freshly made array has to be its first, given once and before any name can have moved:
            # the first store there is, and outside every loop.
            for i in at
                fresh(i) && !(i == first(at) && !inloop(i)) &&
                    throw(ArgumentError("`$(ci.slotnames[s])` is given a freshly made array at line $(sc.stmtline[i]) while another name may still hold the array it had: in Julia the two are then different arrays, and C has one storage for `$(ci.slotnames[s])`. Give the new array a name of its own"))
            end
            if haskey(sc.rebound, s)
                # A parameter's working copy that is only ever moved: the parameter itself, a pointer.
                sc.names[s] = sc.names[sc.rebound[s]]
                delete!(sc.rebound, s)
                push!(sc.moving, s)
            elseif all(fresh, at)
                continue                                          # storage, as it always was
            elseif length(at) == 1
                sc.second[s] = moved(sc, code[at[1]].args[2])
            else
                push!(sc.moving, s)
                fresh(first(at)) && (sc.data[s] = free(sc.names[s] * "_data", union(sc.names, sc.outer, values(sc.data))))
            end
        end
        # Any of them may hold the same array as any other.
        foreach(s -> sc.storage[sc.names[s]] = sc.names[minimum(slots)], slots)
    end
end

# The declaration of a pointer to an array's elements: `double *m`, `double (*M)[3]`.
function pointer(T::Type, name::AbstractString; constant::Bool=false)
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    inner = (constant ? "*const " : "*") * name
    return ctype(eltype(T)) * " " * (length(s) == 1 ? inner : "($inner)" * join("[$n]" for n in s[2:end]))
end

# Is this slot a name for an array and not the array's storage?
named(sc::Scope, s) = s in sc.moving || haskey(sc.second, s)

# The storage a C name may hold: its own, or the one name that stands for every name that can
# come to hold the same array.
held(sc::Scope, name::AbstractString) = (m = match(r"^\w+", name); m === nothing ? String(name) : get(sc.storage, m.match, String(m.match)))

"""
    name!(lines, sc, i, slot, rhs, here)

The statement `slot = rhs` for a second or a moving name. Given another name, it is a
pointer's initialiser or a pointer's assignment. Given a freshly made array, which is its
first, the array is built in the storage the name starts out with, `x_data`.
"""
function name!(lines, sc::Scope, i, slot, rhs, here::Bool)
    x = sc.names[slot]
    push!(sc.pointers, x)
    if fieldof(sc, rhs) !== nothing && haskey(sc.second, slot)
        st = rhs isa Core.SSAValue ? sc.ci.code[rhs.id] : rhs
        V = rhs isa Core.SSAValue ? valuetype(sc, rhs) : widen(sc.ci.ssavaluetypes[i])
        emit!(lines, sc, here ? "$(pointer(V, x; constant=true)) = $(fieldaccess(sc, st.args[2], st.args[3]));" : "$x = $(fieldaccess(sc, st.args[2], st.args[3]));")
        return slotshape!(sc, slot, V)
    end
    if moved(sc, rhs) === nothing
        here || return store!(lines, sc, i, x, rhs)             # declared above the construct this is in, with its storage
        # The array is built in its own storage, as any array is, and then the name is given it:
        # `double x_data[3] = {1.0, 2.0, 3.0};` and `double *x = x_data;`.
        store!(lines, sc, i, sc.data[slot], rhs; declaration=true)
        return emit!(lines, sc, "$(pointer(slottype(sc, slot), x)) = $(sc.data[slot]);")
    end
    V = slottype(sc, moved(sc, rhs))              # the variable's type carries the size of a regular array; a read of it may not
    emit!(lines, sc, here ? "$(pointer(V, x; constant=haskey(sc.second, slot))) = $(value(sc, rhs));" : "$x = $(value(sc, rhs));")
    slotshape!(sc, slot, V)
end

# `double x_data[3], *x = x_data`: storage, and the name that starts out holding it.
function datadecl(sc::Scope, slot)
    T = slottype(sc, slot)
    return declare(T, sc.data[slot]) * ", " * replace(pointer(T, sc.names[slot]), r"^\S+ " => "") * " = " * sc.data[slot]
end

# A name's value kept past the name's next move, `x, xnew = xnew, x`: the pointer, not a copy.
function keep!(lines, sc::Scope, t, x, T::Type)
    emit!(lines, sc, "$(pointer(T, t)) = $x;")
    push!(sc.pointers, t)
    sc.storage[t] = held(sc, x)
end
