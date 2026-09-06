# Structured control flow, recovered from the gotos Julia lowers it into.
#
# Julia's lowering is regular enough to pattern-match: an `if` is a `GotoIfNot` whose
# then-block may end in a jump over the else-block; `&&` and `||` are chains of jumps
# to the same targets; a `while` is a header, a `GotoIfNot` to the exit, and a jump
# back to the header; a `for` over a range is the `iterate`/`getfield` idiom around a
# body; `break` and `continue` are jumps to a loop's exit or its next-iteration point.
# `block!` walks a range of statements and emits each shape as the C construct it
# came from. Anything it can't place is an error rather than a `goto`.
#
# Conditions and loop bounds are rendered as expressions, not temps — `while (temp1)`
# would be wrong — so the statements feeding them are marked `inlined` up front and
# rendered on demand by `expression`, with C precedence handled by `operand`.

# A `for` over an integer range.
struct For
    start::Int      # first statement belonging to the loop (the range construction)
    var::Int        # slot of the loop variable
    lo              # IR values: first, last, and step (step `nothing` for unit)
    hi
    step
    bodylo::Int
    bodyhi::Int
    next::Int       # the `iterate(range, state)` statement: where `continue` goes
    exit::Int       # first statement after the loop
    machinery::NTuple{3, Int}   # inside the body: the state read and the two getfields
    array          # `for x in v`: the IR value iterated, and `var` is its element; else nothing
end

# A `while`.
struct While
    header::Int     # first statement of the condition
    test::Int       # the GotoIfNot
    backedge::Int   # the jump back to the header
    exit::Int
end

# Recognise every `for` loop. The idiom, with `r` the range and `s` the hidden state
# slot, is:  s = iterate(r); %a = s; %b = %a === nothing; %c = not_int(%b);
# goto exit if not %c; %d = s; var = getfield(%d, 1); %e = getfield(%d, 2); body;
# s = iterate(r, %e); … same test …; goto (the `%d = s` line).
function findfors(ci)
    code = ci.code
    fors = Dict{Int, For}()
    for (k, st) in enumerate(code)
        st isa Expr && st.head === :(=) && iscall(st.args[2], Base.iterate) && length(st.args[2].args) == 2 || continue
        r = st.args[2].args[2]
        r isa Core.SSAValue || continue
        range = rangebounds(ci, r.id)
        array = nothing
        if range === nothing
            # `for x in v`: over the elements, in storage order.
            T = widen(valuetype_ir(ci, r))
            isarray(T) || continue
            ndims(T) == 1 || throw(ArgumentError("`for x in A` over a $(describe(T)) is not supported; iterate its indices"))
            range, array = (1, Expr(:length, r), nothing), r
        end
        s = st.args[1].id
        k + 7 <= length(code) || continue
        test = code[k+4]
        test isa Core.GotoIfNot || continue
        # The body starts at k+5. Somewhere at its top — after any loop-variable copies
        # an inner loop needs — the state is read and split into variable and state.
        d = findfirst(j -> code[j] isa Core.SlotNumber && code[j].id == s, (k+5):length(code))
        d === nothing && continue
        d += k + 4
        hdr = code[d+1]
        hdr isa Expr && hdr.head === :(=) && iscall(hdr.args[2], Core.getfield) && hdr.args[2].args[2] == Core.SSAValue(d) || continue
        iscall(code[d+2], Core.getfield) && code[d+2].args[2] == Core.SSAValue(d) || continue
        var = hdr.args[1].id
        # The second iterate call, on this state slot, closes the body.
        next = findfirst(j -> (x = code[j]; x isa Expr && x.head === :(=) && x.args[1].id == s &&
                               iscall(x.args[2], Base.iterate) && length(x.args[2].args) == 3), (d+3):length(code))
        next === nothing && continue
        next += d + 2
        code[next+4] isa Core.GotoIfNot && code[next+5] isa Core.GotoNode && code[next+5].label == k + 5 || continue
        start = r.id - (code[r.id-1] isa GlobalRef ? 1 : 0)
        fors[start] = For(start, var, range..., k + 5, next - 1, next, next + 6, (d, d + 1, d + 2), array)
    end
    return fors
