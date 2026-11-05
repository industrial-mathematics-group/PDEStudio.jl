# e7c1088: which code does a re-export bundle when the original changed after the first export?
using Test, PDEStudio
@testset "re-export bundles the code that ran" begin
    set_save_path!(mktempdir())
    dir, out1, out2 = mktempdir(), mktempdir(), mktempdir()
    src = joinpath(dir, "cfg.jl")
    write(src, "ic_v(x) = x\nSimulationConfig(create_param_dict(:N => 16, :version => 1, :ic => ic_v, :sim_func_name => :advection_solver_1d), create_method_dict(:m => create_param_dict()), [:m])\n")
    PDEStudio.load_config_file!(src)
    @test PDEStudio.save_params_to_csv("exp", out1, Dict("Save Type" => "test"))
    # the user edits the original afterwards
    write(src, replace(read(src, String), ":version => 1" => ":version => 2"))
    reset_manager!()
    PDEStudio.load_and_apply_csv!(joinpath(out1, "exp.csv"))
    ran = PDEStudio.manager.active_config.shared[:version]
    println("loaded export 1: version = $ran, sources = ", PDEStudio.manager.active_config.sources)
    @test PDEStudio.save_params_to_csv("exp2", out2, Dict("Save Type" => "test"))
    bundled = read(joinpath(out2, "exp2_sources", "cfg.jl"), String)
    rows = PDEStudio.parse_csv_to_dict(joinpath(out2, "exp2.csv"))
    println("export 2 records version = ", rows["Simulation"]["Shared"]["version"], "; bundled cfg.jl has ", match(r":version => \d", bundled).match)
    @test occursin(":version => $ran", bundled)
end
