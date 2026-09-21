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

include("choice.jl")    # a value that a test chooses, written as one expression
include("tree.jl")      # what the jumps between them mean: decided there, written here

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
        # The exit is what follows the jump back: where the last of the condition's tests
        # goes when it fails. Not the first test's own target, which for `while a || b` is
        # the second test.
        whiles[t] = While(t, test, j, j + 1)
    end
    return whiles
end

iscall(x, f) = x isa Expr && x.head === :call && (x.args[1] === f || (x.args[1] isa GlobalRef && getfield(x.args[1].mod, x.args[1].name) === f))

# The inferred type of an IR value without a Scope (used before one exists).
valuetype_ir(ci, x) = x isa Core.SSAValue ? ci.ssavaluetypes[x.id] : x isa Core.SlotNumber ? ci.slottypes[x.id] : typeof(x)

# Emit statements `lo` through `hi` as structured C. What each jump is was decided before
# anything was written (`tree.jl`); nothing is decided here.
function block!(lines, sc::Scope, lo::Int, hi::Int; except::Int=0)
    code = sc.ci.code
    tree = sc.tree
    i = lo
    while i <= hi
        # A new Julia line: a blank line first, then — at the top level — this is where
        # a hoisted declaration goes, ahead of the line's source comment.
        sc.stmtline[i] > sc.cursor && separate!(lines, sc)
        # Where this statement or construct begins, at this depth: a declaration hoisted
        # out of it goes here, ahead of its source comment.
        length(sc.starts) > sc.depth || resize!(sc.starts, sc.depth + 1)
        sc.starts[sc.depth+1] = length(lines) + 1
        if !isempty(get(sc.lets, i, ())) && sc.lets[i][1][2] <= hi
            # A `let` of the source: a bare block, which is what a Julia scope is in C. What
            # is declared in it, and under what name, is decided as for any block.
            lo_, hi_, line = popfirst!(sc.lets[i])
            annotate!(lines, sc, line)
            emit!(lines, sc, "{")
            nested!(lines, sc, lo_, hi_)
            emit!(lines, sc, "}")
            pushfirst!(sc.lets[i], (lo_, hi_, line))
            i = hi_ + 1
        elseif haskey(sc.fors, i)
            i = forloop!(lines, sc, sc.fors[i])
        elseif haskey(sc.whiles, i) && i != except
            i = whileloop!(lines, sc, tree.rounds[i])
        elseif i in sc.skipped
            i += 1
        elseif haskey(tree.ifs, i)
            i = ifelse!(lines, sc, tree.ifs[i])
        elseif haskey(tree.exits, i)
            sc.current = i
            emit!(lines, sc, tree.exits[i] * ";")
            i += 1
        elseif isjump(code[i])
            error("internal: the jump at statement $i (line $(sc.stmtline[i])) was accounted for as $(get(tree.claimed, i, :nothing)) and met while writing; please report it")
        else
            i in sc.skipped || annotate!(lines, sc, sc.stmtline[i])
            i in sc.skipped || statement!(lines, sc, i, code[i])
            i += 1
        end
    end
    return i
end

# Emit the body of a construct one level deeper, with `result` available afresh
# inside the block.
function nested!(lines, sc::Scope, lo, hi; loop::Bool=false, braces::Bool=true)
    saved = sc.result
    braces && enter!(sc, lo, hi, loop)
    sc.depth += 1
    block!(lines, sc, lo, hi)
    sc.depth -= 1
    braces && pop!(sc.path)
    sc.result = saved
end

# Open the C block holding statements `lo:hi`, one level deeper than the current depth.
function enter!(sc::Scope, lo, hi, loop::Bool)
    push!(sc.blocks, Block(lo, hi, sc.path[end], sc.depth + 1, loop))
    push!(sc.path, length(sc.blocks))
    # A loop's header is written outside its braces but belongs to it: the loop variable
    # is in scope there, so `for i in 1:i` must not come out as `i <= i`.
    isempty(sc.pending) || (sc.headline[length(sc.blocks)] = sc.pending; sc.pending = "")
end

# The block each variable is declared in, from a walk that found the blocks: the innermost
# one holding every statement that reads or assigns the variable, moved out of any loop
# that carries its value from one pass to the next, where it would be made anew instead.
# Narrower than that and a use falls outside it; wider, and it could capture a later use
# of something else of the same name. Julia's own scope isn't asked for, and couldn't be:
# the compiler marks where a variable is made anew (`NewvarNode`) only when it might be
# read unassigned, and puts the mark for one assigned in a branch at the function's top.
function homes(sc::Scope)
    ci, blocks = sc.ci, sc.blocks
    blockof(i) = (b = 1; for (k, B) in enumerate(blocks); B.lo <= i <= B.hi && B.depth >= blocks[b].depth && (b = k); end; b)
    chain(b) = (c = Int[]; while b != 0; push!(c, b); b = blocks[b].parent; end; c)
    common(a, b) = first(x for x in chain(a) if x in chain(b))
    refs = Dict{Int, Vector{Int}}()
    for (i, st) in enumerate(ci.code), s in union(slotreads(st), slotwrites(st))
        push!(get!(refs, s, Int[]), i)
    end
    home = Dict{Int, Int}()
    for (s, at) in refs
        s > ci.nargs && !(s in sc.hidden) || continue
        b = reduce(common, blockof.(at))
        while true
            l = b
            while l != 0 && !blocks[l].loop; l = blocks[l].parent; end
            l != 0 && carried(sc, s, l) || break
            b = blocks[l].parent
        end
        home[s] = b
    end
    # A loop's own variable is declared in its header: it lives in the loop's body.
    for F in values(sc.fors)
        b = findfirst(B -> B.loop && B.lo == F.bodylo && B.hi == F.bodyhi, blocks)
        b === nothing || (home[F.var] = b)
    end
    return home
