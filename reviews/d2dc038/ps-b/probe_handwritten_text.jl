# Probe: text values of a hand-written CSV with spaces after the commas (labels, UI text options)
using PDEStudio, Test
PDEStudioCore.set_target_module!(Main)
set_save_path!(mktempdir()); reset_manager!()
p = joinpath(mktempdir(), "h.csv")
write(p, "Category, Scope, Parameter, Value\nScene, Labels, upwind, Upwind scheme\nUI, labels, title, My title\n")
PDEStudio.load_and_apply_csv!(p)
@testset "hand-written text values" begin
    @show PDEStudio.manager.labels[:upwind] PDEStudio.manager.ui[:labels][:title]
    @test PDEStudio.manager.labels[:upwind] == "Upwind scheme"
    @test PDEStudio.manager.ui[:labels][:title] == "My title"
end
