# A function handed to one of Julia's own: `sum(abs, v)`, `map(x -> x^2, v)`, `any(x -> x > t,
# v)`, `count(isodd, v)`, a `do` block, a generator, `sum(1 / k^2 for k in 1:n)`. Each is the
# loop it stands for, written where the call is, with the function applied to the element in
# the loop's body: a lambda of one expression as that expression, anything else as a call.
#
#     s = sum(x -> x^2, v)            double s = 0.0;
#                                     for (int64_t i = 0; i < 4; i++) {
#                                         s += v[i] * v[i];
#                                     }

# What each of them does with the values, one after another.
const folds = Dict{Any, Symbol}(Base.sum => :sum, Base.prod => :prod, Base.any => :any, Base.all => :all, Base.count => :count,
                                Base.maximum => :maximum, Base.minimum => :minimum, Base.map => :map, Base.collect => :map, Base.foreach => :foreach)

# Is `ex` such a call? Then what it does, the function, and what it goes over; else nothing.
function folded(sc::Scope, ex)
    ex isa Expr && ex.head === :call || return nothing
    ci = sc.ci
    f = callee_or_nothing(ci, ex.args[1])
    op = get(folds, f, nothing)
    op === nothing && return nothing
    args = ex.args[2:end]
    # `sum(g(x) for x in v)`, `[g(x) for x in v]`: a generator is the function and what it goes over.
    if length(args) == 1 && args[1] isa Core.SSAValue && called(ci, ci.code[args[1].id]) === Base.Generator
        args = ci.code[args[1].id].args[2:end]
    elseif f === Base.collect
        return nothing
    end
    length(args) >= 2 || return nothing
    F = functiontype(sc, args[1])
    F === nothing && return nothing
    length(args) == 2 || op === :map || return nothing
    return (op, args[1], args[2:end])
end

# The function a statement calls, or nothing.
called(ci, st) = st isa Expr && st.head === :call ? callee_or_nothing(ci, st.args[1]) : nothing

# The type of a value that is a function, or nothing.
function functiontype(sc::Scope, x)
    t = x isa Core.SSAValue ? sc.ci.ssavaluetypes[x.id] : x isa Core.SlotNumber ? sc.ci.slottypes[x.id] : x isa GlobalRef ? Core.Const(getfield(x.mod, x.name)) : nothing
    t isa Core.Const && (t = typeof(t.val))
    t isa Core.PartialStruct && (t = t.typ)
    # A struct of the author's with a method of its own, `(p::Poly)(x)`, is called as one is.
    return t isa DataType && isconcretetype(t) && (t <: Function || isstruct(t) && !isempty(Base._methods_by_ftype(Tuple{t, Vararg{Any}}, -1, Base.get_world_counter()))) ? t : nothing
end

# Before anything is written: a range or a generator that only feeds one of these is no
# statement of its own.
function folds!(sc::Scope)
    ci = sc.ci
    for st in ci.code
        ex = consumer(st)
        r = folded(sc, ex)
        r === nothing && continue
        a = ex.args[2]
        if a isa Core.SSAValue && called(ci, ci.code[a.id]) === Base.Generator
            push!(sc.skipped, a.id)
        end
        for it in r[3]
            it isa Core.SSAValue && called(ci, ci.code[it.id]) === Base.Colon() && count(u -> uses(u, it.id), ci.code) == 1 && push!(sc.skipped, it.id)
        end
    end
end

# One thing gone over: the loops' headers, and the element as C text.
struct Span
    headers::Vector{String}
    element::String
    type::Type
end

