# Scope and naming: where a variable is declared, and when a name may be kept. Every case
# runs in C against Julia, which is what catches a wrong capture; the text tests say which
# names are the author's own. See `doc/naming.md`.
module Scope
using Test, StaticArrays
import Main: Case, check, csource

const g = 10.0
# A loop's own `g`, then the *global* `g` read after the loop. Declared above the loop under
# its own name, the leftover local would capture that read: 18 instead of 60.
function after(n::Int64)
    s = 0.0
    for k in 1:n
        g = Float64(k)
        s += g
    end
    return s * g
end
param(g::Float64) = 2.0 * g                          # a parameter hiding a global the function never names
# The declaration point: the new variable's first value reads the outer one of the same name.
function selfinit(x::Float64)
    let x = x + 1.0
        return x * 2.0
    end
end
function selfloop(i::Int64)
    s = 0
    for i in 1:i
        s += i
    end
    return s
end
# `prev` is the function's, though every statement that touches it is inside one branch inside
# the loop: the loop carries its value from one pass to the next, so it is declared outside.
function carried(n::Int64)
    local prev
    s = 0.0
    for k in 1:n
        if n > 0
            if k > 1
                s += prev
            end
            prev = Float64(k)
        end
    end
    return s
end
function siblings(n::Int64)                          # two loops, each with its own `k` and `w`
    s = 0.0
    for k in 1:n
        w = 2.0 * k
        s += w
    end
    for k in 1:n
        w = 3.0 * k
        s += w
    end
    return s
end
function lets(x::Float64)                            # an inner `a` hiding the outer, and sibling `b`s
    a = x + 1.0
    let a = 10.0, b = 2.0
        x = x + a * b
    end
    let b = 5.0
        x = x + b
    end
    return x + a
end
function area(r::Float64)                            # a local named after its own function, which it doesn't call
    area = 3.0 * r * r
    return area
end
function kappa(n::Int64)                             # a local spelled like the function it *does* call: it yields
    κ = n - 1
    return n <= 1 ? 1.0 : n * kappa(κ)
end
function branchonly(c::Bool, a::Float64, b::Float64) # `t` lives in one branch; `y` is used after the `if`
    y = a
    if c
        t = a * b
        y = t + 1.0
    end
    return y
end

cases = [Case(after, 3), Case(param, 1.5), Case(selfinit, 1.0), Case(selfloop, 4), Case(carried, 4), Case(siblings, 3), Case(lets, 1.0),
         Case(area, 2.0), Case(kappa, 5), Case(branchonly, true, 2.0, 3.0), Case(branchonly, false, 2.0, 3.0)]
check("scope", cases)

@testset "scope text" begin
    targets = (after, param, selfinit, selfloop, carried, siblings, lets, area, kappa, branchonly)
    src = csource("scopetext", targets...)
    @test src == csource("scopetext", targets...)                                           # emission is repeatable
    fn(name) = (i = findlast("\n$name(", src); i === nothing && (i = findlast(" $name(", src)); src[i[1]:findnext("\n}", src, i[1])[end]])
    # Where things are declared.
    @test_broken occursin("for (int64_t k = 1; k <= n; k++) {\n        // @scope.jl:14: g = Float64(k)\n        double g = (double)k;", src)   # a loop's variable, in its loop
    @test occursin(r"double prev;\n(    // [^\n]*\n)*    for \(int64_t k", src)                 # carried around the loop: outside it
    @test_broken occursin("if (c) {\n        // @scope.jl:79: t = a * b\n        double t = a * b;", src)                # used in one branch only: in it
    # Which names are kept.
    @test_broken occursin("return s * g;", fn("after")) && !occursin("g_", fn("after"))
    @test_broken occursin("double param(double g)", src)
    @test_broken occursin("double x_local = x + 1.0;", src)
    @test_broken occursin("for (int64_t i_local = 1; i_local <= i; i_local++) {", src)
    @test_broken !occursin("k_", fn("siblings")) && !occursin("w_", fn("siblings"))
    @test_broken occursin("    {\n        double a = 10.0;\n        double b = 2.0;", src) && !occursin("a_", fn("lets")) && !occursin("b_", fn("lets"))
    @test_broken occursin("double area = 3.0 * r * r;", src)
    @test occursin("kappa_ = n - 1;", src) && occursin("kappa(kappa_)", src)               # it names the function it would hide
end
end
