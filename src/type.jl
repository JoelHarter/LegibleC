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

# The array class letter: S for a static (immutable) array, M for a mutable one, and
# nothing at all for a regular array.
class(T::Type) = shape(T) === nothing ? "" : ismutabletype(T) ? "M" : "S"

# The dimensions of an array type as they appear in a mangled name: `3`, `2x3`, `4x3x4`.
# A regular array's size isn't in its type, so it gets its dimension count: `1D`, `2D`.
function dims(T::Type)
    s = shape(T)
    return s === nothing ? "$(ndims(T))D" : join(s, "x")
end

# A C declaration of `name` with type `T`: `double x`, `const double a[2][2]`.
function declare(T::Type, name::AbstractString; constant::Bool=false)
    T <: AbstractArray || return ctype(T) * " " * name
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    return (constant ? "const " : "") * ctype(eltype(T)) * " " * name * join("[$n]" for n in s)
end
