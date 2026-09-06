# The scalar types the transpiler supports: what Julia calls each, what C calls it, and
# the abbreviation used when a type has to appear in a mangled name. The same table
# is written up in doc/math/scalar.md; keep the two in step.

# Two options change the spelling of scalars: C23's `_Float64` and `_Float32` in place
# of `double` and `float`, and an integer type in place of `bool` (see `transpile`).
const c23floattypes = Ref(false)
const booltype = Ref{Type}(Bool)

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
    (Char,    "char",     "C"),      # ASCII: Julia's Char is a code point, C's char a byte
)

# The C spelling of a Julia type.
function ctype(T::Type)
    T === Bool && booltype[] !== Bool && return ctype(booltype[])
    T === Float64 && c23floattypes[] && return "_Float64"
    T === Float32 && c23floattypes[] && return "_Float32"
    for (julia, c, _) in scalars
        T === julia && return c
    end
    T === Nothing && return "void"
    T <: AbstractString && return "const char *"   # UTF-8 bytes, as Julia's, read-only
    isstruct(T) && return structname(T) * (ismutabletype(T) ? " *" : "")
    istuple(T) && return structname(T)
    T <: Complex && throw(ArgumentError("complex numbers are not yet supported (got $T)"))
    T <: AbstractArray && throw(ArgumentError("arrays are not yet supported (got $T)"))
    throw(ArgumentError("no C type for $T"))
end

# The abbreviation for a scalar type in a mangled name.
function abbrev(T::Type)
    T === Bool && booltype[] !== Bool && return abbrev(booltype[])
    for (julia, _, a) in scalars
        T === julia && return a
    end
    T <: AbstractString && return "S"
    throw(ArgumentError("no abbreviation for $T"))
end

# ---- structs and tuples ------------------------------------------------------------

# A user's struct: a type with fields that isn't a scalar, an array, a tuple, or one of
# Julia's own. An immutable one is a C struct passed and returned by value, which is
# Julia's semantics exactly; a `mutable struct` is a reference in Julia — two variables
# can hold the same one — so in C it's always handled through a pointer.
isstruct(T::Type) = T isa DataType && isstructtype(T) && !(T <: AbstractArray) && !(T <: Tuple) && !(T <: Function) &&
                    !(T <: Type) && !(nameof(Base.moduleroot(T.name.module)) in (:Core, :Base, :LinearAlgebra, :StaticArrays))

# A concrete tuple type — `Tuple{Float64, Int64}`, a multiple return value — which is a
# generated C struct with fields named like helper inputs: `a`, `b`, `c`, …
istuple(T::Type) = T isa DataType && T <: Tuple && isconcretetype(T)

# The C name of a struct or tuple type: the Julia name, with type parameters appended
# the way a function's argument types are (`Point_F32`, `Body_3`); a tuple is
# `Tuple_` and its element types (`Tuple_F64_I64`, `Tuple_3_2x2`).
function structname(T::Type)
    istuple(T) && return "Tuple_" * join((typeword(P) for P in T.parameters), "_")
    base = qualified(string(nameof(T)), T.name.module)
    isempty(T.parameters) && return base
    return base * "_" * join((p isa Type ? typeword(p) : string(p) for p in T.parameters), "_")
end

# One type as it appears inside a struct's name.
typeword(T) = T <: AbstractArray ? dims(T) * (eltype(T) === Float64 ? "" : abbrev(eltype(T))) :
              isstruct(T) || istuple(T) ? structname(T) : abbrev(T)

# The C names of a struct's fields, in order; a tuple's are letters.
fieldcnames(T::Type) = istuple(T) ? inputs(collect(T.parameters)) : identifiers(string.(fieldnames(T)))

# The C name of field `f` (a symbol or a 1-based position) of `T`.
fieldcname(T::Type, f) = fieldcnames(T)[f isa Integer ? f : findfirst(==(f), fieldnames(T))]

# `.` for a struct held by value, `->` for a mutable one held through a pointer.
arrow(T::Type) = isstruct(T) && ismutabletype(T) ? "->" : "."

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


