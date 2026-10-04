# A function as a value. In Julia every function has a type of its own, so a function handed
# to another, `newton(f, df, x)`, is known when transpiled: Julia compiles a `newton` for that
# `f`, and so does the C, which calls `f` by name. No function pointer is ever needed.
#
# What a function value holds is what it captured. `x -> a * x + b` holds `a` and `b`; a named
# function and `x -> 2x` hold nothing. So a function value is a tuple of its captures, and it
# travels as a tuple does (`Kind`): spread into one C value per capture wherever it is passed,
# `newton(double f_a, double x)`, and gathered into a struct only where it must be one value,
# as a function's return. A function that holds nothing takes no room at all, and its
# parameter is gone.
#
# Calling one is a call to the C function its body became, the captures first:
#
#     g = y -> a * y + 1.0                 double g(double a, double y)
#     g(x)                                 g(a, x)
#
# A captured variable keeps its value for as long as the function that captured it lives:
# Julia holds a variable that is assigned again afterwards in a `Core.Box`, which has no type
# and is refused. So the captures of a function made in this function are written as the
# variables themselves, and nothing is stored.

# The callee of `v(args…)` where `v` is a value that holds something, a function with captures
# or a struct of the author's with a method of its own: `canonical!` writes the call as this
# function applied to `v` and the arguments, so that `v` is passed like any other argument.
struct Called{T} <: Function end
Base.parentmodule(::Called{T}) where {T} = T.name.module
Base.nameof(::Called{T}) where {T} = nameof(T)

# A function written without a name, `x -> …` or a `do` block: Julia names it `#…`.
islambda(T::Type) = T <: Function && startswith(string(T.name.singletonname), "#")

# The method instance a call of a `T` value at these argument types runs, or nothing.
lookup(T::Type, types) = exact(ccall(:jl_method_lookup_by_tt, Any, (Any, Csize_t, Any), Tuple{T, types...}, Base.get_world_counter(), nothing), Tuple{T, types...})

# The same for a call whose arguments include a regular array of a known size, given as its
# element type and dimensions: a static array if the method takes one, else a regular one.
function resolve(::Called{T}, spec) where {T}
    static, shapedsig, groups = spectypes(spec[2:end])
    mi = lookup(T, static)
    mi === nothing || return (mi, static)
    regular = [isempty(d) ? E : Array{E, length(d)} for (E, d) in groups]
    mi = lookup(T, regular)
    return mi === nothing ? (nothing, nothing) : (mi, shapedsig)
end

# Julia doesn't compile a function anew for a function it only passes on, `thru(g, x) =
# twice(g, x)`: there `g` is any `Function`, and nothing computed from it has a type. The C
# has to know which function it is, so the instance is asked for at exactly these types.
function exact(mi, tt::Type)
    mi === nothing && return nothing
    mi.specTypes == tt && return mi
    any(T -> T isa Type && T <: Function, tt.parameters[2:end]) || return mi
    match = Base._which(tt)
    return Core.Compiler.specialize_method(match.method, tt, match.sparams)
end

# The C name of a function type, as a word in another name: a named function's own, a
# lambda's by the rule below.
function functionname(T::Type)
    islambda(T) && return lambdaname(first(Base.values(programs)), T)
    name = identifier(fname(T.name.singletonname))
    return nameof(Base.moduleroot(T.name.module)) in known ? name : qualified(name, T.name.module)      # Julia's own: `sin`, not `Base_sin`
end

# The C name of a lambda: the variable it was given, `g = y -> …` is `g`; with none, `fun` and
# a number, counted through the file in the order they are needed, then what it captured, by
# the rules a temp's name follows (`temp!`, doc/naming.md): `fun3_a_b` for `x -> a * x + b`.
# A second lambda given a name already taken by one is its function's: `outer_g`.
# Its parameters aren't in the name, since its signature shows them. A number is passed over
# when the author has a `fun<N>` of their own.
function lambdaname(prog::Program, T::Type)
    key = T.name
    haskey(prog.lambdas, key) && return prog.lambdas[key]
    if haskey(prog.bindings, key)
        # Two functions may each call theirs `g`: the second is its function's, `outer_g`.
        name, outer = prog.bindings[key]
        own = qualified(name, key.module)
        own in Base.values(prog.lambdas) && (own = qualified(outer * "_" * name, key.module))
        return prog.lambdas[key] = own
    end
    taken = union(filescope(prog), Set(c.julia for c in prog.claims))
    n = count(v -> occursin(r"(^|_)fun\d+(_|$)", v), Base.values(prog.lambdas))
    while true
        n += 1
        any(t -> occursin(Regex("^fun$(n)(_|\$)"), t), taken) || break
    end
    base = "fun$n"
    parts = unique(reduce(vcat, (filter(!isempty, split(replace(c, r"^temp\d+_?" => ""), "_")) for c in fieldcnames(T)); init=SubString{String}[]))
    name = isempty(parts) || !prog.suffix ? base : base * "_" * join(parts, "_")
    length(name) > prog.limit && (name = base)
    return prog.lambdas[key] = qualified(name, key.module)
end

# A captured variable that is assigned again after the function was made: Julia keeps it in
# a `Core.Box`, of no type, and nothing computed from it has one.
function boxed(T::Type, where)
    k = findfirst(F -> F === Core.Box, elements(T))
    k === nothing && return
    v = capturenames(T)[k]
    throw(ArgumentError("`$v` is used inside a function written $where and assigned again outside it, so Julia holds it in a box of no type, and nothing computed from it has a type. Give the inner function its own variable, or pass `$v` to it and return the new value"))
