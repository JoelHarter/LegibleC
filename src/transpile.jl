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
- `helper`: the name of the helper files, `helper.h` and `helper.c` by default — for
  several `transpile` calls into one `out/`, each with helpers of its own to keep.
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
- `source`: copy each line of the Julia body into the C as a comment, prefixed
  `file:line:`, where that line's work happens. Comments are carried over
  regardless; this controls the code. See `doc/comment.md`.
- `precise`: print every digit of a floating value (`%.17g`, `%.9g` for
  `Float32`) instead of `%g`. See `doc/io.md`.
- `posix`: write `pi` and `ℯ` as `M_PI` and `M_E` from `math.h`, which are POSIX
  rather than ISO C and can be missing under a strict `-std=c11` (the helper header
  then defines them under `#ifndef`). Off, they are `LEGIBLEC_PI` and `LEGIBLEC_E`
  like every irrational: any `AbstractIrrational` — `Base.MathConstants.catalan`, one
  of your own by `Base.@irrational` — is a macro named after it, defined in the helper
  header to 128-bit precision.
- `tempsuffix`: temps carry what they were computed from, `temp1_a_b = a + b`, and an
  unnamed lambda what it captured, `fun3_a_b` (`doc/naming.md`). Off by default: they are
  `temp1`, `temp2`, … and `fun1`, `fun2`, …