# What `x` is gone over as: an array element by element, a range of integers value by value.
# `taken` are the names an index must keep clear of; `var` is the name a range's values take.
#
# `ordered` is for a function that does something besides compute, where the order it is
# called in shows: a matrix is then gone over as Julia goes over it, down each column, where
# otherwise it is gone over as C stores it. `lines` takes what has to be written before the loop.
function span(sc::Scope, x, taken, var, extra::AbstractString=""; ordered::Bool=false, lines=nothing)
    ci = sc.ci
    T = valuetype(sc, x)
    if isarray(T) && shape(T) !== nothing
        ordered && istransposed(T) && ndims(T) > 1 && throw(ArgumentError("going over a transposed matrix with a function that prints or writes is not supported; store the matrix first (line $(sc.stmtline[sc.current]))"))
        idx = indices(ndims(T); taken)
        headers = ["for (int64_t $k = 0; $k < $n$extra; $k++) {" for (k, n) in zip(idx, shape(T))]
        ordered && reverse!(headers)
        return Span(headers, value(sc, x) * join("[$k]" for k in idx), eltype(T)), idx
    end
    if x isa Core.SSAValue && called(ci, ci.code[x.id]) === Base.Colon()
        r = ci.code[x.id].args[2:end]
        E = eltype(widen(ci.ssavaluetypes[x.id]))
        E <: Integer || throw(ArgumentError("a range of $E is not supported here; go over a range of integers (line $(sc.stmtline[sc.current]))"))
        lo, hi = bound(sc, r[1]), bound(sc, r[end])
        # Julia builds the range once, so its end is read once; C's header reads it every pass.
        # An end that is more than a name or a number is taken into a temp first, as a `for` does.
        if lines !== nothing && r[end] isa Core.SSAValue && r[end].id in sc.inlined && !simple(expression(sc, r[end]))
            t = temp!(sc, nothing, contribution(sc, r[end]))
            emit!(lines, sc, "$(ctype(E)) $t = $hi;")
            hi = t
        end
        v = free(var, taken)
        if length(r) == 2
            return Span(["for ($(ctype(E)) $v = $lo; $v <= $hi$extra; $v++) {"], v, E), [v]
        end
        s = literal(sc, r[2])
        s isa Integer && s != 0 || throw(ArgumentError("a range's step must be a number written out (line $(sc.stmtline[sc.current]))"))
        return Span(["for ($(ctype(E)) $v = $lo; $v $(s > 0 ? "<=" : ">=") $hi$extra; $v += $s) {"], v, E), [v]
    end
    throw(ArgumentError("going over a $T with a function is not supported: an array of a known size or a range of integers is (line $(sc.stmtline[sc.current]))"))
end

# The function value `fv` applied to the C texts `texts`, of types `types`, as C text.
function apply(sc::Scope, i, fv, texts, types)
    ci = sc.ci
    F = functiontype(sc, fv)
    if islambda(F)
        k = tuplekind(sc, fv)
        t = inlined(sc, F, k === nothing ? String[] : k.fields, texts, types)
        t === nothing || return t
    end
    return called!(sc, i, fv, texts, types)
end

# The same as a call, whatever the function's body is. With `lines`, the call is written
# there as a statement, for what it does and not for its value: `println(x)` is a `printf`.
function called!(sc::Scope, i, fv, texts, types; lines=nothing)
    ci = sc.ci
    F = functiontype(sc, fv)
    # A call: the texts stand in as variables of Julia's own, and the call is a statement like any other.
    R = try only(Base.code_typed_by_type(Tuple{F, types...}; optimize=false))[2] catch; Any end
    slots = Any[standin!(sc, t, T) for (t, T) in zip(texts, types)]
    ex = fieldcount(F) > 0 ? Expr(:call, Called{F}(), fv, slots...) : Expr(:call, fv, slots...)
    return synthetic(sc, i, ex, R; lines)
end

# A variable of Julia's own that is written as the C text `text`.
function standin!(sc::Scope, text, T)
    ci = sc.ci
    # `sc.names` also holds the indices the loops were given, past the last variable; a new
    # variable goes after those, so that its number finds its name.
    while length(ci.slotnames) < length(sc.names)
        push!(ci.slotnames, Symbol("")); push!(ci.slottypes, Union{}); push!(ci.slotflags, 0x00)
        push!(sc.hidden, length(ci.slotnames))
    end
    while length(sc.names) < length(ci.slotnames)
        push!(sc.names, "")
    end
    push!(ci.slotnames, Symbol(""))
    push!(ci.slottypes, T)
    push!(ci.slotflags, 0x00)
    push!(sc.names, text)
    push!(sc.hidden, length(ci.slotnames))
    return Core.SlotNumber(length(ci.slotnames))
end

