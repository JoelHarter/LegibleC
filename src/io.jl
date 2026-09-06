# Input and output: printing to the screen now, files later. Everything the transpiler
# does with streams lives here, apart from the rest of the emitter, because it is its
# own kind of thing: the C is `printf` and friends rather than arithmetic, and the
# shapes of the Julia are `print(io, x)` and `@printf`.
#
# The C is what a C programmer writes, not a rendering of Julia's output: `printf` with
# `%g` for a floating value (`%.17g` under the `precise` option), `%lld` for an integer,
# `%d` for a boolean, and one helper, `printarray`, for arrays — one row per line, a
# blank line between 2-D slices, two between 3-D blocks, the numbers in right-aligned
# fields. The stream comes first everywhere, as in Julia's `print(io, x)`, so `stdout`,
# `stderr`, and a file opened later all go through the same code.

# ---- print, println, @printf ------------------------------------------------------

# The `printf` conversion for a scalar of type `T`: `%g` for a floating value, or every
# digit that reads back exactly under `precise`; `%lld`/`%llu` for integers, `%d` for a
# boolean. `width` right-aligns it in a field wide enough for the longest value.
function conversion(T::Type; precise::Bool=false, width::Bool=false)
    T === Bool && return width ? "%12d" : "%d"
    T === Char && return "%c"
    T <: AbstractString && return "%s"
    T <: Unsigned && return width ? "%12llu" : "%llu"
    T <: Integer && return width ? "%12lld" : "%lld"
    T <: AbstractFloat || throw(ArgumentError("printing a $T is not supported"))
    digits = T === Float32 ? 9 : 17
    precise || return width ? "%12g" : "%g"
    return width ? "%$(digits + 8).$(digits)g" : "%.$(digits)g"
end

# The `printf` argument for a scalar value: integers cast to the width the conversion
# names, since `int64_t`'s own format needs a macro.
argument(T::Type, x) = T === Bool ? (booltype[] === Bool ? x : "$x != 0") : T <: Unsigned ? "(unsigned long long)$x" : T <: Integer ? "(long long)$x" :
                       c23float[] ? "(double)$x" : x       # a `_FloatN` isn't promoted for `...`

# `"stdout"` or `"stderr"` if the IR value is that global (by name, since a test may have
# redirected the streams), else nothing. A file handle will join these later.
function stream(sc::Scope, x)
    x isa Core.SSAValue && (x = sc.ci.code[x.id])
    x isa GlobalRef && x.name in (:stdout, :stderr) && return string(x.name)
    return nothing
end

# `print` and `println`, to `stdout` or to a stream given first: one `printf` per run
# of strings and scalars, and a `printarray` call for each array. An interpolated
# string, `"x = $x"`, arrives as `string(…)` and prints piece by piece the same way;
# `@show x` arrives as `println("x = ", repr(x))`, and `repr` of a number or array
# prints as the value.
function print!(lines, sc::Scope, args, newline::Bool)
    push!(sc.headers, "stdio.h")
    io = "stdout"
    if !isempty(args) && stream(sc, args[1]) !== nothing
        io = stream(sc, args[1])
        args = args[2:end]
    end
    pieces = Any[]
    function flatten(a)
        if a isa Core.SSAValue && sc.ci.code[a.id] isa Expr && sc.ci.code[a.id].head === :call
            f = callee_or_nothing(sc.ci, sc.ci.code[a.id].args[1])
            f === Base.string && return foreach(flatten, sc.ci.code[a.id].args[2:end])
            f === Base.repr && length(sc.ci.code[a.id].args) == 2 && return flatten(sc.ci.code[a.id].args[2])
        end
        push!(pieces, a)
    end
    foreach(flatten, args)
    fmt = ""
    fargs = String[]
    function flush()
        isempty(fmt) && return
        call = io == "stdout" ? "printf(" : "fprintf($io, "
        emit!(lines, sc, call * "\"$fmt\"" * (isempty(fargs) ? "" : ", " * join(fargs, ", ")) * ");")
        fmt = ""
        empty!(fargs)
    end
    for a in pieces
        v = literal(sc, a)
        T = valuetype(sc, a)
        if v isa AbstractString
            fmt *= cstring(v; format=true)
        elseif isarray(T)
            flush()
            printarray!(lines, sc, io, a)
        else
            fmt *= conversion(T; precise=sc.prog.precise)
            t, p = expression(sc, a)
            push!(fargs, argument(T, p < UNARY ? "($t)" : t))
        end
    end
    newline && (fmt *= "\\n")
    flush()
end

