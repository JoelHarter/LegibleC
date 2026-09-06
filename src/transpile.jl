# The API: targets to method instances, C names, and the output file.

"""
    transpile(target...; outfile="juliatranspiled", outpath=pwd()) -> path

Transpile one or more targets into `outpath/out/`: `<outfile>.c` with the functions,
`helper.h` and `helper.c` with the generated helpers they need. Returns the path of
the functions file. Each
`target` is one of:

- a `Function` — must have exactly one method with all-concrete argument types
- a `Core.MethodInstance` — must be a concrete specialization
- a tuple `(f, T...)` — the arguments to [`concretemethod`](@ref), which resolves it;
  for a single function the tuple can be dropped, `transpile(f, T...)`

In the tuple form a type followed by integers is an array of that element type and
those dimensions: `(f, Float64, 3, Float64, 2, 3)` is a 3-vector and a 2×3 matrix.
Each array is a static array if the function accepts one, otherwise a regular
`Array` of that size — the C is the same either way.

Every target is resolved to a concrete `MethodInstance` before anything is written;
a target that can't be resolved throws an `ArgumentError`.

Options:

- `outfile`: name of the functions file; `.c` is appended if not already present.
- `outpath`: the folder whose `out/` subfolder receives the files; defaults to
  Julia's current working directory.
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
- `portable`: define `LEGIBLEC_PI` and `LEGIBLEC_E` at the top of the file and use those,
  instead of `M_PI` and `M_E` from `math.h`, which are POSIX rather than ISO C and
  can be missing under a strict `-std=c11`.
- `tempsuffix`: temps carry what they were computed from, `temp1_a_b = a + b`
  (`doc/naming.md`); off, they are `temp1`, `temp2`, …
- `spelling`: your own C spellings for characters in names, `Dict('ħ' => "hred",
  '∂' => "d")`, on top of the built-in ones (Julia's `\\name` completion table).
  Keys are single characters Julia allows in a name, other than ASCII letters,
  digits and `_`; values are C identifier text. See `doc/naming.md`.
- `width`: the longest line the C may have, in columns. A scalar expression
  that would run past it is wrapped at its loosest operators, each
  continuation line starting with the operator. See `doc/copy.md`.

Each function keeps its Julia name in C. If the same function is transpiled at more
than one signature in a single call, those get the argument types appended
(`fun1_Float64_Float64`) so the names don't collide.
"""
function transpile(target::Union{Function, Core.MethodInstance, Tuple{Function, Vararg{Union{DataType, Integer}}}, Type, Pair{Symbol, <:Any}, GlobalRef}...;
                   outfile::AbstractString="juliatranspiled", outpath::AbstractString=pwd(),
                   templimit::Integer=40,
                   # On by default only until dynamic arrays are supported; then it flips
                   # to off, and static becomes something you opt into.
                   staticarray::Bool=true,
                   source::Bool=true,
                   precise::Bool=false,
                   width::Integer=100,
                   portable::Bool=false,
                   tempsuffix::Bool=true,
                   spelling::AbstractDict=Dict{Char, String}(),
                   scope::Module=Main,
                   variables...)
    LegibleC.spelling[] = checkspelling(spelling)
    LegibleC.scope[] = scope
    try
        return transpiled(target...; outfile, outpath, templimit, staticarray, source, precise, width, portable, suffix=tempsuffix, scope, variables)
    finally
        LegibleC.spelling[] = Dict{Char, String}()
        LegibleC.scope[] = Main
    end
end

"""
    @transpile(targets...; variables..., options...)

`transpile`, with `scope` set to the module the call is written in, so that a variable
given by keyword is looked up where you wrote it: `@transpile(fall, Point; g, μ,
outfile="body")`.
"""
macro transpile(args...)
    params = [a for a in args if a isa Expr && a.head === :parameters]
    rest = [a for a in args if !(a isa Expr && a.head === :parameters)]
    # Keywords: a bare `k` is `k=k`; each value is evaluated where the macro was written.
    kws = Any[a isa Symbol ? Expr(:kw, a, esc(a)) : a isa Expr && a.head === :kw ? Expr(:kw, a.args[1], esc(a.args[2])) : esc(a)
              for a in (isempty(params) ? [] : params[1].args)]
    push!(kws, Expr(:kw, :scope, __module__))
    return Expr(:call, GlobalRef(@__MODULE__, :transpile), Expr(:parameters, kws...), esc.(rest)...)