end

# (lo, hi, step) for the range built by statement `i`, or nothing if it isn't one we
# know: `a:b`, `a:s:b`, `eachindex(x)`, `Base.OneTo(n)`, `axes(x, d)`.
function rangebounds(ci, i)
    st = ci.code[i]
    st isa Expr && st.head === :call || return nothing
    f = try callee(ci, st.args[1]) catch; return nothing end
    args = st.args[2:end]
    f === Colon() && length(args) == 2 && return (args[1], args[2], nothing)
    f === Colon() && length(args) == 3 && return (args[1], args[3], args[2])
    f === Base.OneTo && length(args) == 1 && return (1, args[1], nothing)
    T = length(args) >= 1 ? widen(valuetype_ir(ci, args[1])) : nothing
    if f === Base.eachindex && length(args) == 1 && T !== nothing && T <: AbstractArray
        return (1, Expr(:length, args[1]), nothing)
    end
    if f === Base.axes && length(args) == 2 && T !== nothing && T <: AbstractArray && args[2] isa Integer
        return (1, Expr(:size, args[1], args[2]), nothing)
    end
    return nothing
end

# Recognise every `while`: a jump backwards that isn't part of a `for`.
function findwhiles(ci, fors)
    code = ci.code
    whiles = Dict{Int, While}()
    forbacks = Set(F.exit - 1 for F in values(fors))
    for (j, st) in enumerate(code)
        st isa Core.GotoNode && st.label <= j && !(j in forbacks) || continue
        t = st.label
        test = findfirst(i -> code[i] isa Core.GotoIfNot, t:j)
        test === nothing && throw(ArgumentError("a loop without a condition at statement $t"))
        test += t - 1
        whiles[t] = While(t, test, j, code[test].dest)
    end
    return whiles
end

iscall(x, f) = x isa Expr && x.head === :call && (x.args[1] === f || (x.args[1] isa GlobalRef && getfield(x.args[1].mod, x.args[1].name) === f))

# The inferred type of an IR value without a Scope (used before one exists).
valuetype_ir(ci, x) = x isa Core.SSAValue ? ci.ssavaluetypes[x.id] : x isa Core.SlotNumber ? ci.slottypes[x.id] : typeof(x)

# Emit statements `lo` through `hi` as structured C.
function block!(lines, sc::Scope, lo::Int, hi::Int)
    code = sc.ci.code
    i = lo
    while i <= hi
        # A new Julia line: a blank line first, then — at the top level — this is where
        # a hoisted declaration goes, ahead of the line's source comment.
        if sc.stmtline[i] > sc.cursor
            separate!(lines, sc)
            sc.depth == 0 && (sc.blockstart = length(lines) + 1)
        end
        if haskey(sc.fors, i)
            i = forloop!(lines, sc, sc.fors[i])
        elseif haskey(sc.whiles, i)
            i = whileloop!(lines, sc, sc.whiles[i])
        elseif i in sc.skipped
            i += 1
        elseif code[i] isa Core.GotoIfNot
            i = ifelse!(lines, sc, i, hi)
        elseif code[i] isa Core.GotoNode
            jump!(lines, sc, code[i].label)
            i += 1
        else
            i in sc.skipped || annotate!(lines, sc, sc.stmtline[i])
            i in sc.skipped || statement!(lines, sc, i, code[i])
            i += 1
        end
    end
    return i
end

# A jump that isn't part of an `if`: `break` or `continue` of the innermost loop it
# belongs to.
function jump!(lines, sc::Scope, label)
    for (brk, cont) in reverse(sc.loops)
        label == brk && return emit!(lines, sc, "break;")
        label == cont && return emit!(lines, sc, "continue;")
    end
    throw(ArgumentError("unstructured jump to statement $label"))
end

# Emit the body of a construct one level deeper, with `result` available afresh
# inside the block.
function nested!(lines, sc::Scope, lo, hi)
    saved = sc.result
    sc.depth += 1
    block!(lines, sc, lo, hi)
    sc.depth -= 1
    sc.result = saved
end

