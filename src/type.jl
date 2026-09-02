# The scalar types the transpiler supports: what Julia calls each, what C calls it, and
# the abbreviation used when a type has to appear in a mangled name. The same table
# is written up in doc/type.md; keep the two in step.

# (Julia, C, abbreviation)
const scalars = (
    (Bool,    "bool",     "B"),
    (Int8,    "int8_t",   "I8"),
    (UInt8,   "uint8_t",  "U8"),
    (Int16,   "int16_t",  "I16"),
    (UInt16,  "uint16_t", "U16"),
    (Int32,   "int32_t",  "I32"),
    (UInt32,  "uint32_t", "U32"),
    (Int64,   "int64_t",  "I64"),
    (UInt64,  "uint64_t", "U64"),
    (Float32, "float",    "F32"),
    (Float64, "double",   "F64"),
)

# The C spelling of a Julia type.
function ctype(T::Type)
    for (julia, c, _) in scalars
        T === julia && return c
    end
    T <: Complex && throw(ArgumentError("complex numbers are not yet supported (got $T)"))
    T <: AbstractArray && throw(ArgumentError("arrays are not yet supported (got $T)"))
    throw(ArgumentError("no C type for $T"))
end

# The abbreviation for a scalar type in a mangled name.
function abbrev(T::Type)
    for (julia, _, a) in scalars
        T === julia && return a
    end
    throw(ArgumentError("no abbreviation for $T"))
end

# The fixed size an array type carries, or nothing if it doesn't (a regular Array).
# Static array types define `size` on the type itself; that's the test, so no package
# is required.
shape(T::Type) = hasmethod(size, (Type{T},)) ? size(T) : nothing

# A regular `Array{T,N}` whose size the transpiler was told. Stands in for the real
# type everywhere a size is needed, so that regular and static arrays go through the
# same code and come out as the same C. Never instantiated.
struct Shaped{T, S, N} <: AbstractArray{T, N} end
Base.size(::Type{Shaped{T, S, N}}) where {T, S, N} = S
shaped(T::Type, s) = Shaped{T, Tuple(s), length(s)}


# A row vector: the transpose of a vector. Stored in C exactly like the vector it came
# from — `double r[3]` — but every helper treats it as 1×N, and it's named `r3`.
struct Row{T, N} <: AbstractArray{T, 1} end
Base.size(::Type{Row{T, N}}) where {T, N} = (N,)
isrow(T::Type) = T <: Row

# Julia's lazy `Adjoint`/`Transpose` wrappers, as the transpiler sees them: a wrapped
# vector is a `Row`; a wrapped matrix is the transposed shape. Everything else passes.
function normalize(T::Type)
    T === Union{} && return T
    T <: LinearAlgebra.Adjoint || T <: LinearAlgebra.Transpose || return T
    P = T.parameters[2]
    s = shape(P)
    s === nothing && return T
    length(s) == 1 && return Row{eltype(T), s[1]}
    P <: Row && return shaped(eltype(T), s)
    return shaped(eltype(T), reverse(s))
end

# The dimensions of an array type as they appear in a mangled name: `3`, `2x3`, `4x3x4`;
# `r3` for a row vector. Under `staticarray` a regular array is treated exactly like a
# static one, so it needs a size too; until there's a way to supply one, it's an error
# rather than a guess.
function dims(T::Type)
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    return (isrow(T) ? "r" : "") * join(s, "x")
end

# An array's *logical* shape, the one the mathematics sees: a vector is N×1, a row
# vector is 1×N, anything else is its own shape. A scalar is 1×1.
function bshape(T::Type)
    T <: AbstractArray || return (1, 1)
    isrow(T) && return (1, shape(T)[1])
    s = shape(T)
    return length(s) == 1 ? (s[1], 1) : s
end

# Which logical dimensions an array type stores, in storage order. A row vector stores
# only its column dimension; everything else stores every dimension in order. With
# `bshape`, this is all a helper needs to index any array the same way.
stored(T::Type) = isrow(T) ? [2] : collect(1:ndims(T))

# A C declaration of `name` with type `T`: `double x`, `const double a[2][2]`.
function declare(T::Type, name::AbstractString; constant::Bool=false)
    T <: AbstractArray || return ctype(T) * " " * name
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    return (constant ? "const " : "") * ctype(eltype(T)) * " " * name * join("[$n]" for n in s)
end