# The call `ex`, of type `R`, written as if it were a statement of the function.
function synthetic(sc::Scope, i, ex::Expr, R; lines=nothing)
    ci = sc.ci
    push!(ci.code, ex)
    push!(ci.ssavaluetypes, R)
    push!(sc.stmtline, sc.stmtline[i])
    j = length(ci.code)
    try
        lines === nothing && return string(render(sc, j, ex))
        if widen(R) === Nothing || callee_or_nothing(ci, ex.args[1]) in (Base.print, Base.println)
            written!(lines, sc, j, ex)
        else
            emit!(lines, sc, string(render(sc, j, ex)) * ";")
        end
        sc.current = i
        return ""
    finally
        pop!(ci.code); pop!(ci.ssavaluetypes); pop!(sc.stmtline)
    end
end

# The one expression a lambda of type `F` returns, with its parameters written as `texts` and
# what it captured as `captures`; nothing if its body is more than one expression.
function inlined(sc::Scope, F::Type, captures, texts, types)
    mi = lookup(F, types)
    mi === nothing && return nothing
    prog = sc.prog
    lines = String[]
    try
        ci, R = only(Base.code_typed_by_type(mi.specTypes; optimize=false))
        R === Union{} && return nothing
        sub = ready("", mi, argtypes(mi), prog, returntype(mi), sc.limit, false, nothing)
        length(sub.ci.slotnames) == length(texts) + 1 || return nothing        # a variable of its own: a body of several lines
        for (k, t) in enumerate(texts)
            sub.names[k+1] = t
        end
        sub.slotkinds[1] = Kind("", collect(String, captures))
        sub.outer = union(sc.outer, sc.names)
        walk!(lines, sub)
        union!(sc.outer, intersect(sub.outer, filescope(prog)))
    finally
        prog.walking = sc
    end
    body = [strip(l) for l in lines if !isempty(strip(l)) && !startswith(strip(l), "//")]
    length(body) == 1 || return nothing
    m = match(r"^return (.*);$", body[1])
    return m === nothing ? nothing : String(m[1])
end

# C text that can stand as an operand anywhere: a name, an element, a call.
operandtext(t) = occursin(r"^[\w.]+(\[[^\]]*\])*$", t) || occursin(r"^\w*\([^()]*\)$", t) ? t : "($t)"

