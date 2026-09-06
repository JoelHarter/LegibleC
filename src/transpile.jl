# The API: targets to method instances, C names, and the output file.

"""
    transpile(target...; outfile="juliatranspiled", outpath=pwd(), split=false) -> path

Transpile one or more targets into `outpath/out/`: `<outfile>.c` with the functions
and `<outfile>.h` for callers, `helper.h` and `helper.c` with the generated helpers
they need. Returns the path of the functions file — the paths, in file order, when
there are several. Each `target` is one of:

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
- `split`: every function in a file of its own, named after it, listed or not, with
  its header; every struct in a header of its own; a function's return struct with
  the function. `<outfile>.h` then holds the globals and includes every other
  header, so a caller can still include one file; `<outfile>.c` holds the mutable
  globals, and is written only when there are any. Names that differ only in case,
  `point` and `Point`, share a file, named by the lowercase one.
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
- `c23floattypes`: write `Float64` and `Float32` as C23's `_Float64` and `_Float32`
  instead of `double` and `float`, wherever they appear.
- `bool`: the C type for Julia's `Bool` — `Bool` itself, for C's `bool`, or one of
  Julia's integer types, `Int32` say, for that integer wherever a `Bool` appears:
  parameters, results, fields, elements, and the names that mention the type. The
  C then writes `0` and `1`, and reads any nonzero value as true.

Each function keeps its Julia name in C. If the same function is transpiled at more
than one signature in a single call, those get the argument types appended
(`fun1_Float64_Float64`) so the names don't collide.
"""
function transpile(target::Union{Function, Core.MethodInstance, Tuple{Function, Vararg{Union{DataType, Integer}}}, Type, Pair{Symbol, <:Any}, GlobalRef}...;
                   outfile::AbstractString="juliatranspiled", outpath::AbstractString=pwd(), split::Bool=false,
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
                   c23floattypes::Bool=false,
                   bool::Type=Bool,
                   scope::Module=Main,
                   variables...)
    bool === Bool || bool in (Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64) ||
        throw(ArgumentError("bool must be Bool or one of Julia's integer types, not $bool"))
    LegibleC.spelling[] = checkspelling(spelling)
    LegibleC.scope[] = scope
    LegibleC.c23floattypes[] = c23floattypes
    LegibleC.booltype[] = bool
    try
        return transpiled(target...; outfile, outpath, separate=split, templimit, staticarray, source, precise, width, portable, suffix=tempsuffix, scope, variables)
    finally
        LegibleC.spelling[] = Dict{Char, String}()
        LegibleC.scope[] = Main
        LegibleC.c23floattypes[] = false
        LegibleC.booltype[] = Bool
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

function transpiled(target...; outfile, outpath, separate, templimit, staticarray, source, precise, width, portable, suffix, scope, variables)
    staticarray || throw(ArgumentError("dynamic arrays are not yet supported; use staticarray=true"))
    # Each instance is paired with its signature: the instance's own argument types,
    # except that a regular array is given as a shaped stand-in carrying its size.
    instances = Tuple{Core.MethodInstance, Vector{Type}}[]
    synthetics = Dict{Core.MethodInstance, Any}()   # an operator target's stand-in -> (operator, signature)
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
            # Julia's own operator at these types — `(+, Float64, 3, Float64, 3)` — is
            # asked for by name, so the helper it would become is a function instead.
            nameof(Base.moduleroot(mi.def.module)) in known && (mi = synthetic(t[1], mi, sig); synthetics[mi] = (t[1], sig))
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
    for (k, (mi, _)) in enumerate(instances); haskey(synthetics, mi) && (names[k] = string(mi.def.name)); end
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
    generate(n, mi, sig; blocked=()) = cfunction(n, mi, sig, prog; templimit, staticarray, source=source && !haskey(synthetics, mi), blocked)
    functions = [generate(n, mi, sig) for (n, (mi, sig)) in zip(names, instances)]
    # A call to a function that wasn't asked for brings it in, and it may call others.
    while !isempty(prog.pending)
        mi, sig, n = popfirst!(prog.pending)
        push!(instances, (mi, sig))
        push!(names, n)
        push!(functions, generate(n, mi, sig))
    end
    # An operator target whose stand-in is one helper call — `add_3(a, b, out)` — is that
    # helper, written as a function of the user's under the helper's name and taken out
    # of `helper.h`. A stand-in with more to it (a scalar operator) stays as it is.
    for (k, (mi, _)) in enumerate(instances)
        haskey(synthetics, mi) || continue
        f, sig = synthetics[mi]
        julia = string(nameof(f)) * "(" * join(("::" * string(T <: Shaped ? juliatype(T) : T) for T in sig), ", ") * ")"
        h = onlycall(functions[k][3], prog.helpers)
        if h === nothing
            # The stand-in stays; its Doxygen block names the operator, not the stand-in.
            proto, above, def, vars = functions[k]
            functions[k] = (proto, replace(above, r"Julia signature: [^\n]*" => "Julia signature: " * julia), def, vars)
            continue
        end
        push!(prog.exported, h)
        names[k] = h
        functions[k] = exportedfunction(prog.helpers[h], julia, sig, returntype(mi))
    end
    # The helpers' names are known only now. A function that shares one is an error,
    # since its name is the C interface; a variable that shares one is renamed with `_`
    # by generating that function again with the helper names blocked.
    for n in names
        haskey(prog.helpers, n) && !(n in prog.exported) && throw(ArgumentError("the function `$n` has the same name as the helper `$n` the output needs; rename it"))
    end
    for (k, (n, (mi, sig))) in enumerate(zip(names, instances))
        any(v -> haskey(prog.helpers, v), functions[k][4]) || continue
        functions[k] = generate(n, mi, sig; blocked=keys(prog.helpers))
    end
    dir = joinpath(outpath, "out")
    mkpath(dir)
    base = endswith(outfile, ".c") ? outfile[1:end-2] : outfile
    base == "helper" && throw(ArgumentError("`helper.c` is the file the generated helpers go to; name the functions' file something else"))
    where, order = placement(prog, base, separate, names)
    writehelpers(dir, prog, separate ? where : Dict(n => base for n in prog.exported))
    return writefiles(dir, prog, base, where, order, names, functions)
