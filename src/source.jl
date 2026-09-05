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
    return Source(basename(path), String.(lines), m.line, last, !(ex isa Expr && ex.head === :function))
end

# The source line of each IR statement, 0 where there is none.
function statementlines(mi::Core.MethodInstance, n::Integer)
    ci = Base.uncompressed_ast(mi.def)
    length(ci.code) == n || return zeros(Int, n)
    return [Base.IRShow.getdebugidx(ci.debuginfo, i)[1] for i in 1:n]
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
            block = [strip(l) for l in src.lines[start:k]]
            block[1] = replace(block[1], r"^\"+" => "")
            block[end] = replace(block[end], r"\"+$" => "")
            # Keep blank lines inside the docstring; drop the ones the delimiters leave.
            while !isempty(block) && isempty(block[1]); popfirst!(block); end
            while !isempty(block) && isempty(block[end]); pop!(block); end
            append!(doc, block)
            k = start - 1
        elseif endswith(s, "=#")
            start = something(findprev(l -> occursin("#=", l), src.lines, k), k)
            block = [strip(replace(l, "#=" => "", "=#" => "")) for l in src.lines[start:k]]
            append!(out, reverse(comment.(filter(!isempty, block))))
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
    for k in max(from, 1):min(to, length(src.lines))
        line = src.lines[k]
        s = strip(line)
        if inblock
            inblock = !occursin("=#", s)
            t = strip(replace(s, "=#" => ""))
            isempty(t) || push!(out, comment(t))
            continue
        end
        isempty(s) && continue
        if startswith(s, "#=")
            inblock = !occursin("=#", s[3:end])
            t = strip(replace(s[3:end], "=#" => ""))
            isempty(t) || push!(out, comment(t))
            continue
        end
        text, trailing = split_comment(s)
        if isempty(text)
            push!(out, comment(trailing))
        elseif minor(text) || (k == src.first && !src.short)
            trailing === nothing || push!(out, comment(trailing))
        elseif code
            push!(out, "// $(src.name):$k: $s")
        elseif trailing !== nothing
            push!(out, comment(trailing))
        end
    end
    return out
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


