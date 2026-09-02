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


# The dimensions of an array type as they appear in a mangled name: `3`, `2x3`, `4x3x4`.
# Under `staticarray` a regular array is treated exactly like a static one, so it needs
# a size too; until there's a way to supply one, it's an error rather than a guess.
function dims(T::Type)
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    return join(s, "x")
end

# A C declaration of `name` with type `T`: `double x`, `const double a[2][2]`.
function declare(T::Type, name::AbstractString; constant::Bool=false)
    T <: AbstractArray || return ctype(T) * " " * name
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    return (constant ? "const " : "") * ctype(eltype(T)) * " " * name * join("[$n]" for n in s)
end