end

# Methods made on request stand in for Julia's own operators as targets (`synthetic`).
module Synthetic end

# A stand-in for Julia's operator `f` at the argument types of its instance `mi`: a
# method of `Synthetic` named by the helper scheme, `add_3`, whose body is the call.
# The C it makes is what the operator becomes anywhere, and now under a name of its
# own.
function synthetic(f, mi::Core.MethodInstance, sig)
    types = collect(mi.specTypes.parameters[2:end])
    name = Symbol(operatorname(nameof(f), sig))
    args = [Symbol('a' + k - 1) for k in 1:length(types)]   # `a`, `b`, `c`, as a helper names them
    params = [Expr(:(::), a, T) for (a, T) in zip(args, types)]
    # Built without line numbers, so the method has no source to quote from.
    s = Core.eval(Synthetic, Expr(:(=), Expr(:call, name, params...), Expr(:block, Expr(:call, f, args...))))
    return Base.method_instance(s, Tuple(types))
end

# The helper a function's body is one call to, if it is that and nothing else.
function onlycall(definition, helpers)
    inner = [strip(l) for l in split(rstrip(definition), "\n")[2:end-1]]
    lines = [l for l in inner if !isempty(l) && !startswith(l, "//")]
    length(lines) == 1 || return nothing
    m = match(r"^(?:return )?(\w+)\(", lines[1])
    m !== nothing && haskey(helpers, m[1]) ? String(m[1]) : nothing
end

# A helper as a function of the user's: its definition without `static inline`, its
# prototype, and a Doxygen block from its two comment lines and the operator it stands
# for, in the shape every other function gets.
function exportedfunction(text, julia, sig, R)
    lines = split(text, "\n")
    doc = [String(strip(l[4:end])) for l in lines if startswith(l, "///")]
    code = [String(l) for l in lines if !startswith(l, "///")]
    code[1] = replace(code[1], r"^static inline " => "")
    definition = join(code, "\n")
    proto = prototype(definition)
    what(T) = isarray(T) ? describe(T) : T <: Number ? "scalar" : ""
    pnames = [String(m[1]) for m in eachmatch(r"(\w+)(?:\[[^\]]*\])*(?:,|\)$)", proto[1:end-1])]
    params = [("in", n, what(T)) for (n, T) in zip(pnames, sig)]
    length(pnames) > length(sig) && push!(params, ("out", pnames[end], describe(R) * ", the return value"))
    return (proto, join(doxygen(doc, julia, params), "\n"), definition, String[])
end

# Does the C text mention the name — a function, as a call; anything else, as a word?
mentions(text, name; call::Bool=false) = occursin(Regex("\\b\\Q$name\\E" * (call ? "\\(" : "\\b")), text)

