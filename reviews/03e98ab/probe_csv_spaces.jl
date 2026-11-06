# Round trip of texts with surrounding spaces through the studio's own CSV writer (ede04c2)
using Test, PDEStudio
const CSV = PDEStudio.CSV
p = joinpath(mktempdir(), "w.csv")
CSV.write(p, PDEStudio.DataFrame(Category=["Scene","UI"], Scope=["Labels","labels"], Parameter=["upwind","title"], Value=["  Upwind  ", " padded "]))
println("CSV.write output:\n", read(p, String))
@testset "texts with surrounding spaces round-trip through save/load" begin
    set_save_path!(mktempdir())
    reset_manager!()
    PDEStudio.set_label!(:upwind, "  Upwind  ")
    PDEStudio.manager.ui[:labels][:title] = " padded "
    dir = mktempdir()
    @test PDEStudio.save_params_to_csv("rt", dir, Dict("Save Type" => "test"))
    txt = read(joinpath(dir, "rt.csv"), String)
    for l in split(txt, '\n'); (occursin("upwind", l) || occursin(",title,", l)) && println("written: ", repr(l)); end
    reset_manager!()
    PDEStudio.load_and_apply_csv!(joinpath(dir, "rt.csv"))
    @show PDEStudio.manager.labels[:upwind] PDEStudio.manager.ui[:labels][:title]
    @test PDEStudio.manager.labels[:upwind] == "  Upwind  "
    @test PDEStudio.manager.ui[:labels][:title] == " padded "
end
