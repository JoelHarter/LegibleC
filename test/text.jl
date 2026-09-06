# Characters and strings, where Julia and C agree: ASCII `char`, UTF-8 `const char *`.
module Text
using Test
import Main: Case, check, csource

classes(c::Char) = (isdigit(c) ? 1 : 0) + (isletter(c) ? 2 : 0) + (isspace(c) ? 4 : 0) + (isuppercase(c) ? 8 : 0) + (islowercase(c) ? 16 : 0) + (ispunct(c) ? 32 : 0)
shift(c::Char) = c + 1
offset(c::Char) = c - 'a'
code(c::Char) = Int(c)
fromcode(n::Int64) = Char(n)
upper(c::Char) = uppercase(c)
folded(c::Char) = uppercase(c) == lowercase(c)
between(c::Char) = 'a' <= c <= 'z'
same(s::String) = s == "abc"
differ(s::String, t::String) = s != t
chars(s::String) = length(s)
bytes(s::String) = ncodeunits(s)
second(s::String) = s[2]
blank(s::String) = isempty(s)
count_a(s::String) = (n = 0; for i in 1:ncodeunits(s); s[i] == 'a' && (n += 1); end; n)
greet(s::String) = (println("hello, ", s); s)
newline(c::Char) = c == '\n' ? 'x' : c

check("text", [Case(classes, 'a'), Case(classes, '7'), Case(classes, ' '), Case(classes, 'Q'), Case(classes, '!'),
               Case(shift, 'a'), Case(offset, 'd'), Case(code, 'A'), Case(fromcode, 66), Case(upper, 'q'), Case(upper, '3'),
               Case(folded, 'a'), Case(folded, '7'), Case(between, 'm'), Case(between, 'M'),
               Case(same, "abc"), Case(same, "abd"), Case(differ, "x", "y"), Case(differ, "x", "x"),
               Case(chars, "héllo"), Case(bytes, "héllo"), Case(second, "abc"), Case(blank, ""), Case(blank, "x"),
               Case(count_a, "banana"), Case(newline, '\n'), Case(newline, 'q')])
@testset "text" begin
    src = csource("texttext", classes, upper, same, chars, second, blank, greet, offset)
    @test occursin("#include <ctype.h>", src) && occursin("isdigit(c)", src) && occursin("isalpha(c)", src) && occursin("isupper(c)", src)
    @test occursin("return (char)toupper(c);", src)
    @test occursin("return strcmp(s, \"abc\") == 0;", src)
    @test occursin("return utf8len(s);", src) && occursin("if ((*s & 0xC0) != 0x80) {", src)
    @test occursin("return s[1];", src) && occursin("return s[0] == '\\0';", src)
    @test occursin("const char *greet(const char *s) {", src) && occursin("printf(\"hello, %s\\n\", s);", src)
    @test occursin("return c - 'a';", src) && occursin("@param[in] c  character", src) && occursin("@param[in] s  string", src)
    counted = csource("counted", count_a)
    @test occursin("int64_t temp1_s = (int64_t)strlen(s);\n    for (int64_t i = 1; i <= temp1_s; i++) {\n        if (s[i - 1] == 'a') {\n            n++;\n        }\n    }\n    return n;", counted)
    @test_throws ArgumentError csource("nonascii", (c::Char) -> c == 'é')
end
end
