# Julia in, C out — C that reads as if a careful engineer wrote it by hand. `transpile`
# is the whole interface; everything else is the machinery behind it, in the module so
# that a user's own `shape` or `index` is a different name from the transpiler's.
module LegibleC

using StaticArrays
using LinearAlgebra
using Printf

export transpile

include("c.jl")          # the emitter, which includes the rest
include("transpile.jl")  # the API: targets to instances, names, the file

end # module LegibleC