# The value-producing ones, at statement `i`: the loop is written here. Returns the lines to
# write after the statement, when the statement itself declares what the loop works on.
function fold!(lines, sc::Scope, i, st)
    ci = sc.ci
    ex = consumer(st)
    r = folded(sc, ex)
    (r === nothing || r[1] === :map || haskey(sc.ready, i)) && return nothing
    op, fv, iters = r
    T = widen(ci.ssavaluetypes[i])
    if op === :foreach
        # Nothing comes of it but what the function does: the loop, and the call in it.
        sp, idx = span(sc, iters[1], union(sc.names, sc.outer), "i"; ordered=true, lines)
        mine = setdiff(idx, sc.outer)
        union!(sc.outer, mine)
        foreach(h -> (emit!(lines, sc, h); sc.depth += 1), sp.headers)
        try called!(sc, i, fv, [sp.element], [sp.type]; lines) finally setdiff!(sc.outer, mine) end
        foreach(_ -> (sc.depth -= 1; emit!(lines, sc, "}")), sp.headers)
        return :done
    end
    T <: Union{Number, Bool} || throw(ArgumentError("`$(op)` with a function, giving a $T, is not supported: a number is (line $(sc.stmtline[i]))"))
    taken = union(sc.names, sc.outer)
    F = functiontype(sc, fv)
    var = islambda(F) && (m = lookup(F, [Int]); m !== nothing) ? identifier(string(Base.method_argnames(m.def)[2])) : "i"
    var = occursin(r"^\w+$", var) && !(var in reserved) ? var : "i"
    # Where the value goes: the variable it is stored in, when the loop can work there; else a temp.
    store = st isa Expr && st.head === :(=) && st.args[1] isa Core.SlotNumber && slottype(sc, st.args[1].id) === T &&
            stable(ci, i, st.args[1].id) ? sc.names[st.args[1].id] : nothing
    It = valuetype(sc, iters[1])
    many = op in (:any, :all) && isarray(It) && ndims(It) > 1
    ordered = !isempty(handedeffects!(sc.prog, F))
    op in (:maximum, :minimum) && isarray(It) && shape(It) !== nothing && prod(shape(It)) == 0 &&
        throw(ArgumentError("`$op` over an array of no elements has no value (line $(sc.stmtline[i]))"))
    # `acc = max(acc, t)`, as Julia's `max` is written for the type. Where that writes `t` twice
    # and `t` is more than a name, it is worked out once first.
    extreme(acc, t) = begin
        g = op === :maximum ? Base.max : Base.min
        written(x) = synthetic(sc, i, Expr(:call, g, standin!(sc, acc, T), standin!(sc, x, T)), T)
        text = written(operandtext(t))
        pre = String[]
        if count(operandtext(t), text) > 1 && !occursin(r"^[\w.]+(\[[^\]]*\])*$", t)
            name = temp!(sc, nothing, String[])
            push!(pre, "$(declare(T, name)) = $t;")
            text = written(name)
        end
        text = replace(text, ", ($t))" => ", $t)")
        startswith(text, "(") && endswith(text, ")") && !occursin(r"^\([^()]*\).*\(", text) && (text = text[2:end-1])
        [pre; "$acc = $text;"]
    end
    build(acc) = begin
        extra = many ? (op === :any ? " && !$acc" : " && $acc") : ""
        sp, idx = span(sc, iters[1], union(taken, [acc]), var, extra; ordered, lines)
        mine = setdiff(idx, sc.outer)             # an index is a name to keep clear of while its loop is written
        union!(sc.outer, mine)
        t = try apply(sc, i, fv, [sp.element], [sp.type]) finally setdiff!(sc.outer, mine) end
        body = op === :sum ? ["$acc += $t;"] : op === :prod ? ["$acc *= $t;"] :
               op === :count ? ["if ($t) {", "    $acc++;", "}"] :
               op === :any ? (many ? ["$acc = $t;"] : ["if ($t) {", "    $acc = true;", "    break;", "}"]) :
               op === :all ? (many ? ["$acc = $t;"] : ["if (!$(operandtext(t))) {", "    $acc = false;", "    break;", "}"]) :
               extreme(acc, t)
        (sp, body)
    end
    # Julia gives `maximum(abs, r)` of an empty range the value 0, where any other function
    # throws: the one empty case that reaches C, so the start says it.
    emptied = op in (:maximum, :minimum) && shape(It) === nothing && isdefined(F, :instance) && F.instance in (Base.abs, Base.abs2) &&
              iters[1] isa Core.SSAValue && called(ci, ci.code[iters[1].id]) === Base.Colon()
    start = op in (:sum, :count) ? value(sc, zero(T)) : op === :prod ? value(sc, one(T)) : op === :any ? value(sc, false) : op === :all ? value(sc, true) :
            T <: AbstractFloat ? (push!(sc.headers, "math.h"); op === :maximum ? "-INFINITY" : "INFINITY") : value(sc, op === :maximum ? typemin(T) : typemax(T))
    if emptied
        r = ci.code[iters[1].id].args[2:end]
        s = length(r) == 3 ? literal(sc, r[2]) : 1
        start = "$(bound(sc, r[1])) $(s isa Integer && s < 0 ? "<" : ">") $(bound(sc, r[end])) ? $(value(sc, zero(T))) : $start"
    end
    write(acc) = begin
        sp, body = build(acc)
        for (d, h) in enumerate(sp.headers)
            emit!(lines, sc, h); sc.depth += 1
        end
        foreach(l -> emit!(lines, sc, l), body)
        for _ in sp.headers
            sc.depth -= 1; emit!(lines, sc, "}")
        end
    end
    # The variable's own name must not be something the loop reads: `n = sum(f, 1:n)`.
    mentioned(name) = any(a -> (a isa Core.SSAValue || a isa Core.SlotNumber) && occursin(Regex("\\b\\Q$name\\E\\b"), try value(sc, a) catch; "" end),
                          [iters; fv isa Core.SSAValue || fv isa Core.SlotNumber ? [fv] : []]) ||
                      (k = tuplekind(sc, fv); k !== nothing && name in k.fields) ||
                      any(it -> it isa Core.SSAValue && called(ci, ci.code[it.id]) === Base.Colon() && any(b -> occursin(Regex("\\b\\Q$name\\E\\b"), bound(sc, b)), ci.code[it.id].args[2:end]), iters)
    if store !== nothing && !mentioned(store)
        sc.ready[i] = start
        return () -> write(store)
    end
    acc = st isa Expr && st.head === :call && onlyreturned(ci, i) ? result!(sc, i) :
          temp!(sc, nothing, unique(reduce(vcat, (contribution(sc, a) for a in iters); init=String[])))
    emit!(lines, sc, "$(declare(T, acc)) = $start;")
    write(acc)
    sc.ready[i] = acc
    sc.expr[i] = acc
    return st isa Expr && st.head === :call ? :done : nothing
