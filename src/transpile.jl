# Everything lives in the module `Newt`, so that a user's own `shape` or `index` — or
# a function of theirs named like any of the transpiler's internals — is a different
# name. `include`-ing this file also brings `transpile` into scope, which is the one
# name a user needs.
module Newt

using StaticArrays
using LinearAlgebra
using Printf

export transpile

include("c.jl")

"""
    transpile(target...; outfile="juliatranspiled", outpath=pwd()) -> path

Transpile one or more targets to a single C file and return its path. Each
`target` is one of:

- a `Function` — must have exactly one method with all-concrete argument types
- a `Core.MethodInstance` — must be a concrete specialization
- a tuple `(f, T...)` — the arguments to [`concretemethod`](@ref), which resolves it

In the tuple form a type followed by integers is an array of that element type and
those dimensions: `(f, Float64, 3, Float64, 2, 3)` is a 3-vector and a 2×3 matrix.
Each array is a static array if the function accepts one, otherwise a regular
`Array` of that size — the C is the same either way.

Every target is resolved to a concrete `MethodInstance` before anything is written;
a target that can't be resolved throws an `ArgumentError`.

Options:

- `outfile`: name of the C file; `.c` is appended if not already present.
- `outpath`: folder to write it in; defaults to Julia's current working directory.
- `templimit`: longest name an intermediate value may be given before its
  descriptive suffix is dropped (see [`temp!`](@ref)).
- `staticarray`: treat every Julia array as fixed-size, and refuse anything a
  fixed-size array can't do (growing, resizing, …). Turning it off asks for
  dynamic arrays, which are not yet supported.
- `source`: copy each line of the Julia body into the C as a comment, prefixed
  `file:line:`, where that line's work happens. Comments are carried over
  regardless; this controls the code. See `doc/comment.md`.
- `precise`: print every digit of a floating value (`%.17g`, `%.9g` for
  `Float32`) instead of `%g`. See `doc/io.md`.
- `portable`: define `NEWT_PI` and `NEWT_E` at the top of the file and use those,
  instead of `M_PI` and `M_E` from `math.h`, which are POSIX rather than ISO C and
  can be missing under a strict `-std=c11`.
- `width`: the longest line the C may have, in columns. A scalar expression
  that would run past it is wrapped at its loosest operators, each
  continuation line starting with the operator. See `doc/copy.md`.

Each function keeps its Julia name in C. If the same function is transpiled at more
than one signature in a single call, those get the argument types appended
(`fun1_Float64_Float64`) so the names don't collide.
"""
function transpile(target::Union{Function, Core.MethodInstance, Tuple{Function, Vararg{Union{DataType, Integer}}}}...;
                   outfile::AbstractString="juliatranspiled", outpath::AbstractString=pwd(),
                   templimit::Integer=40,
                   # On by default only until dynamic arrays are supported; then it flips
                   # to off, and static becomes something you opt into.
                   staticarray::Bool=true,
                   source::Bool=true,
                   precise::Bool=false,
                   width::Integer=100,
                   portable::Bool=false)
    staticarray || throw(ArgumentError("dynamic arrays are not yet supported; use staticarray=true"))
    # Each instance is paired with its signature: the instance's own argument types,
    # except that a regular array is given as a shaped stand-in carrying its size.
    instances = Tuple{Core.MethodInstance, Vector{Type}}[]
    for t in target
        if t isa Function
            mi, _ = concretemethod(t)
            sig = argtypes(mi)
        elseif t isa Tuple
            mi, sig = resolve(t[1], t[2:end])
        else
            # A MethodInstance is not necessarily concrete: inference also creates them
            # for abstract signatures (e.g. f(::Real, ::Real)), so check its specTypes
            # the same way concretemethod checks a method's signature.
            mi = t
            st = mi.specTypes
            st isa DataType && all(isconcretetype, st.parameters[2:end]) ||
                throw(ArgumentError("$mi is not a concrete specialization"))
            sig = argtypes(mi)
        end
        push!(instances, (mi, sig))
    end
    # Two instances that are the same method at signatures C can't tell apart — a
    # static and a mutable array of the same size, say — are one C function.
    unique!(inst -> (inst[1].def, csignature(inst[2])), instances)

    names = cnames(instances)
    prog = Program(; precise, width, portable)
    union!(prog.names, names)
    for (n, (mi, _)) in zip(names, instances); prog.calls[mi] = n; end
    generate(n, mi, sig; blocked=()) = cfunction(n, mi, sig, prog; templimit, staticarray, source, blocked)
    functions = [generate(n, mi, sig) for (n, (mi, sig)) in zip(names, instances)]
    # A call to a function that wasn't asked for brings it in, and it may call others.
    while !isempty(prog.pending)
        mi, sig, n = popfirst!(prog.pending)
        push!(instances, (mi, sig))
        push!(names, n)
        push!(functions, generate(n, mi, sig))
    end
    # The helpers' names are known only now. A function that shares one is an error,
    # since its name is the C interface; a variable that shares one is renamed with `_`
    # by generating that function again with the helper names blocked.
    for n in names
        haskey(prog.helpers, n) && throw(ArgumentError("the function `$n` has the same name as the helper `$n` the output needs; rename it"))
    end
    for (k, (n, (mi, sig))) in enumerate(zip(names, instances))
        any(v -> haskey(prog.helpers, v), functions[k][3]) || continue
        functions[k] = generate(n, mi, sig; blocked=keys(prog.helpers))
    end
    path = joinpath(outpath, endswith(outfile, ".c") ? outfile : outfile * ".c")
    open(path, "w") do io
        for h in ("stdint.h", "stdbool.h", "stdlib.h", "string.h", "stdio.h", "float.h", "math.h")
            h in prog.headers && println(io, "#include <", h, ">")
        end
        println(io)
        for m in sort!(collect(prog.macros)); println(io, "#define NEWT_", m, " ", Float64(constants[m]), "  // the double nearest ", constants[m]); end
        isempty(prog.macros) || println(io)
        for (_, definition) in prog.structs; print(io, definition); println(io); end
        for name in sort!(collect(keys(prog.foreign))); println(io, prog.foreign[name]); end
        isempty(prog.foreign) || println(io)
        for (prototype, _, _) in functions; println(io, prototype); end
        for name in helperorder(prog.helpers); println(io); print(io, prog.helpers[name]); end
        for (_, definition, _) in functions; println(io); print(io, definition); end
    end
    return path
