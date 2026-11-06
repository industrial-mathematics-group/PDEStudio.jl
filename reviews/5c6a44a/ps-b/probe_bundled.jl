# Probe: a .jl config ending with a function, exported to CSV and loaded back (no window).
#   julia -t 2 --project=test <scratch>/probe_bundled.jl
using PDEStudio, Test
const P = PDEStudio
PDEStudioCore.set_target_module!(@__MODULE__)
set_save_path!(mktempdir())
@testset "bundled config file ending with a function" begin
    P.load_config_file!(joinpath(@__DIR__, "cfgsrc", "myconfig.jl"))
    @test manager_ic = P.manager.active_config.shared[:ic] isa Function
    dir = mktempdir()
    @test P.save_params_to_csv("exp", dir, Dict("Save Type" => "probe"))
    P.reset_manager!()
    P.load_and_apply_csv!(joinpath(dir, "exp.csv"))
    ic = P.manager.active_config.shared[:ic]
    println("after CSV reload: shared[:ic] = ", repr(ic), " :: ", typeof(ic))
    println("source failures: ", P.manager.source_failures, "; sources: ", P.manager.active_config.sources)
    @test ic isa Function
end
@testset "docstrings" begin
    d = string(@doc PDEStudio.get_colorrange)
    println("get_colorrange doc starts: ", first(d, 120))
    @test occursin("color range", lowercase(d))
end