end

"""
    names!(sc, first)

The C name of every variable of the function, from the first walk `first`: the author's
own name wherever that is safe, and a changed one only where C would otherwise get it
wrong. Two things sharing a name are harmful when they are declared in the same block;
when one is declared inside the other's block *and that inner block mentions the outer
one*, so the mention would land on the wrong thing; or when the name is C's own. Siblings
and cousins may share a name, and so may a variable and an outer thing its block never
mentions, which is how a shadow the Julia wrote is kept as written.

When two do collide, the one that keeps the name is the one declared further out; then a
parameter before a local before a working copy; then the one whose Julia name is already
its C name; then the first. The other takes `_local` when it is the local version of the
very name it yields to (`let x = x + 1`, the working copy of a parameter), `_` otherwise.
"""
function names!(sc::Scope, first::Scope)
    ci, blocks = sc.ci, first.blocks
    chain(b) = (c = Int[]; while b != 0; push!(c, b); b = blocks[b].parent; end; c)
    # The words each block mentions, comments and strings aside, its own header included;
    # then those of everything inside it.
    words(s) = Set(m.match for m in eachmatch(r"[A-Za-z_]\w*", replace(s, r"/\*.*?\*/"s => "", r"//[^\n]*" => "", r"\"(\\.|[^\"\\])*\"" => "")))
    own = [Set{SubString{String}}() for _ in blocks]
    for (b, line) in first.emitted; union!(own[b], words(line)); end
    for (b, line) in first.headline; union!(own[b], words(line)); end
    inside = deepcopy(own)
    for b in length(blocks):-1:2; union!(inside[blocks[b].parent], inside[b]); end
    # The file-scope names this function mentions: all it has to keep clear of, since the
    # rest of the program is out of its sight. Known by now, its own walk having met them.
    sc.outer = Set(String(w) for w in inside[1] if w in filescope(sc.prog))
    # One variable per name of the first walk: slots Julia made for one variable share it.
    groups = Dict{String, Vector{Int}}()
    for s in 2:length(ci.slotnames)
        isempty(string(ci.slotnames[s])) || push!(get!(groups, first.names[s], Int[]), s)
    end
    vars = map(collect(groups)) do (marked, slots)
        julia = string(ci.slotnames[minimum(slots)])
        param = any(<=(ci.nargs), slots)
        copy = any(s -> haskey(first.rebound, s), slots)
        top = param || copy || any(s -> haskey(first.outplaced, s), slots)
        held = [first.home[s] for s in slots if haskey(first.home, s)]
        home = top || isempty(held) ? 1 : reduce((a, b) -> Base.first(x for x in chain(a) if x in chain(b)), held)
        (; marked, slots, julia, ident=identifier(julia), home, rank=param ? 0 : copy ? 2 : 1)
    end
    sort!(vars; by=v -> (blocks[v.home].depth, v.rank, v.ident == v.julia ? 0 : 1, minimum(v.slots)))
    named = Tuple{String, Any}[]
    globalnamed(n) = (k = findfirst(g -> g.cname == n, sc.prog.globals); k === nothing ? "" : string(sc.prog.globals[k].name))
    # What `v` would collide with under the name `n`: a Julia name (perhaps none), or nothing.
    function clash(v, n)
        n in reserved && return ""
        haskey(irrationals, n) && return ""              # a macro of ours rewrites the name wherever it stands, mentioned in this block or not
        n in sc.outer && n in inside[v.home] && return globalnamed(n)
        for (m, u) in named
            m == n || continue
            u.home == v.home && return u.julia
            u.home in chain(v.home) && u.marked in inside[v.home] && return u.julia
            v.home in chain(u.home) && v.marked in inside[u.home] && return u.julia
        end
        return nothing
    end
    for v in vars
        n = v.ident
        c = clash(v, n)
        c === nothing || (n *= c == v.julia ? "_local" : "_")
        while clash(v, n) !== nothing; n *= "_"; end
        push!(named, (n, v))
        for s in v.slots; sc.names[s] = n; end
    end
end

