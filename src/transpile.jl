
include("c.jl")

"""
    transpile(target...; outfile="juliatranspiled", outpath=pwd()) -> path

Transpile one or more targets to a single C file and return its path. Each
`target` is one of:

- a `Function` — must have exactly one method with all-concrete argument types
- a `Core.MethodInstance` — must be a concrete specialization
- a tuple `(f, T...)` — the arguments to [`concretemethod`](@ref), which resolves it

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

Each function keeps its Julia name in C. If the same function is transpiled at more
than one signature in a single call, those get the argument types appended
(`fun1_Float64_Float64`) so the names don't collide.
"""
function transpile(target::Union{Function, Core.MethodInstance, Tuple{Function, Vararg{DataType}}}...;
                   outfile::AbstractString="juliatranspiled", outpath::AbstractString=pwd(),
                   templimit::Integer=40,
                   # On by default only until dynamic arrays are supported; then it flips
                   # to off, and static becomes something you opt into.
                   staticarray::Bool=true)
    staticarray || throw(ArgumentError("dynamic arrays are not yet supported; use staticarray=true"))
    instances = Core.MethodInstance[]
    for t in target
        if t isa Function
            mi, _ = concretemethod(t)
        elseif t isa Tuple
            mi, _ = concretemethod(t...)
        else
            # A MethodInstance is not necessarily concrete: inference also creates them
            # for abstract signatures (e.g. f(::Real, ::Real)), so check its specTypes
            # the same way concretemethod checks a method's signature.
            mi = t
            sig = mi.specTypes
            sig isa DataType && all(isconcretetype, sig.parameters[2:end]) ||
                throw(ArgumentError("$mi is not a concrete specialization"))
        end
        push!(instances, mi)
    end
    unique!(instances)

    names = cnames(instances)
    helpers = Dict{String, String}()
    functions = [cfunction(n, mi, helpers; templimit, staticarray) for (n, mi) in zip(names, instances)]
    path = joinpath(outpath, endswith(outfile, ".c") ? outfile : outfile * ".c")
    open(path, "w") do io
        println(io, "#include <stdint.h>")
        println(io, "#include <stdbool.h>")
        println(io)
        for (prototype, _) in functions; println(io, prototype); end
        for name in sort!(collect(keys(helpers))); println(io); print(io, helpers[name]); end
        for (_, definition) in functions; println(io); print(io, definition); end
    end
    return path
end

# C names for the instances: each Julia name made C-valid, instances that share a name
# told apart by `mangled`, and the results kept clear of reserved words.
function cnames(instances)
    base = [identifier(string(mi.def.name)) for mi in instances]
    names = similar(base)
    for b in unique(base)
        group = findall(==(b), base)
        names[group] = mangled(b, instances[group])
    end
    return identifiers(names)
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
transpile(f::Function, T1::DataType, T::DataType...; kw...) = transpile((f, T1, T...); kw...)

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