# `@printf`: Julia's format string is already C's, so it passes through, with `%d` and
# friends widened to `%lld` for a 64-bit integer.
function printf!(lines, sc::Scope, args)
    push!(sc.headers, "stdio.h")
    io = "stdout"
    if !isempty(args) && stream(sc, args[1]) !== nothing
        io = stream(sc, args[1])
        args = args[2:end]
    end
    format = literal(sc, args[1])
    format isa Printf.Format || throw(ArgumentError("@printf needs a literal format string"))
    text = String(copy(format.str))
    values = args[2:end]
    specs = collect(eachmatch(r"%[-+ #0]*\d*(?:\.\d+)?([a-zA-Z])", text))
    length(specs) == length(values) || throw(ArgumentError("@printf: $(length(specs)) conversions for $(length(values)) values"))
    cargs = String[]
    for (m, a) in zip(specs, values)
        T = valuetype(sc, a)
        c = m.captures[1]
        if c in ("d", "i", "u", "x", "X", "o")
            T <: Integer || throw(ArgumentError("@printf: %$c needs an integer, got $T"))
            wide = (c == "u" || T <: Unsigned) ? "llu" : c == "x" ? "llx" : c == "X" ? "llX" : c == "o" ? "llo" : "lld"
            text = replace(text, m.match => m.match[1:end-1] * wide; count=1)
            push!(cargs, "($(T <: Unsigned || !(c in ("d", "i")) ? "unsigned long long" : "long long"))$(value(sc, a))")
        elseif c == "s"
            v = literal(sc, a)
            v isa AbstractString || throw(ArgumentError("@printf: %s needs a string literal"))
            push!(cargs, "\"" * cstring(v) * "\"")
        else
            push!(cargs, value(sc, a))
        end
    end
    call = io == "stdout" ? "printf(" : "fprintf($io, "
    emit!(lines, sc, call * "\"$(cstring(text; format=true, keep=true))\"" * (isempty(cargs) ? "" : ", " * join(cargs, ", ")) * ");")
end

# A Julia string as the inside of a C string literal. With `format`, a `%` that isn't
# already a conversion is doubled so the string can be a `printf` format (`keep` leaves
# every `%` alone: the text is already a format).
function cstring(s::AbstractString; format::Bool=false, keep::Bool=false)
    out = replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\t" => "\\t", "\r" => "\\r")
    format && !keep && (out = replace(out, "%" => "%%"))
    return out
end

# ---- arrays ----------------------------------------------------------------------

# Print the array value `a` to `io`: `printarray(stdout, &A[0][0], 2, (const int[]){2, 3});`.
# A transposed value is copied into its real layout first, since the helper walks the
# storage as it is.
function printarray!(lines, sc::Scope, io, a)
    T = valuetype(sc, a)
    x = value(sc, a)
    if istransposed(T)
        R = plain(juliatype(T))
        t = temp!(sc, nothing, contribution(sc, a))
        emit!(lines, sc, declare(R, t) * ";")
        copy!(lines, sc, x, T, t, R)
        T, x = R, t
    end
    pointer = ndims(T) == 1 ? x : "&" * x * "[0]"^ndims(T)
    dims = "(const int[]){$(join(shape(T), ", "))}"
    emit!(lines, sc, "$(printarrayhelper!(sc.helpers, eltype(T); precise=sc.prog.precise))($io, $pointer, $(ndims(T)), $dims);")
end

# The one array-printing helper, per element type: `printarray` for doubles,
# `printarray_F32`, `printarray_I64`, `printarray_B` — the shape is a runtime argument,
# so the name has only the element type to say, as `cross` does. One row per line, a
# blank line between 2-D slices, two between 3-D blocks: after each element, count how
# many dimensions end there — none means a space, one the end of a row, each further
# one a blank line. Nothing after the last element, so `println` adds the newline as it
# does for a scalar. Fields are right-aligned so columns line up.
function printarrayhelper!(helpers::Dict{String, String}, E::Type; precise::Bool=false)
    name = "printarray" * (E === Float64 ? "" : "_" * abbrev(E))
    haskey(helpers, name) && return name
    body = ["int n = 1;",
            "for (int d = 0; d < ndims; d++) {",
            "    n *= dims[d];",
            "}",
            "for (int k = 0; k < n; k++) {",
            "    fprintf(f, \"$(conversion(E; precise, width=true))\", $(argument(E, "a[k]")));",
            "    if (k == n - 1) {",
            "        break;",
            "    }",
            "    int ended = 0;",
            "    for (int d = ndims - 1, stride = 1; d >= 0 && (k + 1) % (stride *= dims[d]) == 0; d--) {",
            "        ended++;",
            "    }",
            "    for (int i = 0; i < ended; i++) {",
            "        fputc('\\n', f);",
            "    }",
            "}"]
    helpers[name] = definition("void", name, ["FILE *f", "const $(ctype(E)) *a", "int ndims", "const int dims[]"], body;
                               doc=["print an array of $E: one row per line, a blank line between 2-D slices, two between 3-D blocks",
                                    "@param a      the elements, row-major, as every array here is stored",
                                    "@param ndims  how many dimensions",
                                    "@param dims   their sizes"], inline=false)
    return name
end