end

function transpiled(target...; outfile, outpath, templimit, staticarray, source, precise, width, portable, suffix, scope, variables)
    staticarray || throw(ArgumentError("dynamic arrays are not yet supported; use staticarray=true"))
    # Each instance is paired with its signature: the instance's own argument types,
    # except that a regular array is given as a shaped stand-in carrying its size.
    instances = Tuple{Core.MethodInstance, Vector{Type}}[]
    types = Type[]
    values = Any[]                    # (module or nothing, name, value, constant or nothing)
    for t in target
        if t isa Type
            isconcretetype(t) && isstruct(t) || throw(ArgumentError("$t is not a concrete struct type"))
            push!(types, t)
            continue
        elseif t isa Pair
            push!(values, (nothing, t.first, t.second, nothing))
            continue
        elseif t isa GlobalRef
            push!(values, (t.mod, t.name, getfield(t.mod, t.name), nothing))
            continue
        end
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
    # A variable given by keyword: its binding is looked for in `scope`; a value with no
    # binding there is a constant.
    for (name, value) in pairs(variables)
        bound = isdefined(scope, name) && getfield(scope, name) === value
        push!(values, (bound ? scope : nothing, name, value, bound ? nothing : true))
    end
    # Two instances that are the same method at signatures C can't tell apart — a
    # static and a mutable array of the same size, say — are one C function.
    unique!(inst -> (inst[1].def, csignature(inst[2])), instances)

    names = cnames(instances)
    prog = Program(; precise, width, portable, suffix)
    union!(prog.names, names)
    for (n, (mi, _)) in zip(names, instances); prog.calls[mi] = n; end
    for T in types
        structdef!(prog, T)
        # The struct's docstring, as a Doxygen block above its typedef.
        doc = strip(string(Base.Docs.doc(T)))
        startswith(doc, "No documentation found") && continue
        k = findfirst(p -> p.first === T, prog.structs)
        prog.structs[k] = T => "/**\n" * join(" * " .* split(doc, "\n"), "\n") * "\n */\n" * prog.structs[k].second
    end
    for (mod, name, value, constant) in values; global!(prog, mod, name, value; constant); end
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
        any(v -> haskey(prog.helpers, v), functions[k][4]) || continue
        functions[k] = generate(n, mi, sig; blocked=keys(prog.helpers))
    end
    # The files in `out/`: `helper.h`/`.c` for everything generated that the user's
    # functions need — `add_3`, `solve_4x4_4`, `powi`, `printarray_F64` — and
    # `<outfile>.c` for the user's functions. The header holds what the helpers need —
    # standard includes, constants, typedefs — plus prototypes of the out-of-line
    # helpers and the inline ones themselves; the `.c` holds the out-of-line ones. The
    # helper files are written only when there is a helper. A function's own return
    # struct sits right above its prototype.
    dir = joinpath(outpath, "out")
    mkpath(dir)
    base = endswith(outfile, ".c") ? outfile[1:end-2] : outfile
    order = helperorder(prog.helpers)
    # Each file includes the standard headers its own text uses, found by the names
    # each header provides — `int64_t`, `bool`, `memcpy`, `sqrt`, `printf`, … — not
    # the union of what the program uses.
    includes(text) = [h for (h, pattern) in standard if occursin(pattern, text)]
    macros = ["#define LEGIBLEC_$m $(Float64(constants[m]))  // the double nearest $(constants[m])" for m in sort!(collect(prog.macros))]
    structs = [(structname(T), def) for (T, def) in prog.structs]
    placed = Set{String}()
    groups = [("helper", order)]
    for (file, names) in groups
        isempty(names) && continue
        text = join((prog.helpers[n] for n in names), "\n")
        inline = [n for n in names if isinline(prog.helpers[n])]
        outline = [n for n in names if !isinline(prog.helpers[n])]
        guard = "LEGIBLEC_" * uppercase(file) * "_H"
        htext = String[]
        used = [m for m in macros if occursin(split(m)[2], text)]
        append!(htext, used); isempty(used) || push!(htext, "")
        for (name, def) in structs; name in placed || !occursin(name, text) || (push!(htext, def); push!(placed, name)); end
        for name in outline; push!(htext, prototype(prog.helpers[name])); end
        isempty(outline) || push!(htext, "")
        for name in inline; push!(htext, prog.helpers[name]); end
        hbody = join(htext, "\n")
        ctext = join((prog.helpers[n] for n in outline), "\n")
        open(joinpath(dir, file * ".h"), "w") do io
            println(io, "#ifndef $guard\n#define $guard\n")
            for h in includes(hbody); println(io, "#include <", h, ">"); end
            isempty(includes(hbody)) || println(io)
            print(io, rstrip(hbody)); println(io); println(io)
            println(io, "#endif  // $guard")
        end
        # The `.c` holds the out-of-line helpers; with none, there is no file.
        isempty(outline) && continue
        open(joinpath(dir, file * ".c"), "w") do io
            for h in includes(ctext); println(io, "#include <", h, ">"); end
            println(io, "#include \"$file.h\"")
            for name in outline; println(io); print(io, prog.helpers[name]); end
        end
    end
    # The companion header, `<outfile>.h`: what a caller needs and nothing else — the
    # typedefs, the globals as `extern`, and each function's documented prototype, with
    # its own return struct right above it. The `.c` includes it, and holds the rest.
    guard = uppercase(identifier(base)) * "_H"
    header = ["#ifndef $guard", "#define $guard", ""]
    body = String[]
    for (name, def) in structs; name in placed || push!(body, def); end
    for g in prog.globals; push!(body, "extern " * globaldecl(g; value=false)); end
    isempty(prog.globals) || push!(body, "")
    for (prototype, above, _, _) in functions
        for (name, def) in prog.tupledefs
            startswith(prototype, name * " ") && !(name in placed) || continue
            push!(body, def); push!(placed, name)
        end
        isempty(above) || push!(body, above)
        push!(body, prototype, "")
    end
    text = join(body, "\n")
    n = length(header)
    for h in includes(text); push!(header, "#include <$h>"); end
    # A struct the helpers own that a prototype mentions: the header needs theirs.
    any(occursin(name, text) for name in placed if any(occursin(name, prog.helpers[n]) for n in order)) && push!(header, "#include \"helper.h\"")
    length(header) > n && push!(header, "")
    push!(header, rstrip(text), "", "#endif  // $guard")
    write(joinpath(dir, base * ".h"), join(header, "\n") * "\n")
    path = joinpath(dir, base * ".c")
    cbody = join([macros; [globaldecl(g) for g in prog.globals]; [prog.foreign[n] for n in sort!(collect(keys(prog.foreign)))]; [d for (_, _, d, _) in functions]], "\n")
    open(path, "w") do io
        for h in includes(cbody); println(io, "#include <", h, ">"); end
        for (file, names) in groups; isempty(names) || println(io, "#include \"$file.h\""); end
        println(io, "#include \"$base.h\"")
        println(io)
        foreach(m -> println(io, m), macros); isempty(macros) || println(io)
        for g in prog.globals; println(io, globaldecl(g)); end
        isempty(prog.globals) || println(io)
        for name in sort!(collect(keys(prog.foreign))); println(io, prog.foreign[name]); end
        isempty(prog.foreign) || println(io)
        for (k, (_, _, definition, _)) in enumerate(functions); k == 1 || println(io); print(io, definition); end
    end
    return path