# The `let` blocks the source wrote, as the statements each holds. Julia's typed statements
# carry no trace of a `let`, so the source is the only thing that knows one was written;
# and it only *proposes* braces, by line. What goes inside them is exact by construction,
# since statements are emitted in order between the braces, and every declaration is then
# placed by `homes` against the blocks as they really are: a wrong guess here can cost a
# badly placed brace and nothing else. A `let` that shares a line with other code, or is a
# value (`y = let … end`), or is all on one line, proposes nothing, and comes out flat.
function findlets(sc::Scope)
    lets = Dict{Int, Vector{NTuple{3, Int}}}()
    src = sc.src
    src === nothing && return lets
    text = join(src.lines, "\n")
    start(l) = sum(ncodeunits(src.lines[k]) + 1 for k in 1:l-1; init=0) + 1
    found = Int[]
    function walk(ex, line)
        ex isa Expr || return
        for a in ex.args
            a isa LineNumberNode && (line = a.line + src.first - 1; continue)    # a parse begun mid-text counts lines from there
            a isa Expr && a.head === :let && line != 0 && push!(found, line)
            walk(a, line)
        end
    end
    fn = try Meta.parse(text, start(src.first))[1] catch; return lets end
    walk(fn, src.first)
    for l in unique(found)
        src.first < l <= src.last && occursin(r"^\s*let\b", src.lines[l]) || continue
        at = start(l) + ncodeunits(match(r"^\s*", src.lines[l]).match)
        ex, next = try Meta.parse(text, at) catch; continue end
        ex isa Expr && ex.head === :let || continue
        stop = something(findprev(!isspace, text, prevind(text, next)), at)
        last = count(==('\n'), SubString(text, 1, stop)) + 1
        last > l && occursin(r"^\s*end\s*(#.*)?$", src.lines[last]) || continue
        inside = [i for i in eachindex(sc.stmtline) if l <= sc.stmtline[i] <= last]
        isempty(inside) && continue
        lo, hi = extrema(inside)
        all(i -> l <= sc.stmtline[i] <= last, lo:hi) || continue
        whole(sc, lo, hi) || continue
        push!(get!(lets, lo, NTuple{3, Int}[]), (lo, hi, l))
    end
    foreach(v -> sort!(v; by=t -> t[1] - t[2]), values(lets))     # the widest first: it is the outermost
    return lets
end

# Is `lo:hi` a whole piece of the function's control flow, so that braces may go round it?
# Line numbers proposed it, and lines can mislead (a macro's, a file edited since it was
# loaded); a range that cut through an `if` or a loop would confuse the recovery of the
# control flow itself, not just misplace a brace. So: nothing outside jumps into its
# middle, and nothing inside jumps out, except to its own end, or — a `break` or a
# `continue` — to the exit or next-pass point of a loop that holds all of it.
function whole(sc::Scope, lo, hi)
    code = sc.ci.code
    target(st) = st isa Core.GotoNode ? st.label : st isa Core.GotoIfNot ? st.dest : nothing
    around = Int[]
    for F in values(sc.fors); F.bodylo <= lo && hi <= F.bodyhi && push!(around, F.exit, F.next); end
    for W in values(sc.whiles); W.header <= lo && hi < W.backedge && push!(around, W.exit, W.backedge, W.header); end
    for (i, st) in enumerate(code)
        t = target(st)
        t === nothing && continue
        if lo <= i <= hi
            lo <= t <= hi + 1 || t in around || return false
        else
            lo < t <= hi && return false
        end
    end
    return true
end

# The variables a statement reads, and the ones it assigns.
slotreads(x) = x isa Core.SlotNumber ? [x.id] :
               x isa Expr && x.head === :(=) ? slotreads(x.args[2]) :
               x isa Expr ? reduce(vcat, (slotreads(a) for a in x.args); init=Int[]) :
               x isa Core.ReturnNode && isdefined(x, :val) ? slotreads(x.val) :
               x isa Core.GotoIfNot ? slotreads(x.cond) : Int[]
slotwrites(x) = x isa Expr && x.head === :(=) && x.args[1] isa Core.SlotNumber ? [x.args[1].id] : Int[]

# Does the loop whose body is block `l` carry variable `s` from one pass to the next: can a
# pass read it before that pass has assigned it? Read off the statements in order; an
# assignment inside a block nested in the body isn't counted on afterwards, since the
# block may not have run, which errs toward saying yes.
function carried(sc::Scope, s, l)
    code, blocks = sc.ci.code, sc.blocks
    function scan(b, assigned)
        inner = Dict(blocks[k].lo => k for k in eachindex(blocks) if blocks[k].parent == b)
        i = blocks[b].lo
        while i <= blocks[b].hi
            if haskey(inner, i) && blocks[inner[i]].hi >= i
                scan(inner[i], assigned) && return true
                i = blocks[inner[i]].hi + 1
                continue
            end
            !assigned && s in slotreads(code[i]) && return true
            code[i] isa Expr && code[i].head === :(=) && s in slotwrites(code[i]) && (assigned = true)
            i += 1
        end
        return false
    end
    return scan(l, false)
end

# Can the body of the loop change what its end bound reads? A variable the bound reads that
# the body assigns; or memory the bound reads (an element, a field) when the body may write
# memory at all — a store, or a call to a function of the author's.
function boundchanges(sc::Scope, F::For)
    code = sc.ci.code
    slots, memory = Set{Int}(), Ref(false)
    function read!(x)
        x isa Core.SlotNumber && return push!(slots, x.id)
        if x isa Core.SSAValue
            st = code[x.id]
            st isa Expr && st.head === :call && !(sc.ci.ssavaluetypes[x.id] isa Core.Const) &&
                callee_or_nothing(sc.ci, st.args[1]) in (Base.getindex, Base.getproperty, Core.getfield, Base.getfield) && (memory[] = true)
            return read!(st)
        end
        x isa Expr && foreach(read!, x.args)
    end
    read!(F.hi)
    for st in code[F.bodylo:F.bodyhi]
        st isa Expr || continue
        st.head === :(=) && st.args[1] isa Core.SlotNumber && st.args[1].id in slots && return true
        memory[] || continue
        c = consumer(st)
        c isa Expr && c.head === :call || continue
        f = callee_or_nothing(sc.ci, c.args[1])
        f in (Base.setindex!, Base.setproperty!, Core.setfield!, Base.setfield!, Base.fill!, Base.materialize!, Base.copyto!) && return true
        f isa Function && !(nameof(Base.moduleroot(parentmodule(f))) in known) && return true
    end
    return false
