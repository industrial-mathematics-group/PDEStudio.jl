# f3ed3a2: `_empty_literals` with Char literals, adjoints, Chars inside strings, unterminated quotes
using Test, PDEStudio
const P = PDEStudio
cases = [
    "Any['\"', <empty>]"            => "Any['\"', \"\"]",
    "Any['\\'', <empty>]"           => "Any['\\'', \"\"]",
    "Any['\\\\', <empty>]"          => "Any['\\\\', \"\"]",
    "Any['\\u00e9', <empty>]"       => "Any['\\u00e9', \"\"]",
    "Any['é', '\"', <empty>]"       => "Any['é', '\"', \"\"]",
    "x' * <empty>"                  => "x' * \"\"",
    "A' * <empty>"                  => "A' * \"\"",
    "[1 2]' , <empty>"              => "[1 2]' , \"\"",
    "(x)'' , <empty>"               => "(x)'' , \"\"",
    "x.' , <empty>"                 => nothing,             # (not Julia; just must not crash)
    "Any[\"it's\", <empty>]"        => "Any[\"it's\", \"\"]",
    "Any[\"a'\\\"b\", <empty>]"     => "Any[\"a'\\\"b\", \"\"]",
    "Any[', <empty>]"               => nothing,             # unterminated
    "Any[<empty>, ']"               => "Any[\"\", ']",
    "'"                             => "'",
    "Any['\"']"                     => "Any['\"']",
    "Any[1, '\"'] , \"<empty>\""     => "Any[1, '\"'] , \"<empty>\"",
    "Any[:a, '\"', <empty>]"        => "Any[:a, '\"', \"\"]",
    "Any[2'\"', <empty>]"           => nothing,
    "Any[f('\"'), <empty>]"         => "Any[f('\"'), \"\"]",
    "Any[x ? '\"' : <empty>]"       => "Any[x ? '\"' : \"\"]",
    "Any[a in '\"', <empty>]"       => "Any[a in '\"', \"\"]",   # keyword before a Char: taken as an adjoint
]
@testset "char literals" begin
    for (inp, want) in cases
        got = try P._empty_literals(inp) catch e; "THROWS $(sprint(showerror, e))" end
        ok = isnothing(want) ? !startswith(got, "THROWS") : got == want
        println(ok ? "ok   " : "FAIL ", rpad(repr(inp), 34), " -> ", repr(got))
        @test ok
    end
    # round trips through the Advanced tab text
    for v in (Any['"', ""], Any['\'', ""], Any['\\', ""], Any['é', '"', ""], Any["it's", ""], Any['"', "<empty>", ""])
        t = P._raw_text(v)
        r = P._parse_raw(t)
        println(rpad(repr(v), 34), " shown ", repr(t), " -> ", r)
        @test r == (true, v)
    end
end
