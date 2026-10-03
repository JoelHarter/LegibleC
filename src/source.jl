# The Julia source around and inside a function, carried into the C as comments.
#
# Before the C definition: the comments and docstring directly above the Julia
# definition — walking upward until a line of code, a blank line, or the top of the
# file. Inside the body: every full comment line, every trailing comment, and (with
# the `source` option) every line of code, each prefixed `file:line:`, placed where
# that line's work happens in the C. Lines that are only closing brackets or `end`
# contribute their trailing comment but not their code.
#
# Line numbers per statement come from the lowered `CodeInfo` (`Base.uncompressed_ast`),
# whose statements match the unoptimized typed IR one for one; the typed IR from
# `code_typed_by_type` carries no line table of its own. `Base.IRShow.getdebugidx` is
# the accessor; it's internal, like the other reflection this project leans on.

# What's known about a method's source: the file's lines and the span the definition
# occupies. `nothing` when the file can't be found (a REPL definition, say).
struct Source
    name::String            # file name for the `file:line:` prefix
    lines::Vector{String}
    first::Int              # the signature's line
    last::Int               # the line the definition ends on
    short::Bool             # `f(x) = …` rather than `function f(x) … end`
end

function Source(m::Method)
    path = Base.find_source_file(string(m.file))
    (path === nothing || !isfile(path)) && return nothing
    text = read(path, String)
    lines = split(text, '\n'; keepempty=true)
    m.line in 1:length(lines) || return nothing
    offset = sum(ncodeunits(lines[k]) + 1 for k in 1:m.line-1; init=0) + 1
    ex, next = try Meta.parse(text, offset) catch; return nothing end
    stop = something(findprev(!isspace, text, prevind(text, next)), offset)
    last = count(==('\n'), SubString(text, 1, stop)) + 1
    # Short, `f(x) = …`: the body starts on the signature's line. Not `function … end`, and not
    # `f = () -> begin … end` either, a closure given a name, whose first line is a signature too.
    rhs = ex isa Expr && ex.head === :(=) ? ex.args[2] : ex
    short = !(rhs isa Expr && (rhs.head === :function || rhs.head === :-> && last > m.line))
    return Source(basename(path), String.(lines), m.line, last, short)
end

# The source line of each IR statement, 0 where there is none.
function statementlines(mi::Core.MethodInstance, n::Integer)
    ci = Base.uncompressed_ast(mi.def)
    length(ci.code) == n || return zeros(Int, n)
    lines = Int[Base.IRShow.getdebugidx(ci.debuginfo, i)[1] for i in 1:n]
    # A statement the IR gives no line — the `return true` that is all of `f() = true` —
    # belongs to the line before it, or to the definition's when it comes first.
    for k in 1:n
        lines[k] > 0 || (lines[k] = k == 1 ? mi.def.line : lines[k-1])
    end
    return lines
end

"""
    leading(src) -> (comments, docstring)

What sits directly above the definition: consecutive comment lines and block
comments, as `//` lines, and the docstring's text as written, stopping at a blank
line, a line of code, or the top of the file.
"""
function leading(src::Source)
    out = String[]
    doc = String[]
    k = src.first - 1
    while k >= 1
        s = strip(src.lines[k])
        if isempty(s)
            break
        elseif startswith(s, "\"") || endswith(s, "\"\"\"")
            # A docstring ends on this line. It starts here too unless the line only
            # closes a multi-line one; then look up for the line that opens it.
            start = k
            if endswith(s, "\"\"\"") && !(startswith(s, "\"\"\"") && length(s) > 6)
                start = something(findprev(l -> startswith(strip(l), "\"\"\""), src.lines, s == "\"\"\"" ? k - 1 : k), k)
            end
            block = [String(rstrip(l)) for l in src.lines[start:k]]
            block[1] = replace(block[1], r"^\s*\"+" => "")
            block[end] = replace(block[end], r"\"+$" => "")
            # Keep blank lines inside the docstring; drop the ones the delimiters leave.
            while !isempty(block) && isempty(strip(block[1])); popfirst!(block); end
            while !isempty(block) && isempty(strip(block[end])); pop!(block); end
            # Lines keep their indentation past the docstring's own, so an indented
            # formula or signature stays a block, as it reads in Julia.
            by = minimum((indentof(l) for l in block if !isempty(strip(l))); init=0)
            append!(doc, [isempty(strip(l)) ? "" : l[by+1:end] for l in block])
            k = start - 1
        elseif endswith(s, "=#")
            # A `#= … =#` block above the definition: one `/* … */` block.
            start = something(findprev(l -> occursin("#=", l), src.lines, k), k)
            block = filter(!isempty, [strip(replace(l, "#=" => "", "=#" => "")) for l in src.lines[start:k]])
            lines = length(block) == 1 ? ["/* " * block[1] * " */"] :
                    ["/* " * block[1]; "   " .* block[2:end-1]; "   " * block[end] * " */"]
            append!(out, reverse(lines))
            k = start - 1
        elseif startswith(s, "#")
            push!(out, comment(s[2:end]))
            k -= 1
        else
            break
        end
    end
    return reverse!(out), doc
end

"""
    doxygen(doc, julia, params) -> Vector{String}

A Doxygen block for a C function: the Julia docstring's text as written, then what the
C declaration can't say — which Julia method it came from, and which parameter carries
the Julia return value.
"""
function doxygen(doc, julia::AbstractString, params)
    lines = ["/**"]
    append!(lines, [isempty(l) ? " *" : " * " * l for l in doc])
    isempty(doc) || push!(lines, " *")
    push!(lines, " * Julia signature: " * julia)
    # `params` are (tag, name, description): the tags and the names each line up.
    tagwidth = maximum(length(p[1]) for p in params; init=0)
    width = maximum(length(p[2]) for p in params; init=0)
    for (tag, name, what) in params
        push!(lines, rstrip(" * @param" * rpad("[" * tag * "]", tagwidth + 2) * " " * rpad(name, width) * "  " * what))
    end
    push!(lines, " */")
    return lines
