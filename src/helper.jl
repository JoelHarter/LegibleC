# Linear algebra helpers: one C function per (operation, argument types), generated on
# demand while a function is being emitted and written out once, ahead of everything
# that calls them.
#
# Arrays in C are fixed-size and row-major, passed as array parameters so the compiler
# knows their shape (`const double a[2][2]`), and every helper writes its output into
# its last parameter. Loops are ordered for C's memory layout, not Julia's.

"""
    helper!(helpers, op, types, R) -> name

Make sure the helper for `op` on argument `types`, producing `R`, is in `helpers`,
and return its C name. `op` is one of `:add`, `:sub`, `:neg`, `:mul`, `:copy`.
"""
function helper!(helpers::Dict{String, String}, op::Symbol, types, R::Type)
    name = helpername(op, types)
    haskey(helpers, name) || (helpers[name] = helpercode(name, op, types, R))
    return name
end

# Helper names always carry size and type: `add_2x2`, `mul_2x2_2`, `add_2x2F64_2x2F32`.
# Arrays are described by dimensions, plus element type unless everything is Float64;
# scalars always by type. Arguments with identical descriptions are written once.
function helpername(op::Symbol, types)
    alldouble = all(T -> (T <: AbstractArray ? eltype(T) : T) === Float64, types)
    descs = [T <: AbstractArray ? dims(T) * (alldouble ? "" : abbrev(eltype(T))) : abbrev(T)
             for T in types]
    allequal(descs) && (descs = descs[1:1])
    return string(op, "_", join(descs, "_"))
end

# The C definition of one helper.
function helpercode(name::AbstractString, op::Symbol, types, R::Type)
    argnames = ["a", "b"][1:length(types)]
    params = [declare(T, n; constant=true) for (T, n) in zip(types, argnames)]
    push!(params, declare(R, "out"))
    body = if op in (:add, :sub)
        a, b = types
        shape(a) == shape(b) || throw(ArgumentError("$op: dimensions don't match, $(dims(a)) and $(dims(b))"))
        elementwise(shape(R), sub -> "out$sub = a$sub $(op == :add ? "+" : "-") b$sub;")
    elseif op == :neg
        elementwise(shape(R), sub -> "out$sub = -a$sub;")
    elseif op == :copy
        elementwise(shape(R), sub -> "out$sub = a$sub;")
    elseif op == :mul
        multiply(types, R)
    else
        throw(ArgumentError("unsupported array operation: $op"))
    end
    return "static void $name($(join(params, ", "))) {\n" * join(body, "\n") * "\n}\n"
end

# Nested loops over `shape`, with `line(sub)` innermost, where `sub` is the index
# expression, e.g. `[i][j]`.
function elementwise(shape, line::Function; indent="    ")
    idx = ["i", "j", "k", "l", "m", "n"][1:length(shape)]
    lines = String[]
    for (d, n) in enumerate(shape)
        push!(lines, indent^d * "for (int $(idx[d]) = 0; $(idx[d]) < $n; $(idx[d])++) {")
    end
    push!(lines, indent^(length(shape) + 1) * line("[" * join(idx, "][") * "]"))
    for d in length(shape):-1:1
        push!(lines, indent^d * "}")
    end
    return lines
end

# The body of `mul`, following Julia's rules for what `*` means on each pair of
# argument kinds.
function multiply(types, R::Type)
    a, b = types
    zero = ctype(eltype(R)) == "float" ? "0.0f" : eltype(R) <: AbstractFloat ? "0.0" : "0"
    if !(a <: AbstractArray)                                   # scalar * array
        return elementwise(shape(R), sub -> "out$sub = a * b$sub;")
    elseif !(b <: AbstractArray)                               # array * scalar
        return elementwise(shape(R), sub -> "out$sub = a$sub * b;")
    elseif ndims(a) == 2 && ndims(b) == 1                      # matrix * vector
        (m, k) = shape(a)
        k == shape(b)[1] || throw(ArgumentError("mul: dimensions don't match, $(dims(a)) and $(dims(b))"))
        return ["    for (int i = 0; i < $m; i++) {",
                "        $(ctype(eltype(R))) sum = $zero;",
                "        for (int k = 0; k < $k; k++) {",
                "            sum += a[i][k] * b[k];",
                "        }",
                "        out[i] = sum;",
                "    }"]
    elseif ndims(a) == 2 && ndims(b) == 2                      # matrix * matrix
        (m, k) = shape(a)
        (k2, n) = shape(b)
        k == k2 || throw(ArgumentError("mul: dimensions don't match, $(dims(a)) and $(dims(b))"))
        # i-k-j order: the inner loop walks a row of `out` and a row of `b`, both
        # contiguous in row-major storage.
        return ["    for (int i = 0; i < $m; i++) {",
                "        for (int j = 0; j < $n; j++) {",
                "            out[i][j] = $zero;",
                "        }",
                "        for (int k = 0; k < $k; k++) {",
                "            for (int j = 0; j < $n; j++) {",
                "                out[i][j] += a[i][k] * b[k][j];",
                "            }",
                "        }",
                "    }"]
    end
    throw(ArgumentError("mul: unsupported operand shapes $(dims(a)) and $(dims(b))"))
end