# A transposed array — `v'`, `A'`, `transpose(A)` — as the transpiler sees it. Stored
# in C exactly like the array it came from, `double v[3]` or `double A[2][3]`: C never
# knows a value is transposed, any more than it knows a vector is a row. Only the
# transpiler does, and all that changes is which axis each dimension lines up with
# (`axis`). So a transpose emits nothing, and named with a `T` in front: `T3`, `T2x3`.
# Julia allows it for at most two dimensions; a scalar's transpose is itself and never
# reaches us.
struct Transposed{T, S, N} <: AbstractArray{T, N} end
Base.size(::Type{Transposed{T, S, N}}) where {T, S, N} = S
istransposed(T::Type) = T <: Transposed
isrow(T::Type) = istransposed(T) && ndims(T) == 1

# `T` without its transpose tag: the storage as a plain array.
plain(T::Type) = istransposed(T) ? shaped(eltype(T), shape(T)) : T

# The transpose of `T`: a transposed array is its original, anything else gets the tag.
function transposed(T::Type)
    T <: AbstractArray || return T
    istransposed(T) && return plain(T)
    ndims(T) <= 2 || throw(ArgumentError("transpose of a $(ndims(T))-dimensional array (Julia allows at most two)"))
    return Transposed{eltype(T), shape(T), ndims(T)}
end

# Julia's lazy `Adjoint`/`Transpose` wrappers, as the transpiler sees them: the
# transpose of what they wrap. Everything else passes.
function normalize(T::Type)
    T === Union{} && return T
    T <: LinearAlgebra.Adjoint || T <: LinearAlgebra.Transpose || return T
    P = T.parameters[2]
    shape(P) === nothing && return T
    return transposed(P)
end

# The dimensions of an array type as they appear in a mangled name: `3`, `2x3`, `4x3x4`;
# `T3`, `T2x3` when transposed. Under `staticarray` a regular array is treated exactly like a
# static one, so it needs a size too; until there's a way to supply one, it's an error
# rather than a guess.
function dims(T::Type)
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    return (istransposed(T) ? "T" : "") * join(s, "x")
end

# The axis each of an operand's dimensions lines up with, in storage order. Nothing is
# added: a vector has one dimension, on axis 1; a matrix two, on axes 1 and 2; a scalar
# none. Transposed, the axes come in the other order — a row vector's one dimension is
# on axis 2, a transposed matrix's two on axes 2 and 1. With `extent`, this is all a
# helper needs to index any operand the same way.
axis(T::Type) = T <: AbstractArray ? (istransposed(T) ? collect(2:-1:3-ndims(T)) : collect(1:ndims(T))) : Int[]

# The extent of `T` along axis `d`: its size there, or 1 where it has no dimension —
# which is what makes a missing dimension line up with anything (and a scalar with
# everything) without pretending it exists.
function extent(T::Type, d::Integer)
    p = findfirst(==(d), axis(T))
    return p === nothing ? 1 : shape(T)[p]
end

# The extents of `T` along every axis up to its last, for looping over its elements.
extents(T::Type) = Tuple(extent(T, d) for d in 1:(isempty(axis(T)) ? 0 : maximum(axis(T))))

# A C declaration of `name` with type `T`: `double x`, `const double a[2][2]`. With
# `restrict`, an output array is declared `double out[restrict 2][2]`: a Julia result is
# always a fresh array, so `out` never overlaps an input, and saying so lets the
# compiler keep loads in registers across the stores.
function declare(T::Type, name::AbstractString; constant::Bool=false, restrict::Bool=false)
    T <: AbstractArray || return (c = ctype(T); endswith(c, "*") ? c * name : c * " " * name)
    s = shape(T)
    s === nothing && throw(ArgumentError("arrays without a size in their type are not yet supported (got $T)"))
    first = (restrict ? "[restrict " : "[") * string(s[1]) * "]"
    return (constant ? "const " : "") * ctype(eltype(T)) * " " * name * first * join("[$n]" for n in s[2:end])
end
