# The control flow of a function, recovered whole before any C is written.
#
# Julia lowers `if`, `&&`, `while`, `for`, `break` and `continue` into jumps. `flow.jl`
# used to work out what each jump meant at the moment it met it while writing C, and what
# it had decided so far lived in the emitter's own state. Every wrong loop the transpiler
# has produced came from there: a guess made with half the picture, and nothing to check
# it against. So the structure is recovered here first, by one walk that writes nothing,
# and then checked (`validate`): every jump of the function is accounted for by exactly
# one construct, and no construct is entered anywhere but at its top. What can't be
# accounted for is refused by line. `flow.jl` then writes C from what was decided here,
# and decides nothing.

# An `if`: its tests merged into one condition, its branches, and where it ends. `chain`
# is the `if` that its else-branch consists of, to be written `else if`, or 0.
struct Branch
    i::Int
    conds::Vector{Tuple{Any, Bool}}
    op::String
    thenlo::Int
    thenhi::Int
    elselo::Int                     # 0 when there is no else
    elsehi::Int
    after::Int
    chain::Int
end

# A `while`, as it will be written: its tests merged, where its body starts, and whether
# the condition can stand in the `while (…)` or has statements of its own, which then go
# inside the braces ahead of an `if (!…) break;`.
struct Round
    W::While
    conds::Vector{Tuple{Any, Bool}}
    op::String
    bodylo::Int
    inline::Bool
end

struct Tree
    ifs::Dict{Int, Branch}
    rounds::Dict{Int, Round}             # by the statement the `while` starts at
    exits::Dict{Int, String}             # a jump that is a statement of its own: `break`, `continue`
    claimed::Dict{Int, Symbol}           # every jump of the function -> the construct that accounts for it
    regions::Vector{NTuple{2, Int}}      # every range of statements that is entered only at its top
    machinery::Set{Int}                  # statements that are a `for`'s own working: control flow, not nothing
end
Tree() = Tree(Dict{Int, Branch}(), Dict{Int, Round}(), Dict{Int, String}(), Dict{Int, Symbol}(), NTuple{2, Int}[], Set{Int}())

isjump(st) = st isa Core.GotoNode || st isa Core.GotoIfNot
aim(st) = st isa Core.GotoNode ? st.label : st.dest

function claim!(tree::Tree, sc::Scope, i, role::Symbol)
    haskey(tree.claimed, i) && tree.claimed[i] !== role &&
        error("internal: the jump at statement $i is both $(tree.claimed[i]) and $role (line $(sc.stmtline[i])); please report it")
    tree.claimed[i] = role
end

"""
    recover(sc) -> Tree

The structure of the whole function, and the check that it is one. Run once `analyze!`
has found the loops and what is rendered inline, and `findlets` the source's `let`s.
"""
function recover(sc::Scope)
    tree = Tree()
    code = sc.ci.code
    for F in values(sc.fors)
        for i in [F.start:F.bodylo-1; F.next:F.exit-1; collect(F.machinery)]
            push!(tree.machinery, i)
            isjump(code[i]) && claim!(tree, sc, i, :loop)
        end
    end
    recover!(tree, sc, 1, length(code), NTuple{2, Int}[])
    validate(tree, sc)
    return tree
end

# Statements `lo:hi`, as `block!` will walk them: the same order, the same tests, so that
# what is decided here is exactly what is written there.
function recover!(tree::Tree, sc::Scope, lo::Int, hi::Int, loops; except::Int=0)
    code = sc.ci.code
    i = lo
    while i <= hi
        if !isempty(get(sc.lets, i, ())) && sc.lets[i][1][2] <= hi
            l = popfirst!(sc.lets[i])            # so that the walk inside doesn't open it again
            push!(tree.regions, (l[1], l[2]))
            recover!(tree, sc, l[1], l[2], loops)
            pushfirst!(sc.lets[i], l)
            i = l[2] + 1
        elseif haskey(sc.fors, i)
            F = sc.fors[i]
            push!(tree.regions, (F.bodylo, F.bodyhi))
            recover!(tree, sc, F.bodylo, F.bodyhi, [loops; (F.exit, F.next)])
            i = F.exit
        elseif haskey(sc.whiles, i) && i != except
            i = round!(tree, sc, sc.whiles[i], loops)
        elseif i in sc.skipped
            i += 1
        elseif code[i] isa Core.GotoIfNot
            i = branch!(tree, sc, i, hi, loops)
        elseif code[i] isa Core.GotoNode
            tree.exits[i] = leave(sc, i, code[i].label, loops)
            claim!(tree, sc, i, Symbol(tree.exits[i]))
            i += 1
        else
            i += 1
        end
    end
end

# A jump that is a statement of its own: the `break` or the `continue` of the loop it is
# in. C's `break` leaves one loop; Julia's leaves the whole nest of a `for i in …, j in …`.
function leave(sc::Scope, i, label, loops)
    if !isempty(loops)
        brk, cont = loops[end]
        label == brk && return "break"
        label == cont && return "continue"
        any(label == b for (b, _) in loops[1:end-1]) &&
            throw(ArgumentError("a `break` inside `for i in …, j in …` leaves every loop of the nest in Julia, and C's `break` leaves one (line $(sc.stmtline[i])); write the loops one inside the other and leave with a flag, or put the nest in a function of its own and `return`"))
    end
    throw(ArgumentError("control flow not recognised: a jump at line $(sc.stmtline[i]) that is no `if`, loop, `break` or `continue` (statement $i, to statement $label)"))