end

# `map(f, v)`, `map(f, a, b)`, `[f(x) for x in v]`: the array of what `f` gives, into `dest`.
function maploop!(lines, sc::Scope, i, ex::Expr, dest; declaration::Bool=false)
    ci = sc.ci
    _, fv, iters = folded(sc, ex)
    # `[f(k) for k in 1:4]`: over a range written out, an array of its length.
    if length(iters) == 1 && iters[1] isa Core.SSAValue && called(ci, ci.code[iters[1].id]) === Base.Colon()
        r = [literal(sc, b) for b in ci.code[iters[1].id].args[2:end]]
        all(b -> b isa Integer, r) || throw(ArgumentError("an array made by going over a range needs the range written in numbers, `1:4`, for C to know its size (line $(sc.stmtline[i]))"))
        lo, step, hi = r[1], length(r) == 3 ? r[2] : 1, r[end]
        n = length(lo:step:hi)
        R = shaped(eltype(widen(ci.ssavaluetypes[i])), (n,))
        declaration && emit!(lines, sc, declare(R, dest) * ";")
        F = functiontype(sc, fv)
        var = islambda(F) && (m = lookup(F, [Int]); m !== nothing) ? identifier(string(Base.method_argnames(m.def)[2])) : "i"
        var = occursin(r"^\w+$", var) && !(var in reserved) ? var : "i"
        sp, idx = span(sc, iters[1], union(sc.names, sc.outer, [dest]), var; lines)
        mine = setdiff(idx, sc.outer)
        union!(sc.outer, mine)
        t = try apply(sc, i, fv, [sp.element], [sp.type]) finally setdiff!(sc.outer, mine) end
        k = idx[1]
        at = step == 1 ? (lo == 0 ? k : lo > 0 ? "$k - $lo" : "$k + $(-lo)") : "($k - $(lo < 0 ? "($lo)" : lo)) / $(step < 0 ? "($step)" : step)"
        emit!(lines, sc, sp.headers[1]); sc.depth += 1
        emit!(lines, sc, "$dest[$at] = $t;")
        sc.depth -= 1; emit!(lines, sc, "}")
        sc.shapes[i] = R
        return
    end
    types = [valuetype(sc, a) for a in iters]
    all(isarray, types) || throw(ArgumentError("`map` with a function goes over arrays of one known size; got $(join(types, ", ")) (line $(sc.stmtline[i]))"))
    T = widen(ci.ssavaluetypes[i])
    R = shape(T) !== nothing ? T : shaped(eltype(T), shape(types[1]))
    maploop!(lines, sc, i, fv, iters, R, dest; declaration)
    sc.shapes[i] = R
end