function forloop!(lines, sc::Scope, F::For)
    annotate!(lines, sc, sc.stmtline[F.start])
    var = sc.names[F.var]
    T = ctype(widen(sc.ci.slottypes[F.var]))
    lo = bound(sc, F.lo)
    hi = bound(sc, F.hi)
    # A bound that is a call — `1:ncodeunits(s)` — is computed once, before the loop,
    # as Julia's range is; in the header it would run every iteration.
    if F.hi isa Core.SSAValue && F.hi.id in sc.inlined && occursin("(", hi)
        t = temp!(sc, nothing, contribution(sc, F.hi))
        emit!(lines, sc, "$T $t = $hi;")
        hi = t
    end
    if F.array !== nothing
        # `for x in v`: a 0-based index the Julia never named, then the element.
        k = indices(1; taken=sc.names)[1]
        push!(sc.names, k)
        emit!(lines, sc, "for (int64_t $k = 0; $k < $hi; $k++) {")
        push!(sc.loops, (F.exit, F.next))
        sc.depth += 1
        emit!(lines, sc, "$T $var = $(value(sc, F.array))[$k];")
        sc.depth -= 1
        nested!(lines, sc, F.bodylo, F.bodyhi)
        pop!(sc.loops)
        emit!(lines, sc, "}")
        return F.exit
    end
    if F.step === nothing
        emit!(lines, sc, "for ($T $var = $lo; $var <= $hi; $var++) {")
    else
        F.step isa Integer || throw(ArgumentError("a range step must be a literal (statement $(F.start))"))
        cmp = F.step > 0 ? "<=" : ">="
        emit!(lines, sc, "for ($T $var = $lo; $var $cmp $hi; $var += $(F.step)) {")
    end
    push!(sc.loops, (F.exit, F.next))
    nested!(lines, sc, F.bodylo, F.bodyhi)
    pop!(sc.loops)
    emit!(lines, sc, "}")
    return F.exit
end

# A range bound as a C expression.
function bound(sc::Scope, x)
    x isa Expr && x.head === :length && return string(prod(shape(valuetype(sc, x.args[1]))))
    x isa Expr && x.head === :size && return string(shape(valuetype(sc, x.args[1]))[x.args[2]])
    return expression(sc, x)[1]
end

function whileloop!(lines, sc::Scope, W::While)
    code = sc.ci.code
    annotate!(lines, sc, sc.stmtline[W.header])
    # The condition can go in the `while (…)` only if everything in the header folds
    # into it; otherwise test it at the top of the body.
    inline = all(i -> i in sc.inlined || i in sc.skipped || code[i] isa GlobalRef ||
                      code[i] isa Core.SlotNumber || code[i] isa Core.SSAValue, W.header:W.test-1)
    if inline
        cond = code[W.test].cond === true ? "true" : condition(sc, [(code[W.test].cond, false)], "&&")
        emit!(lines, sc, "while ($cond) {")
        push!(sc.loops, (W.exit, W.backedge))
        nested!(lines, sc, W.test + 1, W.backedge - 1)
    else
        emit!(lines, sc, "while (true) {")
        push!(sc.loops, (W.exit, W.backedge))
        sc.depth += 1
        # The header's statements, emitted as a block — with this loop taken out of the
        # table meanwhile, or `block!` would start the loop again at its header.
        delete!(sc.whiles, W.header)
        block!(lines, sc, W.header, W.test - 1)
        sc.whiles[W.header] = W
        emit!(lines, sc, "if (!($(condition(sc, [(code[W.test].cond, false)], "&&")))) {")
        emit!(lines, sc, "    break;")
        emit!(lines, sc, "}")
        sc.depth -= 1
        nested!(lines, sc, W.test + 1, W.backedge - 1)
    end
    pop!(sc.loops)
    emit!(lines, sc, "}")
    return W.backedge + 1
end

