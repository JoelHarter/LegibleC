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

# Carrying, on every shape of loop: the value of one pass read by the next.
function whilecarried(n::Int64)                      # a `while`, the value read at the top of the next pass
    local last
    k = 0; s = 0.0
    while k < n
        k += 1
        if k > 1
            s += last
        end
        last = 2.0 * k
    end
    return s
end
function outercarried(n::Int64)                      # assigned in the inner loop, read by the outer loop's next pass
    local seen
    s = 0.0
    for i in 1:n
        if i > 1
            s += seen
        end
        for j in 1:i
            seen = Float64(i * j)
        end
    end
    return s
end
function skipping(n::Int64)                          # a `continue` ahead of the assignment
    local held
    s = 0.0
    for k in 1:n
        if k == 1
            held = 10.0
            continue
        end
        s += held
        held = Float64(k)
    end
    return s
end
function eitherway(n::Int64)                         # assigned on both branches, then read: never carried, wherever it is declared
    s = 0.0
    for k in 1:n
        if k % 2 == 1
            w = 1.0
        else
            w = 2.0
        end
        s += w * k
    end
    return s
end
function nestedlocal(n::Int64)                       # each loop's own variable, and an array that is a loop's own
    s = 0.0
    for i in 1:n
        row = SVector(Float64(i), 1.0)
        for j in 1:n
            cell = row[1] * j + row[2]
            s += cell
        end
    end
    return s
end
function leaving(n::Int64)                           # a `break` and a `return` from inside the loop
    s = 0.0
    for k in 1:n
        step = 0.5 * k
        step > 3.0 && break
        s += step
        s > 100.0 && return -1.0
    end
    return s
end
const i = 3.0
weighted(v::SVector{3,Float64}) = (s = 0.0; for x in v; s += x * i; end; s)   # the index we invent gives way to the global `i` the loop reads
function pairup(x::Float64)                          # a struct's fields are spelled from the Julia names, not from a local that gave way
    let x = x + 1.0
        y = 2x
        return x, y
    end
end
function nestedlets(x::Float64)                      # a `let` inside a `let`, inside a loop
    s = 0.0
    for k in 1:3
        let t = x * k
            let u = t + 1.0
                s += u
            end
            s += t
        end
    end
    return s
end
oneline(x::Float64) = (let a = 2.0; x = x * a; end; x)   # a `let` that shares its line: no braces, and still right
function letkept(x::Float64)                         # the body assigns a variable of the function's: declared outside the braces
    let scale = 2.0
        y = x * scale
    end
    y = x + 1.0
    return y
end

cases = [Case(nestedlets, 1.5), Case(oneline, 3.0), Case(letkept, 2.0), Case(weighted, SVector(1.0, 2.0, 3.0)), Case(whilecarried, 5), Case(outercarried, 4), Case(skipping, 5), Case(eitherway, 5), Case(nestedlocal, 3), Case(leaving, 10),
         Case(after, 3), Case(param, 1.5), Case(selfinit, 1.0), Case(selfloop, 4), Case(carried, 4), Case(siblings, 3), Case(lets, 1.0),
         Case(area, 2.0), Case(kappa, 5), Case(branchonly, true, 2.0, 3.0), Case(branchonly, false, 2.0, 3.0)]
check("scope", cases)

@testset "scope text" begin
    targets = (after, param, selfinit, selfloop, carried, siblings, lets, area, kappa, branchonly)
    src = csource("scopetext", targets...)
    @test src == csource("scopetext", targets...)                                           # emission is repeatable
    fn(name) = (i = findlast("\n$name(", src); i === nothing && (i = findlast(" $name(", src)); src[i[1]:findnext("\n}", src, i[1])[end]])
    # Where things are declared.
    @test occursin(r"for \(int64_t k = 1; k <= n; k\+\+\) \{\n        // [^\n]*\n        double g_? = \(double\)k;", src)   # a loop's variable, in its loop
    @test occursin(r"double prev;\n(    // [^\n]*\n)*    for \(int64_t k", src)                 # carried around the loop: outside it
    @test occursin(r"if \(c\) \{\n        // [^\n]*\n        double t = a \* b;", src)                          # used in one branch only: in it
    # Which names are kept.
    @test occursin("return s * g;", fn("after")) && !occursin("g_", fn("after"))
    @test occursin("double param(double g)", src)
    @test occursin("double x_local = x + 1.0;", src)
    @test occursin("for (int64_t i_local = 1; i_local <= i; i_local++) {", src)
    @test !occursin("k_", fn("siblings")) && !occursin("w_", fn("siblings"))
    @test occursin("    {\n        double a = 10.0;\n        double b = 2.0;", src) && !occursin("a_", fn("lets")) && !occursin("b_", fn("lets"))
    @test occursin("double area = 3.0 * r * r;", src)
    loops = csource("scopeloops", whilecarried, outercarried, skipping, nestedlocal)
    @test occursin(r"double last;\n(    [^\n]*\n)*?    while \(", loops) && occursin(r"double seen;\n(    [^\n]*\n)*?    for \(int64_t i", loops) && occursin(r"double held;\n(    [^\n]*\n)*?    for \(", loops)
    @test occursin(r"for \(int64_t i = 1; i <= n; i\+\+\) \{\n        // [^\n]*\n        double row\[2\] = \{\(double\)i, 1.0\};", loops) && occursin(r"for \(int64_t j = 1; j <= n; j\+\+\) \{\n            // [^\n]*\n            double cell = ", loops)
    ls = csource("scopelets", nestedlets, oneline, selfinit)
    @test occursin("        {\n            double t = x * k;", ls) && occursin("            {\n                double u = t + 1.0;", ls)   # nested as written
    @test occursin("    {\n        double x_local = x + 1.0;", ls)                                  # the declaration point, inside its block
    @test occursin("double oneline(double x) {", ls) && !occursin(r"oneline\(double x\) \{\n[^}]*\n    \{", ls)
    inv = csource("scopeinvented", weighted, pairup)
    @test occursin("for (int64_t i_ = 0; i_ < 3; i_++) {\n        double x = v[i_];", inv) && occursin("s += x * i;", inv)
    @test occursin("    double x;\n    double y;\n} pairup_t;", inv) && occursin("return (pairup_t){x_local, y};", inv)
    @test occursin("kappa_ = n - 1;", src) && occursin("kappa(kappa_)", src)               # it names the function it would hide
end
end