end

function forloop!(lines, sc::Scope, F::For)
    annotate!(lines, sc, sc.stmtline[F.start])
    var = sc.names[F.var]
    T = ctype(widen(sc.ci.slottypes[F.var]))
    lo = bound(sc, F.lo)
    hi = bound(sc, F.hi)
    # Julia builds the range once, so its end is read once; C's header reads it every pass.
    # A bound that is a call — `1:ncodeunits(s)` — or that the body can change — `for k in
    # 1:n; n -= 1` is `n` passes in Julia — is taken into a temp before the loop.
    if F.hi isa Core.SSAValue && F.hi.id in sc.inlined && occursin("(", hi) || F.array === nothing && boundchanges(sc, F)
        t = temp!(sc, nothing, contribution(sc, F.hi))
        emit!(lines, sc, "$T $t = $hi;")
        hi = t
    end
    code = sc.ci.code
    within(s) = any(i -> !(i in F.machinery) && assigns(code[i], s), F.bodylo:F.bodyhi)
    if F.array !== nothing
        # `for x in v`: a 0-based index the Julia never named, then the element.
        array = value(sc, F.array)
        s = slotof(sc, F.array)
        if s !== nothing && within(s)
            # The body gives `v` a new value. Julia goes on through the array it started
            # with; the C, reading `v[i]` each pass, would read the new one. So a copy.
            A = valuetype(sc, F.array)
            array = temp!(sc, nothing, contribution(sc, F.array))
            emit!(lines, sc, declare(A, array) * ";")
            copy!(lines, sc, value(sc, F.array), A, array, A)
        end
        k = indices(1; taken=union(sc.names, sc.outer))[1]
        push!(sc.names, k)
        emit!(lines, sc, "for (int64_t $k = 0; $k < $hi; $k++) {")
        sc.depth += 1
        emit!(lines, sc, "$T $var = $array[$k];")
        sc.depth -= 1
        sc.pending = "$var = $array[$k]"
        nested!(lines, sc, F.bodylo, F.bodyhi; loop=true)
        emit!(lines, sc, "}")
        return F.exit
    end
    # The body assigns the loop's own variable. In Julia that lasts for the pass, and the
    # next pass gets the next value of the range all the same; a C `for` would go on from
    # the new value. So the counting is done by an index of ours, as for `for x in v`, and
    # the variable is the body's, set from it at the top of each pass.
    count = var
    if within(F.var)
        count = indices(1; taken=union(sc.names, sc.outer))[1]
        push!(sc.names, count)
    end
    if F.step === nothing
        emit!(lines, sc, "for ($T $count = $lo; $count <= $hi; $count++) {")
    else
        F.step isa Integer || throw(ArgumentError("a range step must be a literal (statement $(F.start))"))
        cmp = F.step > 0 ? "<=" : ">="
        emit!(lines, sc, "for ($T $count = $lo; $count $cmp $hi; $count += $(F.step)) {")
    end
    sc.pending = "$var = $lo; $var <= $hi"
    if count != var
        sc.depth += 1
        emit!(lines, sc, "$T $var = $count;")
        sc.depth -= 1
    end
    nested!(lines, sc, F.bodylo, F.bodyhi; loop=true)
    emit!(lines, sc, "}")
    return F.exit
end

# A range bound as a C expression.
function bound(sc::Scope, x)
    x isa Expr && x.head === :length && return string(prod(shape(valuetype(sc, x.args[1]))))
    x isa Expr && x.head === :size && return string(shape(valuetype(sc, x.args[1]))[x.args[2]])
    return expression(sc, x)[1]
end

function whileloop!(lines, sc::Scope, R::Round)
    code = sc.ci.code
    W = R.W
    annotate!(lines, sc, sc.stmtline[W.header])
    if R.inline
        cond = code[W.test].cond !== true ? condition(sc, R.conds, R.op) :
               length(R.conds) > 1 && R.op == "&&" ? condition(sc, R.conds[2:end], R.op) : "true"     # `while true`
        emit!(lines, sc, "while ($cond) {")
        nested!(lines, sc, R.bodylo, W.backedge - 1; loop=true)
    else
        # The condition has statements of its own, which can't stand in a `while (…)`: they
        # go inside the braces, and the test after them.
        emit!(lines, sc, "while (true) {")
        enter!(sc, W.header, W.backedge - 1, true)
        sc.depth += 1
        block!(lines, sc, W.header, W.test - 1; except=W.header)
        emit!(lines, sc, "if (!($(condition(sc, [(code[W.test].cond, false)], "&&")))) {")
        emit!(lines, sc, "    break;")
        emit!(lines, sc, "}")
        sc.depth -= 1
        # The same pair of braces as the condition's statements, so the same block: as two,
        # a variable of each could both keep one name, and C saw it declared twice.
        nested!(lines, sc, W.test + 1, W.backedge - 1; braces=false)
        pop!(sc.path)
    end
    emit!(lines, sc, "}")
    return W.backedge + 1
end