# An `if`, starting at the GotoIfNot at `i`, within a block that ends at `hi`.
# Returns the index of the first statement after the whole construct.
function ifelse!(lines, sc::Scope, i::Int, hi::Int; chained::Bool=false)
    code = sc.ci.code
    annotate!(lines, sc, sc.stmtline[i])
    conds = Tuple{Any, Bool}[]           # (IR value, negated) — the pieces of the condition
    op = "&&"
    target = code[i].dest                # where a failed test goes: the else (or the end)
    push!(conds, (code[i].cond, false))
    j = i + 1
    # Merge `&&`: further tests that fail to the same place. Merge `||`: a test that
    # fails into another test, with a jump straight to the body in between.
    while true
        j = nextlive(sc, j)
        if code[j] isa Core.GotoIfNot && code[j].dest == target && op == "&&"
            push!(conds, (code[j].cond, false)); j += 1
        elseif code[j] isa Core.GotoNode && code[j].label > j && nextlive(sc, j + 1) == nextlive(sc, target) &&
               (t2 = nextlive(sc, target); code[t2] isa Core.GotoIfNot && nextlive(sc, t2 + 1) == nextlive(sc, code[j].label)) &&
               (op == "||" || length(conds) == 1)
            op = "||"
            push!(conds, (code[t2].cond, false))
            j = t2 + 1
            target = code[t2].dest
        else
            break
        end
    end
    thenlo = j
    # The then-block runs to the else target. If it ends by jumping past that, there's
    # an else-block up to the jump's destination.
    thenhi = target - 1
    elselo = elsehi = 0
    after = target
    last = lastlive(sc, thenlo, thenhi)
    if last !== nothing && code[last] isa Core.GotoNode && code[last].label > target && code[last].label <= hi + 1 &&
       !any(code[last].label in l for l in sc.loops)
        elselo, elsehi = target, code[last].label - 1
        after = code[last].label
        push!(sc.skipped, last)
    elseif last !== nothing && code[last] isa Core.GotoNode && any(code[last].label == cont for (_, cont) in sc.loops) &&
           nextlive(sc, code[last].label) == nextlive(sc, target)
        # A jump to the loop's next iteration from the end of the body — how `x && (n += 1)`
        # lowers as the last statement of a loop — is where the body was going anyway.
        push!(sc.skipped, last)
    end
    cond = condition(sc, conds, op)
    emit!(lines, sc, (chained ? "} else if (" : "if (") * cond * ") {")
    nested!(lines, sc, thenlo, thenhi)
    if elselo > 0
        first = nextlive(sc, elselo)
        # An else-block that is exactly one `if` reaching the same end is an `else if`.
        if first <= elsehi && code[first] isa Core.GotoIfNot && !haskey(sc.whiles, first) && !haskey(sc.fors, first) &&
           ifextent(sc, first, elsehi) == after
            ifelse!(lines, sc, first, elsehi; chained=true)
            return after
        end
        emit!(lines, sc, "} else {")
        nested!(lines, sc, elselo, elsehi)
    end
    emit!(lines, sc, "}")
    return after
end

# Where the `if` starting at `i` ends, computed without emitting anything.
function ifextent(sc::Scope, i, hi)
    code = sc.ci.code
    target = code[i].dest
    j = i + 1
    while true
        j = nextlive(sc, j)
        if code[j] isa Core.GotoIfNot && code[j].dest == target
            j += 1
        elseif code[j] isa Core.GotoNode && code[j].label > j && nextlive(sc, j + 1) == nextlive(sc, target) &&
               (t2 = nextlive(sc, target); code[t2] isa Core.GotoIfNot && nextlive(sc, t2 + 1) == nextlive(sc, code[j].label))
            j = t2 + 1
            target = code[t2].dest
        else
            break
        end
    end
    last = lastlive(sc, j, target - 1)
    if last !== nothing && code[last] isa Core.GotoNode && code[last].label > target && code[last].label <= hi + 1 &&
       !any(code[last].label in l for l in sc.loops)
        return code[last].label
    end
    return target
end

# The first statement at or after `i` that will actually be emitted (not inlined into
# a condition, not dead, not a constant load).
function nextlive(sc::Scope, i)
    code = sc.ci.code
    while i <= length(code) && (i in sc.inlined || i in sc.skipped || code[i] isa GlobalRef || code[i] isa Core.NewvarNode ||
                                widen(sc.ci.ssavaluetypes[i]) === Union{} && !(code[i] isa Core.ReturnNode))
        i += 1
    end
    return i