end

# What each standard header provides, as a pattern over the C text that uses it.
const standard = (
    ("stdint.h", r"\b(u?int(8|16|32|64)_t)\b"),
    ("stdbool.h", r"\b(bool|true|false)\b"),
    ("stdlib.h", r"\b(llabs|abs|exit|abort|malloc|calloc|free)\("),
    ("string.h", r"\b(memcpy|memset|strcmp|strlen|strcpy)\("),
    ("ctype.h", r"\b(isdigit|isalpha|isspace|isupper|islower|ispunct|iscntrl|isprint|isxdigit|toupper|tolower)\("),
    ("stdio.h", r"\b(printf|fprintf|snprintf|fputs|fputc|putchar|puts|fflush|fopen|fclose|FILE|stdout|stderr)\b"),
    ("float.h", r"\b(DBL|FLT)_(EPSILON|MAX|MIN)\b"),
    ("math.h", r"\b(sqrt|cbrt|sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|exp|exp2|expm1|log|log2|log10|log1p|floor|ceil|trunc|rint|round|hypot|copysign|fabs|fmax|fmin|fmod|pow|isnan|isinf|isfinite|signbit)f?\(|\b(M_PI|M_E|INFINITY|NAN)\b"),
)

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
    base = [qualified(operatorname(mi.def.name, sig), mi.def.module) for (mi, sig) in instances]
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