# The tests an `if` or a `while` opens with, merged into one condition. `a && b` is
# further tests that fail to the same place; `a || b` is a test that fails into another
# test, with a jump straight to the body in between. Returns the pieces, as (IR value,
# negated), the operator, where a failed test goes, and the first statement after them.
function tests(sc::Scope, i::Int)
    code = sc.ci.code
    conds = Tuple{Any, Bool}[(code[i].cond, false)]
    op = "&&"
    target = code[i].dest
    j = i + 1
    # A variable that is assigned more than once is read through a statement of its own, which
    # writes nothing. Between two tests it belongs to the second: looked past, to find it.
    # A loop's own test is never one of them: `if a; while true; …` opens with two tests that
    # fail to the same place, and the second is the loop's.
    function nexttest(k)
        k = nextlive(sc, k)
        while k <= length(code) && code[k] isa Core.SlotNumber && stable(sc.ci, k, code[k].id) && !haskey(sc.whiles, k)
            k = nextlive(sc, k + 1)
        end
        return k <= length(code) && code[k] isa Core.GotoIfNot && !haskey(sc.whiles, k) ? k : 0
    end
    while true
        j = nextlive(sc, j)
        if op == "&&" && (k = nexttest(j); k != 0 && code[k].dest == target)
            push!(conds, (code[k].cond, false)); j = k + 1
        elseif code[j] isa Core.GotoNode && code[j].label > j && nextlive(sc, j + 1) == nextlive(sc, target) &&
               (t2 = nexttest(target); t2 != 0 && nextlive(sc, t2 + 1) == nextlive(sc, code[j].label)) &&
               (op == "||" || length(conds) == 1)
            op = "||"
            push!(conds, (code[t2].cond, false))
            j = t2 + 1
            target = code[t2].dest
        else
            break
        end
    end
    return conds, op, target, j
end

# An `if`, starting at the GotoIfNot at `i`, within a block that ends at `hi`.
# Returns the index of the first statement after the whole construct.
function ifelse!(lines, sc::Scope, B::Branch; chained::Bool=false)
    annotate!(lines, sc, sc.stmtline[B.i])
    emit!(lines, sc, (chained ? "} else if (" : "if (") * condition(sc, B.conds, B.op) * ") {")
    header = length(lines)
    nested!(lines, sc, B.thenlo, B.thenhi)
    if length(lines) == header && B.elselo > 0 && B.chain == 0
        # Nothing to do where it holds, and something where it doesn't, which is how
        # `@assert c` arrives: a person tests for the opposite and has no empty branch.
        lines[header] = replace(lines[header], r"if \(.*\) \{$" => "if (" * opposite(sc, B.conds, B.op) * ") {")
        nested!(lines, sc, B.elselo, B.elsehi)
        emit!(lines, sc, "}")
        return B.after
    end
    if B.chain != 0
        ifelse!(lines, sc, sc.tree.ifs[B.chain]; chained=true)      # an else that is exactly one `if`: `else if`
        return B.after
    elseif B.elselo > 0
        emit!(lines, sc, "} else {")
        nested!(lines, sc, B.elselo, B.elsehi)
    end
    emit!(lines, sc, "}")
    return B.after
end

# Where the `if` starting at `i` ends, computed without emitting anything.
function ifextent(sc::Scope, i, hi, loops)
    code = sc.ci.code
    target = code[i].dest
    j = i + 1
    while true
        j = nextlive(sc, j)
        if code[j] isa Core.GotoIfNot && code[j].dest == target && !haskey(sc.whiles, j)
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
       !any(code[last].label in l for l in loops)
        return code[last].label
    end
    return target
end

# A `throw` or an `error`: typed as never returning, as dead code is, and not dead at all.
throws(sc::Scope, i) = (st = sc.ci.code[i]; st isa Expr && st.head === :call && widen(sc.ci.ssavaluetypes[i]) === Union{} &&
                                           callee_or_nothing(sc.ci, st.args[1]) in (Core.throw, Base.error))

# The first statement at or after `i` that will actually be emitted (not inlined into
# a condition, not dead, not a constant load).
function nextlive(sc::Scope, i)
    code = sc.ci.code
    # A loop begins at statements that are themselves consumed (its range, its first
    # `iterate`), and is live all the same: walked past, a `for` that opens an `if`'s
    # branch was never seen, and its body ran once.
    while i <= length(code) && !haskey(sc.fors, i) && !haskey(sc.whiles, i) &&
          (i in sc.inlined || i in sc.skipped || code[i] isa GlobalRef || code[i] isa Core.NewvarNode ||
           widen(sc.ci.ssavaluetypes[i]) === Union{} && !(code[i] isa Core.ReturnNode) && !throws(sc, i))
        i += 1
    end
    return i
end

function lastlive(sc::Scope, lo, hi)
    for i in hi:-1:lo
        # A loop is one thing. Walking back through its working into its body found the
        # body's last statement, and a `break` there was taken for the branch's own last
        # jump and dropped: `if m > 1; for …; m > 100 && break; end; end` never left early.
        any(F -> lo <= F.start && F.start <= i < F.exit, values(sc.fors)) && return nothing
        any(W -> lo <= W.header && W.header <= i <= W.backedge, values(sc.whiles)) && return nothing
        nextlive(sc, i) == i && return i
    end
    return nothing
end