# The function `fv` applied element by element to `inputs`, arrays of one size and numbers
# beside them, into the array `dest` of type `R`.
function maploop!(lines, sc::Scope, i, fv, inputs, R::Type, dest; declaration::Bool=false)
    types = [valuetype(sc, a) for a in inputs]
    arrays = filter(isarray, types)
    all(T -> shape(T) !== nothing && !istransposed(T), arrays) && allequal(shape.(arrays)) && !istransposed(R) ||
        throw(ArgumentError("a function applied element by element goes over arrays of one known size, none transposed; got $(join(describe.(arrays), ", ")) (line $(sc.stmtline[i]))"))
    declaration && emit!(lines, sc, declare(R, dest) * ";")
    F = functiontype(sc, fv)
    sp, idx = span(sc, inputs[findfirst(isarray, types)], union(sc.names, sc.outer, [dest]), "i"; ordered=F !== nothing && !isempty(handedeffects!(sc.prog, F)))
    at = join("[$k]" for k in idx)
    mine = setdiff(idx, sc.outer)
    union!(sc.outer, mine)
    # A number beside the arrays is worked out once in Julia, before the loop: so here, unless it is a name or a number already.
    scalar(a, T) = begin
        t = expression(sc, a)
        simple(t) && return operandtext(string(t))
        name = temp!(sc, nothing, contribution(sc, a))
        emit!(lines, sc, "$(declare(T, name)) = $t;")
        name
    end
    texts = [isarray(T) ? value(sc, a) * at : scalar(a, T) for (a, T) in zip(inputs, types)]
    t = try apply(sc, i, fv, texts, [isarray(T) ? eltype(T) : T for T in types]) finally setdiff!(sc.outer, mine) end
    for h in sp.headers
        emit!(lines, sc, h); sc.depth += 1
    end
    emit!(lines, sc, "$dest$at = $t;")
    for _ in sp.headers
        sc.depth -= 1; emit!(lines, sc, "}")
    end
end


# A function of Julia's that gives two values, read by destructuring, `q, r = divrem(a, b)`:
# each is written where it is read, as `sincos` is (`pair!`). An argument that is more than a
# name is worked out once first, since each value reads it.
function paired!(lines, sc::Scope, i, st::Expr)
    ci = sc.ci
    f = callee_or_nothing(ci, st.args[1])
    f in (Base.sincosd, Base.divrem, Base.fldmod, Base.modf, Base.frexp) || return false
    args = st.args[2:end]
    P = widen(ci.ssavaluetypes[i])
    P isa DataType && P <: Tuple && length(P.parameters) == 2 || return false
    types = [valuetype(sc, a) for a in args]
    ok = f in (Base.divrem, Base.fldmod) ? length(args) == 2 && types[1] <: Base.BitInteger64 && types[1] === types[2] :
         f === Base.sincosd ? types == [Float64] : length(args) == 1 && types[1] <: Union{Float32, Float64}
    ok || return false
    # What each value reads: the argument itself when it is a name or a number, else a temp.
    names = Any[]
    for (a, A) in zip(args, types)
        t = expression(sc, a)
        if t.kind in (:atom, :number)
            push!(names, a)
        else
            name = temp!(sc, nothing, contribution(sc, a))
            emit!(lines, sc, "$(declare(A, name)) = $t;")
            push!(names, standin!(sc, name, A))
        end
    end
    one(g, R) = operandtext(synthetic(sc, i, Expr(:call, g, names...), R))
    first, second = if f === Base.divrem
        one(Base.div, P.parameters[1]), one(Base.rem, P.parameters[2])
    elseif f === Base.fldmod
        one(Base.fld, P.parameters[1]), one(Base.mod, P.parameters[2])
    elseif f === Base.sincosd
        one(Base.sind, Float64), one(Base.cosd, Float64)
    else
        x = value(sc, names[1])
        s = types[1] === Float32 ? "f" : ""
        push!(sc.headers, "math.h")
        if f === Base.modf
            # The part past the point with the number's sign, and the whole part; an infinity has no part past the point.
            "copysign$s(isinf($x) ? 0 : $x - trunc$s($x), $x)", "trunc$s($x)"
        else
            # `frexp` hands the exponent back through a pointer, and says nothing of it for a NaN or an infinity, where Julia says 0.
            m, e = temp!(sc, nothing, contribution(sc, names[1])), temp!(sc, nothing, String[])
            emit!(lines, sc, "int $e;")
            emit!(lines, sc, "$(declare(types[1], m)) = frexp$s($x, &$e);")
            m, "(int64_t)(isfinite($x) ? $e : 0)"
        end
    end
    pair!(lines, sc, i, args, first, second)
    return true
end