# Each file includes the standard headers its own code uses, found by the names each
# header provides — `int64_t`, `bool`, `memcpy`, `sqrt`, `printf`, … — not the union of
# what the program uses. Comments don't count: a Julia line quoted above its C may
# say `true` or `sqrt` without the C doing so.
function includes(text)
    code = replace(text, r"/\*.*?\*/"s => "", r"//[^\n]*" => "")
    return [h for (h, pattern) in standard if occursin(pattern, code)]
end

# `#define`s for the portable constants, each written where it is used.
macros(prog::Program) = ["#define LEGIBLEC_$m $(Float64(constants[m]))  // the double nearest $(constants[m])" for m in sort!(collect(prog.macros))]

# `helper.h` and `helper.c`: everything generated that the user's functions need —
# `add_3`, `solve_4x4_4`, `powi`, `printarray_F64`. The header holds what the helpers
# need — standard includes, constants, typedefs — plus prototypes of the out-of-line
# helpers and the inline ones themselves; the `.c` holds the out-of-line ones, and is
# written only when there is one. A struct a helper mentions is defined here, unless
# `external` names the header that has it, which is then included.
function writehelpers(dir, prog::Program, external)
    order = filter(!in(prog.exported), helperorder(prog.helpers))
    isempty(order) && return
    text = join((prog.helpers[n] for n in order), "\n")
    inline = [n for n in order if isinline(prog.helpers[n])]
    outline = [n for n in order if !isinline(prog.helpers[n])]
    guard = "LEGIBLEC_HELPER_H"
    htext = String[]
    used = [m for m in macros(prog) if occursin(split(m)[2], text)]
    append!(htext, used); isempty(used) || push!(htext, "")
    headers = String[]
    for (T, def) in prog.structs
        name = structname(T)
        mentions(text, name) || continue
        haskey(external, name) ? push!(headers, external[name]) : push!(htext, def)
    end
    # A helper that calls one the user asked for by name finds it in the user's file.
    for name in prog.exported
        mentions(text, name; call=true) && push!(headers, external[name])
    end
    for name in outline; push!(htext, prototype(prog.helpers[name])); end
    isempty(outline) || push!(htext, "")
    for name in inline; push!(htext, prog.helpers[name]); end
    hbody = join(htext, "\n")
    ctext = join((prog.helpers[n] for n in outline), "\n")
    open(joinpath(dir, "helper.h"), "w") do io
        println(io, "#ifndef $guard\n#define $guard\n")
        for h in includes(hbody); println(io, "#include <", h, ">"); end
        for h in unique(headers); println(io, "#include \"$h.h\""); end
        isempty(includes(hbody)) && isempty(headers) || println(io)
        print(io, rstrip(hbody)); println(io); println(io)
        println(io, "#endif  // $guard")
    end
    isempty(outline) && return
    open(joinpath(dir, "helper.c"), "w") do io
        for h in includes(ctext); println(io, "#include <", h, ">"); end
        println(io, "#include \"helper.h\"")
        for name in outline; println(io); print(io, prog.helpers[name]); end
    end
end

# Which file each C name goes to, and the files in order. In one file: everything but
# the helpers, and a struct the helpers mention goes with them. Split: every function
# in a file named after it, listed or not; every struct in a header of its own; a
# function's return struct with that function; the globals and the foreign wrappers
# in `<base>`. Names that differ only in case share a file — `point` and `Point`,
# which one file system in three would merge anyway — named in lowercase.
function placement(prog::Program, base, split::Bool, names)
    where = Dict{String, String}()
    helpertext = join(values(prog.helpers), "\n")
    for n in names; where[n] = split ? n : base; end
    for g in prog.globals; where[g.cname] = base; end
    for n in keys(prog.foreign); where[n] = base; end
    for (T, _) in prog.structs
        n = structname(T)
        where[n] = split ? n : mentions(helpertext, n) ? "helper" : base
    end
    for (n, _) in prog.tupledefs
        owner = endswith(n, "_t") ? get(where, n[1:end-2], nothing) : nothing
        where[n] = !split ? base : owner === nothing ? n : owner
    end
    files = [base; [where[n] for n in names]; [where[structname(T)] for (T, _) in prog.structs]; [where[n] for (n, _) in prog.tupledefs]]
    filter!(!=("helper"), files)
    canon = Dict(key => (spellings = unique(f for f in files if lowercase(f) == key); length(spellings) == 1 ? only(spellings) : key)
                 for key in unique(lowercase.(files)))
    for (n, f) in where; f == "helper" || (where[n] = canon[lowercase(f)]); end
    order = unique(canon[lowercase(f)] for f in files)
    return where, order
end