# The condition that holds exactly when this one doesn't. One comparison is turned round
# where that is exact: `==` and `!=` always, the ordered ones on integers only, since for
# floats `!(a < b)` holds for a NaN and `a >= b` doesn't. Anything else is `!(…)`.
function opposite(sc::Scope, conds, op)
    flipped = Dict(Base.:(==) => :!=, Base.:!= => :(==), Base.:< => :>=, Base.:<= => :>, Base.:> => :<=, Base.:>= => :<)
    x = conds[1][1]
    if length(conds) == 1 && !conds[1][2] && x isa Core.SSAValue && x.id in sc.inlined && !haskey(sc.choices, x.id)
        st = sc.ci.code[x.id]
        f = callee_or_nothing(sc.ci, st.args[1])
        if haskey(flipped, f) && length(st.args) == 3 && all(a -> valuetype(sc, a) <: Number, st.args[2:3]) &&
           (f in (Base.:(==), Base.:!=) || all(a -> valuetype(sc, a) <: Integer, st.args[2:3]))
            return first(render(sc, x.id, Expr(:call, GlobalRef(Base, flipped[f]), st.args[2:3]...)))
        end
    end
    text = condition(sc, conds, op)
    return "!" * (length(conds) == 1 && occursin(r"^[\w.>\[\]-]+$", text) ? text : "($text)")
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
    # A choice is written inside what uses it too, and whether it can be depends on what is
    # marked, which depends on which choices there are: a value may move past a choice that is
    # an expression, and not past one that is an `if`. So every one is supposed to hold, and
    # those that turn out not to are dropped and the marking done again, until none is.
    candidates = findchoices(sc)
    while true
        empty!(sc.inlined)
        empty!(sc.choices)
        consumed = setdiff(Set(k for c in candidates for k in c.test:c.join-1), sc.skipped)     # all of it is inside the expression
        union!(sc.skipped, consumed)
        foreach(c -> sc.choices[c.join] = c, candidates)
        effectful = mark!(sc)
        held = Choice[]
        for c in candidates
            holds(sc, c, effectful, held) && push!(held, c)
        end
        length(held) == length(candidates) && break
        setdiff!(sc.skipped, consumed)
        candidates = held
    end
end

function mark!(sc::Scope)
    ci = sc.ci
    code = ci.code
    count = Dict{Int, Int}()
    for st in code
        countuses!(count, st)
    end
    # `a || b` stores `a` where it holds, and that store is never written: no second use.
    for c in values(sc.choices)
        v = code[c.yes].args[2]
        v isa Core.SSAValue && v == code[c.test].cond && (count[v.id] -= 1)
    end
    effectful = Set{Int}()
    for (i, st) in enumerate(code)
        choice = haskey(sc.choices, i)
        choice || st isa Expr && st.head === :call || continue
        # `SI.c`, a constant read through its module, is a name: free to repeat, so it
        # is always written where it's read, `SI_c * SI_c`.
        if !choice && callee_or_nothing(ci, st.args[1]) === Base.getproperty && literal(sc, st.args[2]) isa Module
            push!(sc.inlined, i)
            continue
        end
        get(count, i, 0) == 1 || continue
        T = widen(ci.ssavaluetypes[i])
        u = findfirst(s -> uses(s, i), code)
        use = code[u]
        use isa Expr && use.head === :(=) && (use = use.args[2])
        # Scalars, and small structs held by value (no array fields): a struct result is
        # `conjugate(q)` where the author wrote it, and `(Point){x, y}` likewise. A struct
        # with an array field is built field by field, so only a call's result of one is
        # inlined, and only where the whole struct goes: returned, or passed to a call.
        # `f(q).v` would read a field of a temporary, which C allows and nobody writes.
        whole = use isa Core.ReturnNode ||
                use isa Expr && use.head === :call && !(callee_or_nothing(ci, use.args[1]) in (Base.getproperty, Core.getfield, Base.getindex))
        small = T <: Union{Number, Char} || !choice && isstruct(T) && !ismutabletype(T) &&
                (!any(isarray, fieldtypes(T)) || whole && !(callee_or_nothing(ci, st.args[1]) isa Type))
        small && !compiletime(ci.ssavaluetypes[i]) || continue
        use isa Expr && use.head === :call && duplicates(sc, u, use, i) && continue
        effect = !choice && (!pure(sc, st) || any(a -> a isa Core.SSAValue && a.id in effectful, st.args[2:end]))
        all(k -> effect ? silent(sc, k) : inert(sc, k), i+1:u-1) || continue
        push!(sc.inlined, i)
        effect && push!(effectful, i)
    end
    return effectful
end