- `spelling`: your own C spellings for characters in names, `Dict('ħ' => "hred",
  '∂' => "d")`, on top of the built-in ones (Julia's `\\name` completion table).
  Keys are single characters Julia allows in a name, other than ASCII letters,
  digits and `_`; values are C identifier text. See `doc/naming.md`.
- `width`: the longest line the C may have, in columns. A scalar expression
  that would run past it is wrapped at its loosest operators, each
  continuation line starting with the operator. See `doc/copy.md`.
- `c23floattypes`: write `Float64` and `Float32` as C23's `_Float64` and `_Float32`
  instead of `double` and `float`, wherever they appear.
- `goto`: may the C contain a `goto`? It is wanted for one thing only, a `break` that leaves a
  whole nest of loops, `for i in 1:n, j in 1:m`, which C has no other word for. With
  `goto=true` that is `goto done;` and a label after the nest, as many C programmers write
  it by hand. By default it is a flag that the outer loops test, `i <= n && !done`, which is
  what the coding guidelines for safety-critical C ask for, and there is no `goto` anywhere.
- `bool`: the C type for Julia's `Bool` — `Bool` itself, for C's `bool`, or one of
  Julia's integer types, `Int32` say, for that integer wherever a `Bool` appears:
  parameters, results, fields, elements, and the names that mention the type. The
  C then writes `0` and `1`, and reads any nonzero value as true.

Each function keeps its Julia name in C. If the same function is transpiled at more
than one signature in a single call, those get the argument types appended
(`fun1_Float64_Float64`) so the names don't collide.
"""
function transpile(target::Union{Function, Core.MethodInstance, Tuple{Union{Function, Symbol}, Vararg{Union{DataType, Integer}}},
                                 Tuple{typeof(broadcast), Function, Vararg{Union{DataType, Integer}}}, Type, Pair{Symbol, <:Any}, GlobalRef}...;
                   outfile::AbstractString="juliatranspiled", outpath::AbstractString=pwd(), split::Bool=false,
                   helper::AbstractString="helper",
                   templimit::Integer=40,
                   # On by default only until dynamic arrays are supported; then it flips
                   # to off, and static becomes something you opt into.
                   source::Bool=true,
                   precise::Bool=false,
                   width::Integer=100,
                   posix::Bool=false,
                   goto::Bool=false,
                   tempsuffix::Bool=false,
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
    LegibleC.posix[] = posix
    LegibleC.gotos[] = goto
    empty!(LegibleC.irrationals)
    local problem
    try
        return transpiled(target...; outfile, outpath, separate=split, helper=(endswith(helper, ".c") || endswith(helper, ".h") ? helper[1:end-2] : helper), templimit, source, precise, width, suffix=tempsuffix, scope, variables)
    catch e
        # A refusal, a fault already explained (`cfunction`), or the file system's own
        # complaint goes out as it is. Anything else is a mistake of the transpiler's made
        # outside any one function, and says so in place of a stack of its insides.
        (e isa ArgumentError || e isa Fault || e isa InterruptException || e isa SystemError || e isa Base.IOError) && rethrow()
        failure[] = (e, catch_backtrace())
        problem = Fault("the transpiler went wrong:\n  " * sprint(showerror, e) *
                        "\nThis is a mistake of LegibleC's, not of the Julia. Please report it with what was being transpiled; `LegibleC.failure[]` holds the error and its stack.")
    finally
        LegibleC.spelling[] = Dict{Char, String}()
        LegibleC.scope[] = Main
        LegibleC.c23floattypes[] = false
        LegibleC.posix[] = false
        LegibleC.gotos[] = false
        empty!(LegibleC.irrationals)
        LegibleC.booltype[] = Bool
    end
    throw(problem)
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

function transpiled(target...; outfile, outpath, separate, helper, templimit, source, precise, width, suffix, scope, variables)
    # The file names, checked before any work is done on their account.
    base = endswith(outfile, ".c") ? outfile[1:end-2] : outfile
    base == helper && throw(ArgumentError("`$helper.c` is the file the generated helpers go to; name the functions' file something else"))
    for name in (base, helper)
        name * ".h" in first.(standard) && throw(ArgumentError("`$name.h` would shadow the standard header <$name.h> for every file compiled with `-I out`; name it something else"))
    end
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
        elseif t isa Tuple && (t[1] isa Symbol || t[1] === broadcast)
            # A broadcast: an operator's symbol, `(:.+, Float64, 3, Float64)`, since `.+`
            # is no function; or Julia's own spelling of any function's, `(broadcast,
            # sqrt, Float64, 3)`. A stand-in method is its only form.
            f = t[1] isa Symbol ? t[1] : Broadcast(t[2])
            sig, _ = spectypes(t[(t[1] isa Symbol ? 2 : 3):end])   # static arrays, as `resolve` gives a function's
            mi = synthetic(f, sig, sig)
            synthetics[mi] = (f, sig)
        elseif t isa Tuple
            mi, sig = resolve(t[1], t[2:end])
            # Julia's own operator at these types — `(+, Float64, 3, Float64, 3)` — is
            # asked for by name, so the helper it would become is a function instead.
            nameof(Base.moduleroot(mi.def.module)) in known && (mi = synthetic(t[1], collect(mi.specTypes.parameters[2:end]), sig); synthetics[mi] = (t[1], sig))
            # An anonymous function, `(A -> sum(A; dims=1), Float64, 3, 3)`, `((A, B) -> A' * B,
            # …)`: an operation with no name of its own, so it must be one helper's, and
            # is promoted like an operator; more than that needs a name.
            startswith(string(mi.def.name), "#") && (synthetics[mi] = (t[1], sig))
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
    # A global that isn't `const`, given a value here, is that global, starting from that
    # value: `counter = 0` after a run has left it at 15.
    for (name, value) in pairs(variables)
        bound = isdefined(scope, name) && getfield(scope, name) === value
        if !bound && isdefined(scope, name) && !isconst(scope, name)
            T = Core.get_binding_type(scope, name)
            value = T === Any ? value : convert(T, value)
            bound = true
        end
        push!(values, (bound ? scope : nothing, name, value, bound ? nothing : true))
    end
    # Two instances that are the same method at signatures C can't tell apart — a
    # static and a mutable array of the same size, say — are one C function.
    unique!(inst -> (inst[1].def, csignature(inst[2])), instances)

    # The generation, as a function of what an earlier attempt settled: first come, first
    # served is how names are claimed while C is being written, and `audit` says afterwards
    # whether that gave a name to the wrong one. If so it is all done again, with those
    # names settled beforehand. Almost always once is enough.
    listed = copy(instances)
    local prog, names, functions
    fixed, avoid, nomacro = Dict{Any, String}(), Set{String}(), Set{String}()
    for attempt in 1:4
        instances = copy(listed)
        empty!(irrationals)
        prog, names, functions = build!(instances, synthetics, types, values, fixed, avoid, nomacro; precise, width, suffix, templimit, source)
        # A global's initializer can be the first place an irrational is met (`const τ = 2π`):
        # written now, so that its macro is known before the names are audited.
        files = unique(String(mi.def.file) for (mi, _) in instances)
        for g in prog.globals; globallines(g, files, source, ""); end
        again = audit(prog, fixed, avoid, nomacro)
        again || break
        attempt == 4 && throw(ArgumentError("the file-scope names of this program could not be settled; please report it"))
    end
    # A global that some function writes into is not `const` in C, whatever the Julia's
    # `const` says: that fixes the binding, and an `MVector`'s contents are still free.
    for (k, g) in enumerate(prog.globals)
        g.constant && (g.mod, g.name) in prog.written && (prog.globals[k] = Global(g.cname, g.mod, g.name, g.value, false))
    end
    # The helpers' names are known only now. A function that shares one is an error, since
    # its name is the C interface. (A local keeps clear of the file-scope names its own
    # function mentions — `ω` beside a global `omega` it reads — while it is named: `names!`.)
    for n in names
        haskey(prog.helpers, n) && !(n in prog.exported) && throw(ArgumentError("the function `$n` has the same name as the helper `$n` the output needs; rename it"))
    end
    dir = joinpath(outpath, "out")
    mkpath(dir)
    where, order = placement(prog, base, separate, names, helper)
    files = unique(String(mi.def.file) for (mi, _) in instances)   # where a global's line may be
    # The whole program's text, for the macros it uses.
    everything = String[]
    for f in functions; push!(everything, f[2], f[3]); end
    for g in prog.globals; append!(everything, globallines(g, files, source, "")); end
    append!(everything, Base.values(prog.helpers))
    for (_, def) in prog.structs; push!(everything, def); end
    for (_, def) in prog.tupledefs; push!(everything, def); end
    everything = join(everything, "\n")
    writehelpers(dir, prog, separate ? where : Dict(n => base for n in prog.exported), helper, everything)
    return writefiles(dir, prog, base, where, order, names, functions, helper, files, source, everything)
end


# One attempt at the whole program: the listed functions, whatever they call, and the
# operator targets that turn out to be a helper. `fixed` and `avoid` come from `audit`.
function build!(instances, synthetics, types, values, fixed, avoid, nomacro; precise, width, suffix, templimit, source)
    prog = Program(; precise, width, suffix, limit=templimit)
    merge!(prog.fixed, fixed)
    union!(prog.avoid, avoid)
    empty!(macroavoid); union!(macroavoid, nomacro)
    union!(prog.yielded, nomacro)
    # The listed functions are named first, together, so that one function at several
    # signatures gets its types appended; then each is claimed like any file-scope name.
    wanted = cnames(instances; settled=false)
    names = similar(wanted)
    for (k, (mi, _)) in enumerate(instances)
        if haskey(synthetics, mi)
            names[k] = startswith(string(mi.def.name), "#") ? "anonymous$k" : string(mi.def.name)      # a synthetic target's own name
            push!(prog.names, names[k])
        else
            names[k] = claim!(prog, mi, wanted[k], string(mi.def.name))
        end
        prog.calls[mi] = names[k]
    end
    for T in types
        structdef!(prog, T)
        # The struct's docstring, as a Doxygen block above its typedef.
        doc = strip(string(Base.Docs.doc(T)))
        startswith(doc, "No documentation found") && continue
        k = findfirst(p -> p.first === T, prog.structs)
        prog.structs[k] = T => "/**\n" * join(" * " .* split(doc, "\n"), "\n") * "\n */\n" * prog.structs[k].second
    end
    for (mod, name, value, constant) in values; global!(prog, mod, name, value; constant); end
    generate(n, mi, sig) = cfunction(n, mi, sig, prog; templimit, source=source && !haskey(synthetics, mi))
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
        anonymous = startswith(string(mi.def.name), "#")
        types = join(("::" * replace(string(T <: Shaped ? juliatype(T) : T), "StaticArraysCore." => "") for T in sig), ", ")
        julia = (f isa Symbol ? string(f) : f isa Broadcast ? string(nameof(f.f)) * "." : anonymous ? "" : string(nameof(f))) * "(" * types * ")"
        h = onlycall(functions[k][3], prog.helpers)
        if anonymous
            h === nothing && throw(ArgumentError("an anonymous target must be a single operation the transpiler has a helper for, like `A -> sum(A; dims=1)` or `(A, B) -> A' * B`; for anything more, give the function a name"))
            # `(::SMatrix{4, 2, Float64, 8}, ::SVector{4, Float64}) -> Aᵀ * b`: the helper's own step.
            step = replace(split(prog.helpers[h], "\n")[2], r"^/// (out = |returns )?" => "")
            julia *= " -> " * step
        end
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
    return prog, names, functions
end

# Did claiming names in the order things were met give one to the wrong thing? Two of the
# author's things with different Julia names that ask for the same C name: the one whose
# Julia name already is that name keeps it, whichever was met first; if that isn't how it
# came out, it is settled so (`fixed`) and the program built again. When neither or both
# can say so — `φ` and `ϕ`, both `phi` — there is no rule to choose by, and a silent `_` on
# one of two interface names is not a choice to make for the author: refused, by name.
# And a name of the author's that a typedef or a macro, met later, also came out as: those
# have no other spelling, so the author's is kept clear of it (`avoid`) and built again;
# except a macro of ours, which ranks below the author's names and is the one kept clear
# (`nomacro`).
function audit(prog::Program, fixed, avoid, nomacro)
    again = false
    for want in unique(c.preferred for c in prog.claims)
        group = [c for c in prog.claims if c.preferred == want]
        length(unique(c.julia for c in group)) > 1 || continue        # one function at several signatures: told apart by type
        exact = [c for c in group if c.julia == want]
        if length(exact) == 1
            exact[1].name == want && continue
            fixed[exact[1].key] = want
            again = true
        else
            listing = join(("`$(c.julia)`" for c in group), " and ")
            throw(ArgumentError("$listing both come out as `$want` in C, and neither is spelled that way in the Julia, so there is no saying which should keep it; rename one, or give one a spelling of its own with the `spelling` option"))
        end
    end
    structs = Set(structname(T) for (T, _) in prog.structs)
    others = union(structs, keys(prog.foreign), setdiff(keys(prog.helpers), prog.exported))
    for c in prog.claims
        c.name in others && !(c.name in avoid) && (push!(avoid, c.name); again = true)
    end
    # The names of ours give way to the author's: a macro, which rewrites a name wherever it
    # stands, so to a struct's members as well; and a tuple's struct, `step_t`, to a struct
    # or a function of the author's called that, whichever was met first.
    members = Set{String}()
    for (T, _) in prog.structs; isstruct(T) && union!(members, fieldcnames(T)); end
    for k in Base.values(prog.kinds); k isa Kind && union!(members, k.fields); end
    theirs = union(prog.names, structs, members)
    for m in keys(irrationals)
        m in theirs && !(m in nomacro) && (push!(nomacro, m); again = true)
    end
    for (n, _) in prog.tupledefs
        n in union(prog.names, structs) && !(n in nomacro) && (push!(nomacro, n); again = true)
    end
    return again
end

# Every name at file scope in the output: functions and globals, helpers, foreign
# wrappers, struct and tuple typedefs, and the macros for irrationals.
filescope(prog::Program) = union(prog.names, keys(prog.helpers), keys(prog.foreign), Set(structname(T) for (T, _) in prog.structs),
                                 Set(first.(prog.tupledefs)), keys(irrationals))

# A global with its value: its Julia line above it, as a statement's is, when the source
# is being copied — its trailing `# note` riding along, otherwise after the declaration
# — and the initializer written from that line's expression where it can be (`symbolic`),
# so `π` is the macro; from the value otherwise.
function globallines(g::Global, files, source::Bool, prefix; written::Bool=false, warn::Bool=false)
    # Several lines may assign a name like this one — `c` in a module and in a submodule of
    # it. The one whose expression agrees with the value Julia holds is the one; failing
    # that, the first whose expression can't be checked; never one that disagrees.
    found = [(src, symbolic(g, src.text)) for src in globalsource(g, files)]
    k = something(findfirst(p -> p[2] isa String, found), findfirst(p -> p[2] === nothing, found), 0)
    src, init = k == 0 ? (nothing, nothing) : found[k]
    # A global starts in C from the value it holds when it is transpiled: where Julia is now.
    # That is the one rule that always holds, since the same calls then give the same results in
    # both from here on. For a global the C writes, that value may be one an earlier run left
    # behind, and the author is told: the one line that assigns it disagrees with it, which is
    # said beside the value in the C and as a warning, with the two ways to start elsewhere.
    stale = nothing
    if written && k == 0 && length(found) == 1 && found[1][2] === false
        src = found[1][1]
        rhs = assigned(try Meta.parse(src.text) catch; nothing end, g.name)
        first = rhs !== nothing && crender(rhs, g.mod) !== nothing ? (try Core.eval(g.mod, rhs) catch; nothing end) : nothing
        stale = "the value when transpiled" * (first === nothing ? "" : ", not the $(first) of the line above")
        warn && @warn "`$(g.name)` holds $(g.value) now, which isn't what its defining line gives it ($(src.file):$(src.line): $(src.text)). The C starts from $(g.value), where Julia is now. To start from another value, transpile before running anything that changes `$(g.name)`, or pass `$(g.name) = …` to `transpile`."
    end
    lines = String[]
    source && src !== nothing && push!(lines, "// @$(src.file):$(src.line): $(src.text)")
    push!(lines, prefix * globaldecl(g; note=stale !== nothing ? stale : source && src !== nothing ? nothing : src === nothing ? nothing : src.note, text=init))
    return lines
end

# Methods made on request stand in for Julia's own operators as targets (`synthetic`).
module Synthetic end

# A function broadcast asked for as a target, `(broadcast, sqrt, Float64, 3)`.
struct Broadcast
    f::Function
end

# A stand-in for Julia's operator `f` at the argument `types` — or for a broadcast,
# `f` an operator's symbol, `:.+`, or a `Broadcast`: a method of `Synthetic` named by
# the helper scheme, `add_3`, `addP_3_s`, `sqrtP_3`, whose body is the call. The C it
# makes is what the operator becomes anywhere, and now under a name of its own.
function synthetic(f, types, sig)
    # `a`, `b`, `c`, as a helper names them, and `A` for a matrix.
    args = [Symbol(T <: AbstractArray && ndims(T) >= 2 ? uppercase('a' + k - 1) : 'a' + k - 1) for (k, T) in enumerate(types)]
    params = [Expr(:(::), a, T) for (a, T) in zip(args, types)]
    if f isa Symbol
        s = string(f)
        startswith(s, ".") && length(s) > 1 && Base.isoperator(Symbol(s[2:end])) ||
            throw(ArgumentError("a broadcast target is an operator's dotted symbol, `:.+`, or `(broadcast, f, types...)`; got :$f"))
        body = Expr(:call, f, args...)
        name = Symbol(replace(operatorname(Symbol(s[2:end]), sig), "_" => "P_"; count=1))
    elseif f isa Broadcast
        body = Expr(:., f.f, Expr(:tuple, args...))
        name = Symbol(replace(operatorname(nameof(f.f), sig), "_" => "P_"; count=1))
    else
        body = Expr(:call, f, args...)
        name = Symbol(operatorname(nameof(f), sig))
    end
    # Built without line numbers, so the method has no source to quote from.
    made = Core.eval(Synthetic, Expr(:(=), Expr(:call, name, params...), Expr(:block, body)))
    return Base.method_instance(made, Tuple(types))
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

# The `#define`s a text needs, for the helper header: each irrational it uses, to
# 128-bit precision — the compiler rounds the literal to the double nearest it, and a
# `long double` build keeps more of it — and the guards for POSIX's `M_PI` and for
# `CMPLX`. A file that uses any of them includes that header.
function defines(text)
    lines = String[]
    for name in sort!(collect(keys(irrationals)))
        occursin(Regex("\\b" * name * "\\b"), text) || continue
        push!(lines, "#define $name $(digits128(irrationals[name]))  // $(irrationalname(irrationals[name])) to 128-bit precision")
    end
    return [lines; mathguards(text)]
end
usesdefine(text) = any(occursin(Regex("\\b" * name * "\\b"), text) for name in keys(irrationals)) || occursin(r"\b(M_PI|M_E)\b|\bCMPLXF?\(", text)

# A constant to 128-bit precision: the digits of the binary128 nearest it, 113 bits.
digits128(x) = setprecision(BigFloat, 113) do; string(BigFloat(x)); end

# `M_PI` and `M_E` are POSIX, not ISO C: glibc's <math.h> leaves them out under a strict
# `-std=c11`. A file that uses one defines it itself if the header didn't, the way C
# programmers do.
function mathguards(text)
    lines = String[]
    for (m, v) in (("M_PI", π), ("M_E", ℯ))
        occursin(Regex("\\b$m\\b"), text) || continue
        append!(lines, ["#ifndef $m", "#define $m $(digits128(v))  // not in ISO C; absent under a strict -std=c11", "#endif"])
    end
    # C11's `CMPLX` builds a complex from its parts exactly; an older <complex.h> lacks it.
    for (m, t) in (("CMPLX", "double"), ("CMPLXF", "float"))
        occursin(Regex("\\b$m\\("), text) || continue
        append!(lines, ["#ifndef $m", "#define $m(x, y) __builtin_complex(($t)(x), ($t)(y))  // C11; here if <complex.h> predates it", "#endif"])
    end
    return lines
end

# `helper.h` and `helper.c`: everything generated that the user's functions need —
# `add_3`, `solve_4x4_4`, `powi`, `printarray_F64`. The header holds what the helpers
# need — standard includes, typedefs — the macros the whole program uses (`LEGIBLEC_PI`;
# `everything` is the program's text), plus prototypes of the out-of-line helpers and
# the inline ones themselves; the `.c` holds the out-of-line ones, and is written only
# when there is one. A struct a helper mentions is defined here, unless `external`
# names the header that has it, which is then included.
function writehelpers(dir, prog::Program, external, helper, everything)
    order = filter(!in(prog.exported), helperorder(prog.helpers))
    # Helper names are reserved by their shape (`ishelpername`). One the shape doesn't know
    # is still kept clear of here, being emitted (`claim!`, `audit`); what it loses is only
    # that an author's function of that name is renamed in programs that don't emit it
    # too. Noted, for the test suite to insist the set stays empty.
    for n in keys(prog.helpers)
        ishelpername(n) || push!(unrecognized, n)
    end
    used = defines(everything)
    isempty(order) && isempty(used) && return
    text = join((prog.helpers[n] for n in order), "\n")
    inline = [n for n in order if isinline(prog.helpers[n])]
    outline = [n for n in order if !isinline(prog.helpers[n])]
    guard = guardname("LEGIBLEC_" * uppercase(identifier(helper)) * "_H", everything)
    htext = String[]
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
    open(joinpath(dir, helper * ".h"), "w") do io
        println(io, "#ifndef $guard\n#define $guard\n")
        for h in includes(hbody); println(io, "#include <", h, ">"); end
        for h in unique(headers); println(io, "#include \"$h.h\""); end
        isempty(includes(hbody)) && isempty(headers) || println(io)
        print(io, rstrip(hbody)); println(io); println(io)
        println(io, "#endif  // $guard")
    end
    isempty(outline) && return
    open(joinpath(dir, helper * ".c"), "w") do io
        for h in includes(ctext); println(io, "#include <", h, ">"); end
        println(io, "#include \"$helper.h\"")
        for name in outline; println(io); print(io, prog.helpers[name]); end
    end
end

# Which file each C name goes to, and the files in order. In one file: everything but
# the helpers, and a struct the helpers mention goes with them. Split: every function
# in a file named after it, listed or not; every struct in a header of its own; a
# function's return struct with that function; the globals and the foreign wrappers
# in `<base>`. Names that differ only in case share a file — `point` and `Point`,
# which one file system in three would merge anyway — named in lowercase.
function placement(prog::Program, base, split::Bool, names, helper)
    where = Dict{String, String}()
    helpertext = join(values(prog.helpers), "\n")
    for n in names; where[n] = split ? n : base; end
    for g in prog.globals; where[g.cname] = base; end
    for n in keys(prog.foreign); where[n] = base; end
    for (T, _) in prog.structs
        n = structname(T)
        where[n] = split ? n : mentions(helpertext, n) ? helper : base
    end
    for (n, _) in prog.tupledefs
        owner = endswith(n, "_t") ? get(where, n[1:end-2], nothing) : nothing
        where[n] = !split ? base : owner === nothing ? n : owner
    end
    files = [base; [where[n] for n in names]; [where[structname(T)] for (T, _) in prog.structs]; [where[n] for (n, _) in prog.tupledefs]]
    filter!(!=(helper), files)
    canon = Dict(key => (spellings = unique(f for f in files if lowercase(f) == key); length(spellings) == 1 ? only(spellings) : key)
                 for key in unique(lowercase.(files)))
    for (n, f) in where; f == helper || (where[n] = canon[lowercase(f)]); end
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
# A header's include guard. It is a macro, and a macro rewrites every later use of its
# name whatever that names — a global `GUARD_H`, a local, a struct's member — so it is
# checked against every word of the program and gives way with `_`.
function guardname(guard, everything)
    while occursin(Regex("\\b" * guard * "\\b"), everything)
        guard *= "_"
    end
    return guard
end

function writefiles(dir, prog::Program, base, where, order, names, functions, helper, files, source::Bool, everything)
    declared(g::Global, prefix) = globallines(g, files, source, prefix; written=(g.mod, g.name) in prog.written, warn=true)
    definition = Dict(zip(names, (f[3] for f in functions)))
    # What each file defines, for the includes: functions and foreign wrappers are looked
    # for as calls, the rest as words.
    entities = Dict(f => Tuple{String, Bool}[] for f in order)
    for (n, f) in where
        haskey(entities, f) && push!(entities[f], (n, haskey(definition, n) || haskey(prog.foreign, n)))
    end
    helperstructs = [structname(T) for (T, _) in prog.structs if where[structname(T)] == helper]
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
        for (k, g) in enumerate(gls)
            inheader(g) || (push!(body, "extern " * globaldecl(g; value=false)); continue)
            lines = declared(g, "static ")
            length(lines) > 1 && k > 1 && push!(body, "")
            append!(body, lines)
        end
        isempty(gls) || push!(body, "")
        append!(body, protos)
        htext = join(body, "\n")
        guard = guardname(uppercase(identifier(file)) * "_H", everything)
        header = ["#ifndef $guard", "#define $guard", ""]
        n0 = length(header)
        for h in includes(htext); push!(header, "#include <$h>"); end
        (any(mentions(htext, n) for n in helperstructs) || usesdefine(htext)) && push!(header, "#include \"$helper.h\"")
        included = [f for f in order if f != file && (umbrella && file == base || needs(htext, f))]
        for f in included; push!(header, "#include \"$f.h\""); end
        length(header) > n0 && push!(header, "")
        push!(header, rstrip(htext), "", "#endif  // $guard")
        write(joinpath(dir, file * ".h"), join(header, "\n") * "\n")
        # The `.c`: the includes it needs beyond its own header, then the mutable globals
        # with their values, then the definitions. Nothing to hold, no file.
        cglobals = String[]
        for g in gls
            inheader(g) && continue
            lines = declared(g, "")
            length(lines) > 1 && !isempty(cglobals) && push!(cglobals, "")
            append!(cglobals, lines)
        end
        defs = [functions[k][3] for k in fns]
        isempty(cglobals) && isempty(defs) && isempty(fgn) && continue
        ctext = join([cglobals; fgn; defs], "\n")
        path = joinpath(dir, file * ".c")
        push!(paths, path)
        open(path, "w") do io
            for h in includes(ctext); println(io, "#include <", h, ">"); end
            (any(mentions(ctext, n; call=true) for n in keys(prog.helpers) if !(n in prog.exported)) || any(mentions(ctext, n) for n in helperstructs) || usesdefine(ctext)) && println(io, "#include \"$helper.h\"")
            for f in order; f != file && needs(ctext, f) && !(f in included) && println(io, "#include \"$f.h\""); end
            println(io, "#include \"$file.h\"")
            println(io)
            foreach(g -> println(io, g), cglobals); isempty(cglobals) || println(io)
            foreach(x -> println(io, x), fgn); isempty(fgn) || println(io)
            for (k, d) in enumerate(defs); k == 1 || println(io); print(io, d); end
        end
    end
    return length(paths) == 1 ? paths[1] : paths
end

# A spec's types — each a type, optionally followed by the dimensions of an array —
# as static arrays, as the shaped signature, and as (element type, dimensions) pairs.
function spectypes(spec)
    (isempty(spec) || spec[1] isa Integer) && throw(ArgumentError("in $(spec), a type must come first, then any dimensions of an array"))
    groups = Tuple{DataType, Vector{Int}}[]
    for x in spec
        x isa DataType ? push!(groups, (x, Int[])) : push!(groups[end][2], x)
    end
    static = [isempty(d) ? T : SArray{Tuple{d...}, T, length(d), prod(d)} for (T, d) in groups]
    shapedsig = [isempty(d) ? T : shaped(T, d) for (T, d) in groups]
    return static, shapedsig, groups
end

# What each standard header provides, as a pattern over the C text that uses it.
const standard = (
    ("stdint.h", r"\b(u?int(8|16|32|64)_t)\b"),
    ("stdbool.h", r"\b(bool|true|false)\b"),
    ("stdlib.h", r"\b(llabs|abs|exit|abort|malloc|calloc|free)\("),
    ("string.h", r"\b(memcpy|memset|memmove|memcmp|strcmp|strlen|strcpy|strncpy|strcat|strchr|strstr)\("),
    ("ctype.h", r"\b(isdigit|isalpha|isspace|isupper|islower|ispunct|iscntrl|isprint|isxdigit|toupper|tolower)\("),
    ("stdio.h", r"\b(printf|fprintf|snprintf|fputs|fputc|putchar|puts|fflush|fopen|fclose|FILE|stdout|stderr)\b"),
    ("float.h", r"\b(DBL|FLT)_(EPSILON|MAX|MIN)\b"),
    ("complex.h", r"\b(creal|cimag|conj|cabs|carg|csqrt|cexp|clog|cpow|csin|ccos|ctan|casin|cacos|catan|csinh|ccosh|ctanh|cproj)f?\(|\bCMPLXF?\(|\b(double|float) complex\b|\bI\b"),
    ("math.h", r"\b(sqrt|cbrt|sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|asinh|acosh|atanh|exp|exp2|expm1|log|log2|log10|log1p|floor|ceil|trunc|rint|round|hypot|copysign|fabs|fmax|fmin|fmod|remainder|fma|nextafter|ilogb|frexp|modf|pow|ldexp|tgamma|lgamma|erf|erfc|isnan|isinf|isfinite|signbit)f?\(|\b(M_PI|M_E|INFINITY|NAN)\b"),
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
function cnames(instances; settled::Bool=true)
    base = [qualified(operatorname(mi.def.name, sig), mi.def.module) for (mi, sig) in instances]
    names = similar(base)
    # One Julia function at several signatures gets its types appended. Grouped by the
    # function, not by the spelling: `ω` and `omega` are two functions, not two signatures.
    which = [(b, mi.def.module, mi.def.name) for (b, (mi, _)) in zip(base, instances)]
    for w in unique(which)
        group = findall(==(w), which)
        names[group] = mangled(w[1], [sig for (_, sig) in instances[group]])
    end
    # Unsettled: spelled as C, but not yet kept apart from each other or from C's own
    # words. That is `claim!`'s to do, which also remembers what each one asked for.
    return settled ? identifiers(names) : identifier.(names)
end

argtypes(mi::Core.MethodInstance) = Type[normalize(T) for T in mi.specTypes.parameters[2:end]]

# A signature as C sees it: every array reduced to element type and size.
csignature(sig) = [isarray(T) ? shaped(eltype(T), shape(T)) : T for T in sig]

# Resolve a tuple target's specification — types, each optionally followed by the
# integer dimensions of an array — to a MethodInstance and a signature.
function resolve(f::Function, spec)
    isempty(spec) && return (concretemethod(f)[1], argtypes(concretemethod(f)[1]))
    all(x -> x isa DataType, spec) && (mi = concretemethod(f, spec...)[1]; return (mi, argtypes(mi)))
    static, shapedsig, groups = spectypes(spec)
    # Arrays are static if the function takes them that way, else regular arrays of
    # the same size, which the transpiler treats identically.
    regular = [isempty(d) ? T : Array{T, length(d)} for (T, d) in groups]
    mi = exact(Base.method_instance(f, Tuple(static)), Tuple{typeof(f), static...})
    mi === nothing || return (mi, static)
    mi = exact(Base.method_instance(f, Tuple(regular)), Tuple{typeof(f), regular...})
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

# `SMatrix{3,3,Float64}` as people write it leaves out the last parameter, the number of
# elements, which the size already says. So does `MMatrix{3,3,Float64}`. It is filled in.
function completed(P)
    P isa UnionAll || return P
    u = Base.unwrap_unionall(P)
    u isa DataType && u <: StaticArrays.StaticArray && length(u.parameters) == 4 || return P
    S, E, N, L = u.parameters
    S isa DataType && isconcretetype(E) && all(d -> d isa Int, S.parameters) && L isa TypeVar || return P
    return u.name.wrapper{S, E, length(S.parameters), prod(S.parameters; init=1)}
end

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
        ms = filter(m -> !(m.sig isa UnionAll) && all(P -> isconcretetype(completed(P)), m.sig.parameters[2:end]), methods(f))
        isempty(ms) && throw(ArgumentError("$f has no method with concrete argument types; give the types explicitly"))
        length(ms) > 1 && throw(ArgumentError("$f has $(length(ms)) methods with concrete argument types; give the types to pick one"))
        T = Tuple(completed(P) for P in only(ms).sig.parameters[2:end])
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