end

"""
    body(src, from, to; code=true) -> Vector{String}

C comment lines for source lines `from` through `to` of the body: comments carried
over, code carried over as `file:line: code` when `code` is set. Lines that are only
closing brackets or `end` — and the signature line of a long-form definition — give
up their trailing comment but not their code.
"""
function body(src::Source, from::Integer, to::Integer; code::Bool=true)
    out = String[]
    inblock = false
    k = max(from, 1) - 1
    while (k += 1) <= min(to, length(src.lines))
        line = src.lines[k]
        s = strip(line)
        isempty(s) && continue
        if startswith(s, "#=")
            # A `#= … =#` comment is one `/* … */` block, its lines' indentation kept
            # relative to the first; `*/` sits on the last line, or alone if `=#` did.
            e = k
            while !occursin("=#", e == k ? s[3:end] : src.lines[e]) && e < length(src.lines)
                e += 1
            end
            text = [k == e ? s[3:end] : s[3:end]; [src.lines[j] for j in k+1:e]]
            text[end] = replace(text[end], "=#" => "")
            alone = e > k && isempty(strip(text[end]))
            alone && pop!(text)
            text = dedent([strip(text[1]); text[2:end]]; by=indentof(line) + 3)   # `#= ` is three wide
            text = [rstrip(l) for l in text]
            if length(text) == 1
                push!(out, "/* " * strip(text[1]) * " */")
            else
                push!(out, "/* " * text[1])
                append!(out, "   " .* text[2:end-1])
                alone ? push!(out, "   " * text[end], "*/") : push!(out, "   " * text[end] * " */")
            end
            k = e
            continue
        end
        text, trailing = split_comment(s)
        if isempty(text)
            push!(out, comment(trailing))
        elseif minor(text) || (k == src.first && !src.short)
            trailing === nothing || push!(out, comment(trailing))
        elseif code
            # The line, prefixed `@file:line:`; a short-form definition's line contributes
            # only its body, since its signature is in the Doxygen block already. A
            # statement that runs on over several lines is one block comment, the range
            # in front and the lines inside with their own indentation kept.
            e = statementend(src, k)
            if e > k
                block = [k == src.first && src.short ? afterdef(s) : s; [src.lines[j] for j in k+1:e]]
                push!(out, "/* @$(src.name):$k-$e:")
                append!(out, "   " .* rstrip.(dedent(block; by=indentof(line))))
                push!(out, "*/")
                k = e
            else
                push!(out, "// @$(src.name):$k: " * (k == src.first && src.short ? afterdef(s) : s))
            end
        elseif trailing !== nothing
            push!(out, comment(trailing))
        end
    end
    return out
end

# Lines with `by` columns of leading whitespace removed from all but the first (which
# arrives already stripped), so the rest keep their indentation relative to it.
function dedent(lines; by::Integer)
    return [lines[1]; [indentof(l) >= by ? l[by+1:end] : lstrip(l) for l in lines[2:end]]]
end

indentof(l::AbstractString) = length(l) - length(lstrip(l))

# The last line of the Julia statement that starts at `line`: where its brackets have
# closed and the line doesn't end in an operator waiting for its right side.
function statementend(src::Source, line)
    depth = 0
    for k in line:length(src.lines)
        code, _ = split_comment(strip(src.lines[k]))
        for c in code
            c in "([{" && (depth += 1)
            c in ")]}" && (depth -= 1)
        end
        depth <= 0 && !(occursin(r"[-+*/\\^=,&|?:]$", code) && k < length(src.lines)) && return k
    end
    return line
end

# The last line of the statement that holds `to`, among the statements starting at `from`
# or after: `to` itself unless a statement that began earlier runs on past it.
function reach(src::Source, from, to)
    k = max(from, 1)
    while k <= min(to, length(src.lines))
        e = statementend(src, k)
        e >= to && return max(e, to)
        k = e + 1
    end
    return to
end

# The body of a short-form definition line, `f(x) = body`: what follows the `=` at the
# top level. The line itself if that isn't found.
function afterdef(s::AbstractString)
    cs = collect(s)
    depth = 0
    for (i, c) in enumerate(cs)
        c in "([{" && (depth += 1)
        c in ")]}" && (depth -= 1)
        depth == 0 && c == '=' && 1 < i < length(cs) && !(cs[i-1] in "=<>!:") && cs[i+1] != '=' && return strip(String(cs[i+1:end]))
    end
    return s
end

# Split a line into its code and its trailing comment (without the `#`), the latter
# `nothing` if there is none. Skips `#` inside string literals.
function split_comment(s::AbstractString)
    instring = false
    prev = ' '
    for (i, c) in pairs(s)
        c == '"' && prev != '\\' && (instring = !instring)
        c == '#' && !instring && return rstrip(s[1:prevind(s, i)]), s[nextind(s, i):end]
        prev = c
    end
    return s, nothing
end

# Only closing brackets and `end`: no code worth carrying over.
minor(text) = occursin(r"^[\s\)\]\}]*(end)?[\s\)\]\}]*$", text)

# A Julia comment's text as a C comment line.
comment(text) = (t = lstrip(text); isempty(t) ? "//" : "// " * rstrip(t))