# Where an array value can be computed straight into its place, sparing a temp and a
# copy: its one use is a field of a struct or tuple being built — `Quat(c, s * axis)`
# gives `mul_s_3(s, axis, q.v)` — and the destination is not touched, read, written or
# passed, by anything from the computation to the store: the statements between, the
# value's own operands, the construction's other arguments. The store moves earlier,
# so nothing may see it early; a destination nobody names, `result` or a temp, is safe
# by construction. Returns the construction's statement, the destination's name, its
# declaration if it needs one here, and the field — or `nothing`, and the temp stays.
function placement(sc::Scope, i)
    ci = sc.ci
    code = ci.code
    users = findall(st -> uses(st, i), code)
    length(users) == 1 || return nothing
    u = users[1]
    st = code[u]
    rhs = st isa Expr && st.head === :(=) ? st.args[2] : st
    rhs isa Expr && rhs.head === :call || return nothing
    f = callee_or_nothing(ci, rhs.args[1])
    T = widen(ci.ssavaluetypes[u])
    (f === Core.tuple && istuple(T) || f isa Type && isstruct(T) && !ismutabletype(T)) || return nothing
    args = rhs.args[2:end]
    count(a -> a isa Core.SSAValue && a.id == i, args) == 1 || return nothing
    k = findfirst(a -> a isa Core.SSAValue && a.id == i, args)
    if st isa Expr && st.head === :(=)
        slot = st.args[1].id
        slot in sc.hidden && return nothing
        istuple(T) && sc.kind !== nothing && returnedslot(ci) == slot && return nothing   # the function's own struct, built elsewhere
        # Touched means by C name, not by IR slot: a reassigned parameter is two slots
        # sharing one variable, and a read of the one is a read of the other.
        name = sc.names[slot]
        any(touches(sc, code[m], name) for m in i:u-1) && return nothing
        any(touches(sc, a, name) for a in args if !(a isa Core.SSAValue && a.id == i)) && return nothing
        declared = slot in sc.declared
        declared || sc.path[end] == get(sc.home, slot, 1) || return nothing     # declared here, or hoisted by the assignment: not both
        declared || push!(sc.declared, slot)
        return (u, sc.names[slot], declared ? nothing : declare(T, sc.names[slot]), fieldcnames(T)[k])
    elseif f === Core.tuple && sc.kind !== nothing && onlyreturned(ci, u)
        return (u, "result", sc.kind.cname * " result", sc.kind.fields[k])
    elseif f === Core.tuple
        return nothing                                  # a tuple spread into calls, or held whole: as before
    elseif onlyreturned(ci, u)
        isempty(sc.result) && return nothing
        return (u, result!(sc, u), declare(T, sc.expr[u]), fieldcnames(T)[k])
    else
        return (u, temp!(sc, u, parts(sc, rhs)), declare(T, sc.expr[u]), fieldcnames(T)[k])
    end
end

# Array variables that live in `out` from the start, so that the copies at the end
# vanish: for a function returning an array through `out`, a variable that every
# `return` places at one and the same rows of `out` — returned whole, `return x`, or
# as a block of a concatenation along the first dimension, `return [x; v]`, `[A; B]` —
# is those rows of `out` under its own name, a pointer to its first row; a reassigned
# parameter's working copy is made there instead of beside it, a local is declared
# there. Rows are the general case because the C is row-major: a block stacked along
# the first dimension with the full trailing extents is one contiguous span.
#
# Why this is safe by construction: `out` is the caller's memory, `restrict`, so nothing
# can see it before the function returns, and inside the function a variable's reads
# see its current value wherever that value lives. What must hold is only that the
# pieces don't overlap, that no `return` wants a variable somewhere else, and that no
# `return` computes into `out` from a variable now living in it — an operand aliasing a
# `restrict` output. Any of those, and nothing is placed: the copies stay.
function outplacement!(sc::Scope)
    sc.resultparam || return
    ci = sc.ci
    code = ci.code
    if shape(sc.rettype) === nothing
        # A regular array whose size Julia doesn't know: the sizes are learned as the
        # body is walked, so nothing can be laid out in `out` by size. What can is the
        # one case that needs no size: every `return` returning the same local
        # variable, whose size is `out`'s by definition.
        s = returnedslot(ci)
        s !== nothing && s > ci.nargs && !(s in sc.hidden) && isarray(slottype(sc, s)) || return
        sc.outplaced[s] = 0
        push!(sc.declared, s)
        push!(sc.pointers, sc.names[s])
        return
    end
    rows, trailing... = shape(sc.rettype)
    # A variable that can be rows of `out`: a local or working copy with the full trailing extents.
    fits(s) = s !== nothing && s > ci.nargs && !(s in sc.hidden) && isarray(slottype(sc, s)) &&
              shape(slottype(sc, s)) !== nothing && collect(shape(slottype(sc, s))[2:end]) == collect(trailing)
    wanted = Dict{Int, Int}()                       # slot -> its first row of `out`
    others = Any[]                                  # returned values computed into `out`
    for st in code
        st isa Core.ReturnNode && isdefined(st, :val) || continue
        v = st.val
        s = slotof(sc, v)
        if fits(s)
            get(wanted, s, 0) == 0 || return
            wanted[s] = 0
            continue
        end
        def = v isa Core.SSAValue ? code[v.id] : nothing
        if def isa Expr && def.head === :call && callee_or_nothing(ci, def.args[1]) in (Base.vcat, Base.vect, Base.typed_vcat)
            blocks = callee_or_nothing(ci, def.args[1]) === Base.typed_vcat ? def.args[3:end] : def.args[2:end]
            row = 0
            for b in blocks
                T = valuetype(sc, b)
                s = slotof(sc, b)
                if fits(s)
                    get(wanted, s, row) == row || return
                    wanted[s] = row
                end
                row += isarray(T) ? extent(T, 1) : 1
            end
            row == rows || return
            continue
        end
        push!(others, v)
    end
    isempty(wanted) && return
    # Pieces that don't overlap, and no other `return` reading a placed variable.
    spans = sort([(r, r + extent(slottype(sc, s), 1), s) for (s, r) in wanted])
    all(spans[k][2] <= spans[k+1][1] for k in 1:length(spans)-1) && spans[end][2] <= rows || return
    for v in others, (s, _) in wanted
        touches(sc, v, sc.names[s]) && return
    end
    for (s, r) in wanted
        sc.outplaced[s] = r
        push!(sc.declared, s)
        push!(sc.pointers, sc.names[s])
    end
end

