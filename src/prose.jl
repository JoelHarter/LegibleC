# The one-line comment on each generated helper, written the way a person would say
# it: "2×3 * 3×3 matrix multiplication", "4-vector + 4×3-matrix broadcast addition",
# "2×2-matrix negation", "2×3-matrix element-wise exponential". The transpiler itself
# knows only arrays of any dimension and one kind of pointwise operation; "vector",
# "matrix", "element-wise" and "broadcast" exist here and nowhere else, because they're
# what a reader expects to see.

# The operator and the noun for a binary operation, and the noun for a unary one.
# Anything not listed is called by its Julia name.
const binaryword = Dict(:add => ("+", "addition"), :sub => ("-", "subtraction"), :mul => ("*", "multiplication"),
                  :div => ("/", "division"), :pow => ("^", "exponentiation"), :dot => ("·", "dot product"),
                  :cross => ("×", "cross product"), :max => ("max", "maximum"), :min => ("min", "minimum"))
const unaryword = Dict(:neg => "negation", :abs => "absolute value", :sqrt => "square root", :cbrt => "cube root",
                   :sin => "sine", :cos => "cosine", :tan => "tangent", :asin => "arcsine", :acos => "arccosine",
                   :atan => "arctangent", :sinh => "hyperbolic sine", :cosh => "hyperbolic cosine",
                   :tanh => "hyperbolic tangent", :exp => "exponential", :exp2 => "base-2 exponential",
                   :expm1 => "exponential minus one", :log => "natural logarithm", :log2 => "base-2 logarithm",
                   :log10 => "base-10 logarithm", :log1p => "logarithm of one plus", :floor => "floor",
                   :ceil => "ceiling", :trunc => "truncation", :round => "rounding",
                   :sum => "sum", :prod => "product", :maximum => "maximum", :minimum => "minimum",
                   :any => "any", :all => "all", :norm => "norm", :inv => "inverse", :pinv => "pseudoinverse")

# One operand as a person names it: "scalar", "3-vector", "2×3-matrix", "4×3×2-array",
# "transposed 3-vector"; the element type in front when the helper's name carries
# types (the same rule as the name: only when not every input is Float64).
sizeword(T::Type) = join(shape(T), "×")
noun(T::Type; plural::Bool=false) = ndims(T) == 1 ? (plural ? "vectors" : "vector") :
                                    ndims(T) == 2 ? (plural ? "matrices" : "matrix") : (plural ? "arrays" : "array")
function describe(T::Type; typed::Bool=false, plural::Bool=false)
    T <: AbstractArray || return (typed ? "$T " : "") * (plural ? "scalars" : "scalar")
    return (istransposed(T) ? "transposed " : "") * (typed ? "$(eltype(T)) " : "") * sizeword(T) * "-" * noun(T; plural)
end

# The comment for the helper for `op` on `types`, producing `R`.
function prose(op::Symbol, types, R=nothing; pointwise::Bool=false)
    typed = !all(T -> (T <: AbstractArray ? eltype(T) : T) === Float64, types)
    d = [describe(T; typed) for T in types]
    op == :copy && return axis(types[1]) == axis(R) ? "$(d[1]) copy" : "$(describe(plain(types[1]); typed)) transpose"
    length(types) == 1 && return "$(d[1]) $(pointwise ? "element-wise " : "")$(get(unaryword, op, string(op)))"
    a, b = types
    sym, verb = get(binaryword, op, (string(op), string(op)))
    kind = !pointwise ? "" :
           any(T -> !(T <: AbstractArray), types) || extents(a) != extents(b) ? "broadcast " : "element-wise "
    d[1] == d[2] && return "$(d[1]) $kind$verb"
    # Two plain operands of one kind share the noun: "2×3 * 3×3 matrix multiplication".
    shared = !typed && all(T -> T <: AbstractArray && !istransposed(T), types) && noun(a) == noun(b)
    left, right = shared ? (sizeword(a), sizeword(b)) : (d[1], d[2])
    return left * (all(isletter, sym) ? " and " : " $sym ") * right * " " * (shared ? noun(a) * " " : "") * kind * verb
end

# The comment for a block construction: "vertical concatenation of two 3-vectors",
# "2×2 block matrix of four 2×2-matrices", "horizontal concatenation of a 3-vector and
# a scalar". Runs of the same kind of block are counted.
function blockprose(kind::Symbol, rows, types)
    several(n) = n == 1 ? "a" : get(Dict(2 => "two", 3 => "three", 4 => "four", 5 => "five", 6 => "six",
                                         7 => "seven", 8 => "eight", 9 => "nine"), n, string(n))
    items = String[]
    i = 1
    while i <= length(types)
        j = i
        while j < length(types) && describe(types[j + 1]) == describe(types[i]); j += 1; end
        push!(items, several(j - i + 1) * " " * describe(types[i]; plural=j > i))
        i = j + 1
    end
    list = length(items) == 1 ? items[1] : join(items[1:end-1], ", ") * " and " * items[end]
    kind == :vcat && return "vertical concatenation of $list"
    kind == :hcat && return "horizontal concatenation of $list"
    grid = allequal(rows) ? "$(length(rows))×$(rows[1])" : "$(length(rows))-row"
    return "$grid block matrix of $list"
end
