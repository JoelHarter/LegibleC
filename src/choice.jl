# A value that a test chooses: `a && b`, `a || b` and `c ? x : y` where a value is wanted:
# `ok = a && b`, `return c ? x : y`, the `(b || c)` of `if a && (b || c)`. Julia lowers each
# one into a variable of its own making, stored on both sides of a test and read once, where
# the sides meet:
#
#        goto L if not c
#        hidden = x
#        goto M
#     L: hidden = y
#     M: hidden              <- the value
#
# C has the same three operators, with Julia's order of evaluation and Julia's promise that
# only the chosen side is evaluated. So the value is one expression, written where it is
# used, `bool ok = a && b;`, and not an `if` and an `else` storing into a temp. That is what
# a person writes, and it is also what lets an `if`'s condition be any mix of the three: the
# inner part is a value like any other by the time the `if` is looked at.
#
# Only when each side is an expression and nothing more. A side with work of its own, an
# array helper or a call with an effect, keeps its `if`.
struct Choice
    test::Int           # the `goto L if not c`
    more::Vector{Int}   # further tests that fail to the same place: `a && b ? x : y`
    yes::Int            # the store when the test holds
    jump::Int           # the `goto M` after it
    no::Int             # the store when it doesn't
    join::Int           # the read, where the sides meet: the value
end

const COND = 3          # C's `? :`, which binds less tightly than `||`

# Every place the lowered code has that shape exactly, innermost first. Whether each one
# can be written as an expression is settled with the inlining (`markinlined!`), since it
# is the same question: may this be written inside what uses it?
function findchoices(sc::Scope)
    ci = sc.ci
    code = ci.code
    stores = Dict{Int, Vector{Int}}()
    reads = Dict{Int, Int}()
    for (i, st) in enumerate(code)
        foreach(s -> push!(get!(stores, s, Int[]), i), slotwrites(st))
        foreach(s -> reads[s] = get(reads, s, 0) + 1, slotreads(st))
    end
    found = Choice[]
    for (s, at) in stores
        isempty(string(ci.slotnames[s])) && length(at) == 2 && get(reads, s, 0) == 1 || continue
        T = widen(ci.slottypes[s])
        isconcretetype(T) && T <: Number || continue
        yes, no = at
        jump, join = yes + 1, no + 1
        join <= length(code) && code[join] isa Core.SlotNumber && code[join].id == s || continue
        code[jump] isa Core.GotoNode && code[jump].label == join && jump < no || continue
        tests = [k for k in 1:yes-1 if code[k] isa Core.GotoIfNot && code[k].dest == jump + 1]
        isempty(tests) && continue
        # One way in: nothing else comes to the second side or to where they meet.
        any(k -> isjump(code[k]) && !(k in tests) && k != jump && aim(code[k]) in (jump + 1, join), eachindex(code)) && continue
        push!(found, Choice(tests[1], tests[2:end], yes, jump, no, join))
    end
    return sort(found; by=c -> c.join)
end

# Can this one be an expression, given what was marked for inlining? Its condition and each
# side must be reads, loads and calls that are all written inline, or a choice inside it that
# holds; and nothing in it may have an effect, since it is written later than where Julia
# computed it. Whether the expression then goes inside what uses it, or on a line of its own
# into a temp (`(c ? x : y)^2` writes its operand twice), is the usual question.
function holds(sc::Scope, c::Choice, effectful, held)
    ci = sc.ci
    code = ci.code
    for t in [c.test; c.more]
        cond = code[t].cond
        cond isa Core.SSAValue && cond.id in effectful && return false
    end
    for k in (c.yes, c.no)
        v = code[k].args[2]
        v isa Expr && !(v.head === :call && pure(sc, v)) && return false
    end
    inner = [h for h in held if c.test < h.test && h.join < c.join]
    for k in [c.test+1:c.yes-1; c.jump+1:c.no-1]
        any(h -> h.test <= k <= h.join, inner) && continue
        k in c.more && continue
        st = code[k]
        (st === nothing || st isa GlobalRef || st isa Number) && continue
        st isa Core.SlotNumber && stable(ci, k, st.id) && continue
        st isa Expr && st.head === :call && k in sc.inlined && !(k in effectful) && continue
        return false
    end
    return true
end

# The C for it, as `(text, precedence)`. `a || b` is the one whose first side stores a value
# known to be `true`, `a && b` the one whose second side stores `false`; anything else is
# C's conditional. A person brackets `&&` under `||` and one conditional inside another.
function chosen(sc::Scope, c::Choice)
    code = sc.ci.code
    known(k, v) = code[k].args[2] === v || (t = sc.ci.ssavaluetypes[k]; t isa Core.Const && t.val === v)
    side(k) = (v = code[k].args[2]; v isa Expr ? render(sc, k, v) : expression(sc, v))
    wrap((text, p), prec) = p < prec || (prec == LOR && p == LAND) ? "($text)" : text
    cond = isempty(c.more) ? expression(sc, code[c.test].cond) :
           (join((wrap(expression(sc, code[t].cond), LAND) for t in [c.test; c.more]), " && "), LAND)
    # `a || b` stores `a` itself where it holds, which Julia knows to be `true` only when `a` is a variable.
    (known(c.yes, true) || isempty(c.more) && code[c.yes].args[2] == code[c.test].cond) && return wrap(cond, LOR) * " || " * wrap(side(c.no), LOR), LOR
    known(c.no, false) && return wrap(cond, LAND) * " && " * wrap(side(c.yes), LAND), LAND
    return wrap(cond, COND + 1) * " ? " * wrap(side(c.yes), COND + 1) * " : " * wrap(side(c.no), COND + 1), COND
end