end

function lastlive(sc::Scope, lo, hi)
    for i in hi:-1:lo
        nextlive(sc, i) == i && return i
    end
    return nothing
end

# A condition from its pieces, joined by `&&` or `||`.
function condition(sc::Scope, conds, op)
    prec = op == "&&" ? 5 : 4
    parts = String[]
    for (x, negated) in conds
        text, p = expression(sc, x)
        negated && (text = "!" * (p < 14 ? "($text)" : text); p = 14)
        push!(parts, p < prec || (prec == LOR && p == LAND) ? "($text)" : text)
    end
    return join(parts, " $op ")
end

# Mark, ahead of emission, the scalar calls that are rendered inside the expression
# that consumes them rather than as temps: `sqrt(sq(a) + sq(b))`, not three temps. The
# rule mirrors the author — a value they never named, used once, is written where it
# is used, `return` included — with the exceptions that keep the C's meaning Julia's:
#   - the consumer writes its operand twice (`x^2` is `x * x`; `mod`, integer `max`
#     and `min`, `==` on a struct): a call evaluated twice costs twice;
#   - something with an effect stands between the value and its consumer — a print, a
#     store, a `setindex!`, a user function that does any of those: C leaves the order
#     of operands and arguments unspecified, so pure work may move past pure work only;
#   - the value itself carries an effect (its call, or a call inlined into it): then
#     nothing that computes may stand between, not even a read, since a read of what
#     the effect writes would see a different value.
# Conditions and loop bounds follow the same rule; they were its first consumers.
function markinlined!(sc::Scope)
    ci = sc.ci
    code = ci.code
    count = Dict{Int, Int}()
    for st in code
        countuses!(count, st)
    end
    effectful = Set{Int}()
    for (i, st) in enumerate(code)
        st isa Expr && st.head === :call && get(count, i, 0) == 1 || continue
        widen(ci.ssavaluetypes[i]) <: Union{Number, Char} && !compiletime(ci.ssavaluetypes[i]) || continue
        u = findfirst(s -> uses(s, i), code)
        use = code[u]
        use isa Expr && use.head === :(=) && (use = use.args[2])
        use isa Expr && use.head === :call && duplicates(sc, u, use, i) && continue
        effect = !pure(sc, st) || any(a -> a isa Core.SSAValue && a.id in effectful, st.args[2:end])
        all(k -> effect ? silent(sc, k) : inert(sc, k), i+1:u-1) || continue
        push!(sc.inlined, i)
        effect && push!(effectful, i)
    end
end

# Does the call at `u`, consuming SSA value `i`, write that operand more than once?
function duplicates(sc::Scope, u, use::Expr, i)
    f = callee_or_nothing(sc.ci, use.args[1])
    T = widen(sc.ci.ssavaluetypes[u])
    if f === Base.literal_pow
        p = sc.ci.ssavaluetypes[use.args[4].id]
        return use.args[3] == Core.SSAValue(i) && p isa Core.Const && p.val isa Val && typeof(p.val).parameters[1] in (2, 3)
    end
    f === Base.mod && T <: Integer && return true
    f in (Base.max, Base.min) && T <: Integer && return true
    f === Base.:(==) && (isstruct(valuetype(sc, use.args[2])) || istuple(valuetype(sc, use.args[2]))) && return true
    return false
end

# Can a pure computation move past statement `k` without changing what it computes?
# Yes for anything that is no statement in C, a read, or a pure call.
inert(sc::Scope, k) = silent(sc, k) || (st = sc.ci.code[k]; st isa Expr && st.head === :call && pure(sc, st))

# Can a computation with an effect move past statement `k`? Only if `k` computes
# nothing at all: a variable read (a Julia local, which no callee can change), a
# constant, or a statement with no C.
function silent(sc::Scope, k)
    st = sc.ci.code[k]
    k in sc.skipped || st === nothing || st isa GlobalRef || st isa Core.NewvarNode || st isa Core.SlotNumber ||
        st isa Core.SSAValue || st isa Number || st isa Expr && st.head in (:meta, :code_coverage_effect)
