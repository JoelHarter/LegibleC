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
                  :cross => ("×", "cross product"), :max => ("max", "maximum"), :min => ("min", "minimum"),
                  :lt => ("<", "less-than comparison"), :le => ("<=", "at-most comparison"), :gt => (">", "greater-than comparison"),
                  :ge => (">=", "at-least comparison"), :eq => ("==", "equality test"), :ne => ("!=", "inequality test"),
                  :and => ("&", "logical and"), :or => ("|", "logical or"))
const unaryword = Dict(:neg => "negation", :abs => "absolute value", :sqrt => "square root", :cbrt => "cube root",
                   :sin => "sine", :cos => "cosine", :tan => "tangent", :asin => "arcsine", :acos => "arccosine",
                   :atan => "arctangent", :sinh => "hyperbolic sine", :cosh => "hyperbolic cosine",
                   :tanh => "hyperbolic tangent", :exp => "exponential", :exp2 => "base-2 exponential",
                   :expm1 => "exponential minus one", :log => "natural logarithm", :log2 => "base-2 logarithm",
                   :log10 => "base-10 logarithm", :log1p => "logarithm of one plus", :floor => "floor",
                   :ceil => "ceiling", :trunc => "truncation", :round => "rounding",
                   :sum => "sum", :prod => "product", :maximum => "maximum", :minimum => "minimum",
                   :any => "any", :all => "all", :norm => "norm", :inv => "inverse", :pinv => "pseudoinverse",
                   :not => "logical not", :count => "count of true elements", :argmax => "index of the maximum",
                   :argmin => "index of the minimum", :extrema => "minimum and maximum")

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
    # The cross product is only ever of 3-vectors, so saying so says nothing.
    op == :cross && return (typed ? join(unique(string(eltype(T)) for T in types), " × ") * " " : "") * "cross product"
    op == :ifelse && return "element-wise choice between $(d[2]) and $(d[3]) by $(d[1])"
    m = match(r"^pow(m?)(\d+)$", string(op))
    m !== nothing && return "$(d[1]) element-wise " * (m[2] == "2" && isempty(m[1]) ? "square" : m[2] == "3" && isempty(m[1]) ? "cube" : "power $(m[1] == "m" ? "-" : "")$(m[2])")
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