# The functions' files, `<file>.c` with a companion `<file>.h` each: what a caller needs
# in the header and nothing else — the typedefs, the constants (`static const`, so every
# file that includes them can fold them), the other globals as `extern`, and each
# function's documented prototype with its own return struct right above it — and in
# the `.c` the includes, the mutable globals with their values, and the definitions. A
# file includes another's header when its text names something placed there; the
# `<base>` header of a split includes every other header, so a caller can include just
# that. A file with nothing for a `.c` — a struct's header — gets none. Returns the
# path of the `.c`, or the paths in file order when there are several.
function writefiles(dir, prog::Program, base, where, order, names, functions)
    definition = Dict(zip(names, (f[3] for f in functions)))
    # What each file defines, for the includes: functions and foreign wrappers are looked
    # for as calls, the rest as words.
    entities = Dict(f => Tuple{String, Bool}[] for f in order)
    for (n, f) in where
        haskey(entities, f) && push!(entities[f], (n, haskey(definition, n) || haskey(prog.foreign, n)))
    end
    helperstructs = [structname(T) for (T, _) in prog.structs if where[structname(T)] == "helper"]
    needs(text, f) = any(mentions(text, n; call) for (n, call) in entities[f])
    inheader(g::Global) = g.constant && !(globaltype(g.value) <: AbstractString)
    umbrella = length(order) > 1
    paths = String[]
    for file in order
        fns = [k for k in 1:length(names) if where[names[k]] == file]
        gls = [g for g in prog.globals if where[g.cname] == file]
        sts = [def for (T, def) in prog.structs if where[structname(T)] == file]
        tds = [(n, def) for (n, def) in prog.tupledefs if where[n] == file]
        fgn = [prog.foreign[n] for n in sort!(collect(keys(prog.foreign))) if where[n] == file]
        # The header: typedefs, then the globals, then each prototype under its comment,
        # with a return struct right above the first prototype that returns it.
        body = String[]
        append!(body, sts)
        protos = String[]
        done = Set{String}()
        for k in fns
            prototype, above = functions[k][1], functions[k][2]
            for (n, def) in tds
                startswith(prototype, n * " ") && !(n in done) || continue
                push!(protos, def)
                push!(done, n)
            end
            isempty(above) || push!(protos, above)
            push!(protos, prototype, "")
        end
        for (n, def) in tds; n in done || push!(body, def); end
        for g in gls; push!(body, inheader(g) ? "static " * globaldecl(g) : "extern " * globaldecl(g; value=false)); end
        isempty(gls) || push!(body, "")
        append!(body, protos)
        htext = join(body, "\n")
        guard = uppercase(identifier(file)) * "_H"
        header = ["#ifndef $guard", "#define $guard", ""]
        n0 = length(header)
        for h in includes(htext); push!(header, "#include <$h>"); end
        any(mentions(htext, n) for n in helperstructs) && push!(header, "#include \"helper.h\"")
        included = [f for f in order if f != file && (umbrella && file == base || needs(htext, f))]
        for f in included; push!(header, "#include \"$f.h\""); end
        length(header) > n0 && push!(header, "")
        push!(header, rstrip(htext), "", "#endif  // $guard")
        write(joinpath(dir, file * ".h"), join(header, "\n") * "\n")
        # The `.c`: the includes it needs beyond its own header, then the mutable globals
        # with their values, then the definitions. Nothing to hold, no file.
        cglobals = [globaldecl(g) for g in gls if !inheader(g)]
        defs = [functions[k][3] for k in fns]
        isempty(cglobals) && isempty(defs) && isempty(fgn) && continue
        used = [m for m in macros(prog) if occursin(split(m)[2], join(defs, "\n"))]
        ctext = join([used; cglobals; fgn; defs], "\n")
        path = joinpath(dir, file * ".c")
        push!(paths, path)
        open(path, "w") do io
            for h in includes(ctext); println(io, "#include <", h, ">"); end
            (any(mentions(ctext, n; call=true) for n in keys(prog.helpers)) || any(mentions(ctext, n) for n in helperstructs)) && println(io, "#include \"helper.h\"")
            for f in order; f != file && needs(ctext, f) && !(f in included) && println(io, "#include \"$f.h\""); end
            println(io, "#include \"$file.h\"")
            println(io)
            foreach(m -> println(io, m), used); isempty(used) || println(io)
            foreach(g -> println(io, g), cglobals); isempty(cglobals) || println(io)
            foreach(x -> println(io, x), fgn); isempty(fgn) || println(io)
            for (k, d) in enumerate(defs); k == 1 || println(io); print(io, d); end
        end
    end
    return length(paths) == 1 ? paths[1] : paths
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

