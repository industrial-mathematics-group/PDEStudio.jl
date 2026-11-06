# 464d59c: `old isa AbstractVector && val isa AbstractVector && return true` -- which typos does it let through?
using Test, PDEStudio
old = [0.1, 0.2]
target = Dict(:v => old)
for s in ("[abc, 1]", "[0.1, 0.2x]", "[0.1 0.2]", "[0.1, \"a\"]", "Float64[0.1, abc]", "[0.1, 0.2", "[a, b]", "[:a, \"b\"]", "String[<empty>, \"a\"]")
    val = PDEStudio._parse_editor_input(s, old)
    ok = PDEStudio._valid_editor_value(s, target, :v, val)
    println(rpad(s, 22), " -> ", repr(val), "  accepted = ", ok)
end
@testset "char containing a quote before <empty>" begin
    v = Any['"', ""]
    shown = PDEStudio._raw_text(v)
    println("raw text of Any['\"', \"\"]: ", shown, " -> ", PDEStudio._parse_raw(shown))
    @test PDEStudio._parse_raw(shown) == (true, v)
end