end

# Calls with an effect the C must keep in order: writes and prints. Anything foreign
# (a `ccall`) counts as both.
const writing = (Base.setindex!, Base.setproperty!, Core.setfield!, Base.push!, Base.pop!, Base.fill!, Base.copyto!, Base.materialize!)
const printing = (Base.print, Base.println, Printf.format)
const known = (:Core, :Base, :LinearAlgebra, :StaticArrays, :Printf)

# Is this call free of effects? Julia's own functions are, except the ones above; a
# user function is examined (`effects!`).
function pure(sc::Scope, st::Expr)
    f = callee_or_nothing(sc.ci, st.args[1])
    f === nothing && return false
    (f in writing || f in printing) && return false
    f isa Type && return true
    nameof(Base.moduleroot(parentmodule(f))) in known && return true
    r = userinstance!(sc, f, st.args[2:end])
    return r === nothing || isempty(effects!(sc.prog, r[1]))
end

# What a user function does besides compute: `:write` (a store into an array or
# struct), `:print`, `:foreign` (a `ccall`), `:unknown` (a call that couldn't be
# resolved) — its own, and those of every user function it calls. Read off its typed
# IR, once per instance. A recursive function contributes nothing to itself.
function effects!(prog::Program, mi::Core.MethodInstance)
    haskey(prog.effects, mi) && return prog.effects[mi]
    prog.effects[mi] = Set{Symbol}()
    ci = only(Base.code_typed_by_type(mi.specTypes; optimize=false))[1]
    rawtype(t) = t isa Core.Const ? typeof(t.val) : t isa Core.PartialStruct ? t.typ : t
    argtype(a) = a isa GlobalRef ? typeof(getfield(a.mod, a.name)) : rawtype(valuetype_ir(ci, a))
    found = Set{Symbol}()
    for st in ci.code
        ex = st isa Expr && st.head === :(=) ? st.args[2] : st
        ex isa Expr || continue
        ex.head === :foreigncall && (push!(found, :foreign); continue)
        ex.head === :call || continue
        f = callee_or_nothing(ci, ex.args[1])
        f === nothing && (push!(found, :unknown); continue)
        f in writing && push!(found, :write)
        f in printing && push!(found, :print)
        f isa Type && continue
        nameof(Base.moduleroot(parentmodule(f))) in known && continue
        types = [argtype(a) for a in ex.args[2:end]]
        m = all(T -> T isa Type && isconcretetype(T), types) ? Base.method_instance(f, Tuple(types)) : nothing
        m === nothing ? push!(found, :unknown) : union!(found, effects!(prog, m))
    end
    prog.effects[mi] = found
    return found
end

countuses!(uses, x) = x isa Core.SSAValue ? (uses[x.id] = get(uses, x.id, 0) + 1) :
                      x isa Expr ? foreach(a -> countuses!(uses, a), x.args) :
                      x isa Core.ReturnNode ? (isdefined(x, :val) && countuses!(uses, x.val)) :
                      x isa Core.GotoIfNot ? countuses!(uses, x.cond) : nothing

# The C for an IR value as an expression: `(text, precedence)`. An SSA value that was
# marked inline is rendered from its call; anything else is its name or literal.
function expression(sc::Scope, x)
    if x isa Core.SSAValue && x.id in sc.inlined
        return render(sc, x.id, sc.ci.code[x.id])
    end
    text = value(sc, x)
    return text, startswith(text, "-") ? 14 : 15
end

# An operand of an operator with precedence `prec`, parenthesised if it binds less
# tightly. `right` operands of equal precedence are parenthesised too (left
# associativity). Under a shift or a bitwise operator any other operator is
# parenthesised, and `&&` under `||`: C's precedence there is what nobody remembers,
# a person writes `(a & b) | (c << 2)`, and clang warns without the parentheses.
function operand(sc::Scope, x, prec; right::Bool=false)
    text, p = expression(sc, x)
    return p < prec || (right && p == prec) || (prec in (SHIFT, BAND, BXOR, BOR) && p < UNARY && p != prec) || (prec == LOR && p == LAND) ? "($text)" : text
end