end

function round!(tree::Tree, sc::Scope, W::While, loops)
    code = sc.ci.code
    # `while a && b`, `while a || b`: the same merged tests an `if` opens with.
    conds, op, target, bodylo = tests(sc, W.test)
    target == W.exit || throw(ArgumentError("a `while` whose condition doesn't lead out of it (line $(sc.stmtline[W.header]))"))
    compound = length(conds) > 1
    # The condition can go in the `while (…)` only if everything in the header folds into it.
    inline = all(i -> i in sc.inlined || i in sc.skipped || code[i] isa GlobalRef || code[i] isa Core.SlotNumber ||
                      code[i] isa Core.SSAValue || isjump(code[i]) || code[i] isa Core.NewvarNode, W.header:bodylo-1)
    compound && !inline && throw(ArgumentError("a `while a && b` whose condition needs work of its own, array work say, before it can be tested (line $(sc.stmtline[W.header])); test the first part in the `while` and the rest in the body, with `break`"))
    tree.rounds[W.header] = Round(W, conds, op, bodylo, inline)
    for i in W.test:bodylo-1; isjump(code[i]) && claim!(tree, sc, i, :test); end
    claim!(tree, sc, W.backedge, :loop)
    inside = [loops; (W.exit, W.backedge)]
    if inline
        push!(tree.regions, (bodylo, W.backedge - 1))
        recover!(tree, sc, bodylo, W.backedge - 1, inside)
    else
        # The condition's statements go inside the braces, and the loop begins with them.
        push!(tree.regions, (W.header, W.backedge - 1))
        recover!(tree, sc, W.header, W.test - 1, inside; except=W.header)
        recover!(tree, sc, W.test + 1, W.backedge - 1, inside)
    end
    return W.backedge + 1
end

function branch!(tree::Tree, sc::Scope, i::Int, hi::Int, loops)
    code = sc.ci.code
    conds, op, target, j = tests(sc, i)
    for k in i:j-1; isjump(code[k]) && claim!(tree, sc, k, :test); end
    thenlo = j
    # The then-block runs to the else target. If it ends by jumping past that, there's
    # an else-block up to the jump's destination.
    thenhi = target - 1
    elselo = elsehi = 0
    after = target
    last = lastlive(sc, thenlo, thenhi)
    if last !== nothing && code[last] isa Core.GotoNode
        label = code[last].label
        if label > target && label <= hi + 1 && !any(label in l for l in loops)
            elselo, elsehi = target, label - 1
            after = label
            push!(sc.skipped, last)
            claim!(tree, sc, last, :else)
        elseif label == target
            # `c && (x = 1)` in the middle of a body ends its branch with a jump to the very
            # place the branch was going. Exactly that place: "the same next live statement"
            # is not the same thing, since it sees straight through a loop's own machinery.
            push!(sc.skipped, last)
            claim!(tree, sc, last, :join)
        elseif !isempty(loops) && label == loops[end][2] && label != loops[end][1] && nextlive(sc, label) == nextlive(sc, target)
            # A jump to the loop's next pass from the end of its body — how `x && (n += 1)`
            # lowers as the last statement of a loop — is where the body was going anyway.
            # Of the innermost loop only: an inner loop that ends an outer loop's body has
            # its exit at the outer one's next-pass point, and a jump there is its `break`.
            push!(sc.skipped, last)
            claim!(tree, sc, last, :join)
        end
    end
    chain = 0
    if elselo > 0
        first = nextlive(sc, elselo)
        # An else-block that is exactly one `if` reaching the same end is an `else if`.
        if first <= elsehi && code[first] isa Core.GotoIfNot && !haskey(sc.whiles, first) && !haskey(sc.fors, first) &&
           ifextent(sc, first, elsehi, loops) == after
            chain = first
        end
    end
    tree.ifs[i] = Branch(i, conds, op, thenlo, thenhi, elselo, elsehi, after, chain)
    push!(tree.regions, (thenlo, thenhi))
    recover!(tree, sc, thenlo, thenhi, loops)
    if chain != 0
        branch!(tree, sc, chain, elsehi, loops)
    elseif elselo > 0
        push!(tree.regions, (elselo, elsehi))
        recover!(tree, sc, elselo, elsehi, loops)
    end
    return after
end

# Is the structure one? Every jump of the function belongs to exactly one construct — a
# loop's working, an `if`'s or a `while`'s tests, the jump over an else, a jump to where
# its branch was going anyway, a `break`, a `continue` — and nothing jumps into the middle
# of a branch or a loop from outside it. A jump nobody claimed is code the walk never
# understood: a loop it walked past, a test it took for something else. That used to come
# out as C that compiled and computed something else.
function validate(tree::Tree, sc::Scope)
    code = sc.ci.code
    for (i, st) in enumerate(code)
        isjump(st) && sc.ci.ssavaluetypes[i] !== Union{} || continue
        haskey(tree.claimed, i) ||
            throw(ArgumentError("control flow not recognised at line $(sc.stmtline[i]): a jump that belongs to no `if`, loop, `break` or `continue` the transpiler found (statement $i, to statement $(aim(st)))"))
        t = aim(st)
        for (lo, hi) in tree.regions
            lo < t <= hi && !(lo <= i <= hi) &&
                throw(ArgumentError("control flow not recognised at line $(sc.stmtline[i]): a jump into the middle of a branch or a loop (statement $i, to statement $t, inside $lo:$hi)"))
        end
    end
end