end

# The helpers in the order they can be defined: alphabetical, except that one that calls
# another comes after it (`det_4x4` after `det_3x3`, `solve_4x4_4` after `lu_4x4` after
# `pivot_4x4`), so no prototypes are needed.
function helperorder(helpers)
    order = String[]
    remaining = sort!(collect(keys(helpers)))
    while !isempty(remaining)
        ready = filter(n -> all(m -> m == n || m in order || !occursin(m * "(", helpers[n]), remaining), remaining)
        isempty(ready) && throw(ArgumentError("helpers call each other in a cycle: $(join(remaining, ", "))"))
        append!(order, ready)
        filter!(!in(ready), remaining)
    end
    return order
end

# C names for the instances: each Julia name made C-valid, instances that share a name
# told apart by `mangled`, and the results kept clear of reserved words.
function cnames(instances)
    base = [identifier(string(mi.def.name)) for (mi, _) in instances]
    names = similar(base)
    for b in unique(base)
        group = findall(==(b), base)
        names[group] = mangled(b, [sig for (_, sig) in instances[group]])
    end
    return identifiers(names)
end

argtypes(mi::Core.MethodInstance) = Type[normalize(T) for T in mi.specTypes.parameters[2:end]]

# A signature as C sees it: every array reduced to element type and size.
csignature(sig) = [isarray(T) ? shaped(eltype(T), shape(T)) : T for T in sig]

# Resolve a tuple target's specification — types, each optionally followed by the
# integer dimensions of an array — to a MethodInstance and a signature.
function resolve(f::Function, spec)
    isempty(spec) && return (concretemethod(f)[1], argtypes(concretemethod(f)[1]))
    spec[1] isa Integer && throw(ArgumentError("in $((f, spec...)), a dimension must follow a type"))
    # Group into (element type, dimensions) pairs.
    groups = Tuple{DataType, Vector{Int}}[]
    for x in spec
        x isa DataType ? push!(groups, (x, Int[])) : push!(groups[end][2], x)
    end
    all(isempty(d) for (_, d) in groups) && (mi = concretemethod(f, spec...)[1]; return (mi, argtypes(mi)))
    # Arrays are static if the function takes them that way, else regular arrays of
    # the same size, which the transpiler treats identically.
    static  = [isempty(d) ? T : SArray{Tuple{d...}, T, length(d), prod(d)} for (T, d) in groups]
    regular = [isempty(d) ? T : Array{T, length(d)} for (T, d) in groups]
    shapedsig = [isempty(d) ? T : shaped(T, d) for (T, d) in groups]
    mi = Base.method_instance(f, Tuple(static))
    mi === nothing || return (mi, static)
    mi = Base.method_instance(f, Tuple(regular))
    mi === nothing && throw(ArgumentError("$f has no method accepting $(Tuple(static)) or $(Tuple(regular))"))
    return (mi, shapedsig)
end

"""
    transpile(f, T1, T...)

Single-target form: `transpile(f, Float64, Float64)` is `transpile((f, Float64, Float64))`
without the extra parentheses. Deliberately accepts only one function — to transpile
several targets, each with its own types, box each one up as a tuple so there is no
question of which types belong to which function.

At least one type is required; with none, a bare `transpile(f)` is handled by the
method above (and would otherwise be ambiguous between the two).
"""
transpile(f::Function, T1::DataType, T::Union{DataType, Integer}...; kw...) = transpile((f, T1, T...); kw...)

"""
    concretemethod(f, T...) -> (MethodInstance, return type)

The compiled specialization of `f` for concrete argument types `T`, plus its
inferred return type. With no `T`, uses `f`'s own signature, which must then
be concrete.

Works on Julia 1.12.6. Uses `Base.method_instance` and `Base.return_types`,
which are undocumented Base internals with no stability guarantee — if this
breaks after a Julia upgrade, those two calls are the first thing to check.
"""
function concretemethod(f::Function, T::DataType...)
    if isempty(T)
        # No types given: use the function's own signature, which must be concrete.
        # A `where` signature is a UnionAll, so it's not concrete by definition.
        ms = filter(m -> !(m.sig isa UnionAll) && all(isconcretetype, m.sig.parameters[2:end]), methods(f))
        isempty(ms) && throw(ArgumentError("$f has no method with concrete argument types; give the types explicitly"))
        length(ms) > 1 && throw(ArgumentError("$f has $(length(ms)) methods with concrete argument types; give the types to pick one"))
        T = Tuple(only(ms).sig.parameters[2:end])
    else
        all(isconcretetype, T) || throw(ArgumentError("argument types must all be concrete, got $(T)"))
    end
    # One method-table lookup: dispatch resolution and specialization together.
    # Returns the canonical MethodInstance (type params filled in), or nothing.
    mi = Base.method_instance(f, T)
    mi === nothing && throw(ArgumentError("$f has no method accepting $(T)"))
    T_return = only(Base.return_types(f, T))
    return mi, T_return
end

end # module Newt

using .Newt