end

# `#1 = %new(T, a, b)`, a function made here, and `g = %5`, the same one given a name: no C.
# The variable stands for the captures, each written as the variable it was captured from.
function lambda!(sc::Scope, i, st::Expr)
    ci = sc.ci
    slot = st.args[1]
    slot isa Core.SlotNumber || return false
    if st.args[2] isa Expr && st.args[2].head === :call && callee_or_nothing(ci, st.args[2].args[1]) === Core.Box
        v = ci.slotnames[slot.id]
        throw(ArgumentError("`$v` is used inside a function written here and assigned again after that function is made, so Julia holds it in a box of no type, and nothing computed from it has a type. Give the inner function its own variable, or pass `$v` to it and return the new value"))
    end
    T = slottype(sc, slot.id)
    T isa DataType && T <: Function || return false
    rhs = st.args[2]
    kind = if rhs isa Expr && rhs.head === :new
        boxed(T, "here")
        Kind("", reduce(vcat, (captured(sc, a) for a in rhs.args[2:end]); init=String[]))
    else
        tuplekind(sc, rhs)
    end
    kind !== nothing && isempty(kind.cname) || return false
    # The captures are written as their variables, which is right while those hold what they
    # held when the function was made. In a loop they change on the next pass, so there the
    # function is to be used straight away, before anything can come between.
    if inloop(ci, i)
        for (r, u) in enumerate(ci.code)
            (u isa Core.SlotNumber && u.id == slot.id) || continue
            (r > i && !any(k -> jumps(ci, k), i+1:r)) ||
                throw(ArgumentError("the function made at line $(sc.stmtline[i]) is made inside a loop and used across a branch or on a later pass, where the variables it captured may have moved on. Make it before the loop, or use it on the line it is made"))
        end
    end
    sc.slotkinds[slot.id] = kind
    sc.kinds[i] = kind
    push!(sc.hidden, slot.id)
    return true
end

# A captured value as C text: a variable's name, a field of this function's own captures. A
# captured function is what it captured in turn.
function captured(sc::Scope, a)
    isfunction(valuetype(sc, a)) || return [value(sc, a)]
    k = tuplekind(sc, a)
    k === nothing && return String[]
    return isempty(k.cname) ? k.fields : [value(sc, a) * "." * c for c in k.fields]
end

# Is statement `i` inside a loop: is there a jump back, after it, to at or before it?
inloop(ci, i) = any(j -> (g = ci.code[j]; g isa Core.GotoNode && g.label <= i), i+1:length(ci.code))
# Is statement `k` a jump, or somewhere a jump lands?
jumps(ci, k) = ci.code[k] isa Core.GotoNode || ci.code[k] isa Core.GotoIfNot ||
               any(g -> (g isa Core.GotoNode && g.label == k) || (g isa Core.GotoIfNot && g.dest == k), ci.code)

# The name the lambda made at each `%new` was given, if it was given one: `g = y -> …` stores
# the new function in a variable of Julia's own, reads it, and stores that in `g`.
function bindings!(prog::Program, mi::Core.MethodInstance, ci::Core.CodeInfo)
    for st in ci.code
        st isa Expr && st.head === :(=) && st.args[2] isa Expr && st.args[2].head === :new || continue
        hidden = st.args[1].id
        T = ci.slottypes[hidden]
        T isa Core.Const && (T = typeof(T.val))
        T isa Core.PartialStruct && (T = T.typ)
        T isa DataType && T <: Function || continue
        push!(prog.made, T.name)
        haskey(prog.bindings, T.name) && continue
        reads = [k for (k, u) in enumerate(ci.code) if u isa Core.SlotNumber && u.id == hidden]
        for u in ci.code
            u isa Expr && u.head === :(=) && u.args[2] isa Core.SSAValue && u.args[2].id in reads || continue
            name = string(ci.slotnames[u.args[1].id])
            startswith(name, "#") || isempty(name) || (prog.bindings[T.name] = (identifier(name), identifier(plainname(mi.def.name))))
        end
    end
end

# The source lines of each function written inside this one, after the line it is made on: a
# `do` block's body, the lines of `x -> begin … end`. Julia says where the inner function's
# statements are; the line it is made on is the outer function's own.
function innerlines(mi::Core.MethodInstance, ci::Core.CodeInfo)
    out = UnitRange{Int}[]
    made = statementlines(mi, length(ci.code))
    for (k, st) in enumerate(ci.code)
        st isa Expr && st.head === :(=) && st.args[2] isa Expr && st.args[2].head === :new || continue
        T = ci.slottypes[st.args[1].id]
        T isa Core.Const && (T = typeof(T.val))
        T isa Core.PartialStruct && (T = T.typ)
        T isa DataType && T <: Function || continue
        for match in Base._methods_by_ftype(Tuple{T, Vararg{Any}}, -1, Base.get_world_counter())
            m = match.method
            inner = try Base.uncompressed_ast(m) catch; continue end
            at = Int[Base.IRShow.getdebugidx(inner.debuginfo, j)[1] for j in eachindex(inner.code)]
            lo, hi = max(m.line, made[k] + 1), maximum(at; init=Int(m.line))
            lo <= hi && push!(out, lo:hi)
        end
    end
    return out
end
