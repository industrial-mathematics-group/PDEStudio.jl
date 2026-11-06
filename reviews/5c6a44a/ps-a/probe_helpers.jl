# Probes of UI helpers that need no window
using PDEStudio, Test
const P = PDEStudio

@testset "helper probes" begin
@testset "probe: status line wrapping with non-ASCII text" begin
    n = P.STATUS_LINE_CHARS
    # ASCII: the first line ends at a space, within n characters
    a = repeat("word ", 30)
    @test length(first(split(P._wrap_status(a), '\n'))) <= n
    # a realistic status message: a change message (→) of a long text value
    msg = "Shared → description = Größere Auflösung für die Dämpfungsstudie mit Überschall-Strömungen und Rändern"
    lines = split(P._wrap_status(msg), '\n')
    @show msg lines length.(lines)
    @test length(lines[1]) <= n                       # FAILS: byte index used as character count
    @test startswith(msg, lines[1] * " ")             # FAILS: line 1 doesn't end at a word boundary
    msg2 = "Geschwindigkeit · Dämpfung → Größe ▲▼ " ^ 4
    lines2 = split(P._wrap_status(msg2), '\n')
    @show lines2 length.(lines2)
    @test length(lines2[1]) <= n
end

@testset "probe: raw / typed values" begin
    @test P._parse_raw("\"abc") == (true, "abc")     # unbalanced quote accepted as text (lenient)
    @test P._parse_raw("abc")[1] == false
    @test P._raw_text("") == "<empty>"
    @test P._parse_raw(P._raw_text(""))[1]           # what the raw editor shows for "" can be re-applied?
    @test P._typed_value(:Bool, "1") === true
    @test_throws ArgumentError P._typed_value(Symbol("Vector{Int}"), "[1.5]")
    @test P._typed_value(:Tuple, "[1, 2]") == (1, 2)
    @test P._typed_value(:Symbol, "\":a\"") === :a
end
end