# The slot an IR value is, if it is one: the slot itself, an SSA value that just reads
# it, or the value of a store into it, `%i = (a = …)`, as long as the slot isn't
# reassigned before the value is used.
function slotof(sc::Scope, x)
    x isa Core.SlotNumber && return x.id
    x isa Core.SSAValue || return nothing
    st = sc.ci.code[x.id]
    st isa Core.SlotNumber && return st.id
    st isa Expr && st.head === :(=) && stable(sc.ci, x.id, st.args[1].id) && return st.args[1].id
    return nothing
end

# The variable the `return` at statement `r` returns, when it is one: `return a`, or
# `a = …` as the last expression, whose value Julia returns as the value stored
# rather than as a read of `a` (see `foldstores!`).
function returnslot(ci, r)
    st = ci.code[r]
    st isa Core.ReturnNode && isdefined(st, :val) || return nothing
    v = st.val
    v isa Core.SlotNumber && return v.id
    v isa Core.SSAValue || return nothing
    def = ci.code[v.id]
    def isa Core.SlotNumber && return def.id
    def isa Expr && def.head === :(=) && stable(ci, v.id, def.args[1].id) && return def.args[1].id
    return nothing
end

# `a = A[2, :]` as a function's last expression: Julia returns the value stored, so the
# call's value has two users, the store and the `return`, and would be computed into a
# temp and copied to `a`. The call is moved into the store and the store's own SSA
# value made a read of it — `%i = (a = A[2, :])`, `%j = %i` — and the value is
# computed straight into `a`, which the `return` then names. Any call whose next
# statement stores it and whose other users are all returns.
function foldstores!(sc::Scope)
    code = sc.ci.code
    for (i, st) in enumerate(code)
        st isa Expr && st.head === :call && i < length(code) || continue
        t = sc.ci.ssavaluetypes[i]
        t isa Core.Const && (t.val isa Char || t.val isa AbstractString) && continue   # a literal, written where it is used
        next = code[i+1]
        next isa Expr && next.head === :(=) && next.args[2] == Core.SSAValue(i) || continue
        all(u == i + 1 || code[u] isa Core.ReturnNode for u in eachindex(code) if uses(code[u], i)) || continue
        code[i] = Expr(:(=), next.args[1], st)
        code[i+1] = Core.SSAValue(i)
    end
end

# Is the returned value a variable that lives in all of `out` already?
outplacedwhole(sc::Scope, v) = (s = slotof(sc, v); s !== nothing && get(sc.outplaced, s, -1) == 0 && extent(slottype(sc, s), 1) == shape(sc.rettype)[1])

# Is this block of a concatenation a variable living from row `row` of `out` already?
outplacedat(sc::Scope, b, row) = (s = slotof(sc, b); s !== nothing && get(sc.outplaced, s, -1) == row)

# Does the IR value or statement name the C variable anywhere — as a read, an
# assignment, an argument — itself or through the values it is built from? Any slot
# with that C name counts; so does an array parameter's working copy of that name.
touches(sc::Scope, x, name) = x isa Core.SlotNumber ? sc.names[x.id] == name || get(sc.rebound, x.id, 0) != 0 && sc.names[sc.rebound[x.id]] == name :
                              x isa Core.SSAValue   ? touches(sc, sc.ci.code[x.id], name) :
                              x isa Expr            ? any(a -> touches(sc, a, name), x.args) :
                              x isa Core.ReturnNode ? isdefined(x, :val) && touches(sc, x.val, name) :
                              x isa Core.GotoIfNot  ? touches(sc, x.cond, name) : false

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
    f === Base.minmax && return true                  # each argument is in the minimum and in the maximum
    # `A[k]` on a matrix writes `k` once for each dimension (`linear`).
    f === Base.getindex && length(use.args) == 3 && isarray(valuetype(sc, use.args[2])) && ndims(valuetype(sc, use.args[2])) > 1 && return use.args[3] == Core.SSAValue(i)
    r = idiom(f, T, [widen(valuetype(sc, a)) for a in use.args[2:end]])
    r === nothing || return any(k -> use.args[k+1] == Core.SSAValue(i) && twice(r, k), 1:length(use.args)-1)
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
        st isa Core.SSAValue || st isa Number || st isa Expr && st.head in (:meta, :code_coverage_effect, :static_parameter)
end

# Calls with an effect the C must keep in order: writes and prints. Anything foreign
# (a `ccall`) counts as both.
const writing = (Base.setindex!, Base.setproperty!, Core.setfield!, Base.push!, Base.pop!, Base.fill!, Base.copyto!, Base.materialize!, Core.setglobal!)
const printing = (Base.print, Base.println, Printf.format)
const known = (:Core, :Base, :LinearAlgebra, :StaticArrays, :Printf, :Statistics)

# Is this call free of effects? Julia's own functions are, except the ones above; a
# user function is examined (`effects!`).
function pure(sc::Scope, st::Expr)
    f = callee_or_nothing(sc.ci, st.args[1])
    f === nothing && return false
    (f in writing || f in printing) && return false
    f isa Type && return true
    r = userinstance!(sc, f, st.args[2:end])   # the user's method, even of a Julia operator
    r === nothing || return isempty(effects!(sc.prog, r[1]))
    return nameof(Base.moduleroot(parentmodule(f))) in known
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
    x isa Core.SSAValue && x.id in sc.inlined && haskey(sc.choices, x.id) && return chosen(sc, sc.choices[x.id])
    x isa Core.SSAValue && haskey(sc.alias, x.id) && return sc.alias[x.id] isa Tuple ? render(sc, sc.alias[x.id]...) : expression(sc, sc.alias[x.id])
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
