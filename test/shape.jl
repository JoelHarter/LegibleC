# The shapes a condition can take: every way of joining up to three parts with `&&`, `||`, `!`
# and `? :`, in every place a condition can stand, with each part either something C can write
# inside a condition or something that needs lines of its own, on every assignment of true and
# false. Julia answers, the C must match. It runs through the grid's machinery (`grid.jl`).
#
# It exists for the same reason the grid does. The shapes that went wrong were never the ones
# a test had: `a || b || c`, `(a || b) && c` as a value, `@assert a || b`, a part with array
# work and an `else` to reach. Here they are all tried, and the ones nobody has thought of yet.
module Shape
using Test, LegibleC
import Main: Grid

# A part is true when its parameter is 1. A light part is a comparison. A heavy one is the same
# truth worked out through `mod` of a product, which the C writes as a temp on a line of its own.
light(k) = "p$k > 0"
heavy(k) = "mod(p$k * 3, 2) == 1"

# The ways of joining one, two and three parts.
const joins = ["L1",
               "L1 && L2", "L1 || L2", "!(L1) && L2", "L1 || !(L2)",
               "L1 && L2 && L3", "L1 || L2 || L3", "L1 && (L2 || L3)", "(L1 || L2) && L3", "L1 || (L2 && L3)", "(L1 && L2) || L3",
               "L1 && !(L2 || L3)", "(L1 ? L2 : L3)", "L1 && (L2 ? L3 : !(L3))"]

# The places a condition can stand. `q` is one more parameter, for the places that need a way out.
const places = ["ifelse" => "if COND; r = 1; else; r = 2; end; return r",
                "ifonly" => "r = 0; if COND; r = 1; end; return r + 10",
                "elseif" => "if q > 5; r = 1; elseif COND; r = 2; else; r = 3; end; return r",
                "value" => "ok = COND; return ok ? 1 : 2",
                "choose" => "return (COND ? 10 : 20) + q",
                "whilefirst" => "s = 0; while (COND) && s < 3; s += 1; end; return s",
                "whilelast" => "s = 0; while s < 3 && (COND); s += 1; end; return s",
                "skip" => "s = 0; for k in 1:3; (COND) || continue; s += k; end; return s",
                "leave" => "s = 0; for k in 1:3; s += k; (COND) && break; end; return s",
                "leavenest" => "s = 0; for i in 1:2, j in 1:2; s += 1; (COND) && break; end; return s",
                "early" => "(COND) && return 7; return 8 + q"]

function items()
    out = Grid.Item[]
    for (j, join) in enumerate(joins)
        n = count(k -> occursin("L$k", join), 1:3)
        for weights in Iterators.product(fill((false, true), n)...), (place, body) in places
            cond = join
            for k in 1:n
                cond = replace(cond, "L$k" => weights[k] ? heavy(k) : light(k))
            end
            name = "$(place)_$(j)_" * prod(w ? "h" : "l" for w in weights)
            params = [["p$k::Int64" for k in 1:n]; "q::Int64"]
            f = Core.eval(Shape, Meta.parse("function $name($(Base.join(params, ", "))); $(replace(body, "COND" => cond)); end"))
            it = Grid.item(name, f, ntuple(_ -> Int64, n + 1), Any[[fill([0, 1], n)...]; [[0]]])
            it === nothing || push!(out, it)
        end
    end
    return out
end

@testset "shape" begin
    r = Grid.report("shape", items(), Shape)
    @test isempty(r.wrong)
    @test isempty(r.broken)
    @test isempty(r.faults)
    @test length(r.refused) <= 0.02 * r.functions        # a shape that is refused is a shape someone will write
end
end
