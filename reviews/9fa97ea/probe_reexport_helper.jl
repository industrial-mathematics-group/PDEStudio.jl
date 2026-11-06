# 40e6813: an included helper edited after the first export. The bundled config copy runs as its original, so its
# relative `include("helper.jl")` runs the (edited) original helper after the bundled helper copy.
using Test, PDEStudio
const P = PDEStudio
set_save_path!(mktempdir())
root = mktempdir(); orig = joinpath(root, "orig"); mkpath(orig)
out1, out2 = mktempdir(), mktempdir()
write(joinpath(orig, "helper.jl"), "helper_N() = 24\n")
write(joinpath(orig, "config.jl"), """
    include("helper.jl")
    SimulationConfig(create_param_dict(:N => helper_N(), :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m]; sources = [joinpath(@__DIR__, "helper.jl")])
    """)
P.load_config_file!(joinpath(orig, "config.jl"))
@test P.save_params_to_csv("exp", out1, Dict("Save Type" => "test"))
write(joinpath(orig, "helper.jl"), "helper_N() = 25\n")      # edited after the export
reset_manager!()
P.load_and_apply_csv!(joinpath(out1, "exp.csv"))
ran = P.manager.active_config.shared[:N]
println("loaded export 1: N = $ran; sources = ", P.manager.active_config.sources)
@test P.save_params_to_csv("exp2", out2, Dict("Save Type" => "test"))
rows = P.parse_csv_to_dict(joinpath(out2, "exp2.csv"))
println("export 2 records N = ", rows["Simulation"]["Shared"]["N"], "; bundled helper.jl: ", strip(read(joinpath(out2, "exp2_sources", "helper.jl"), String)))
rm(orig; recursive = true)
reset_manager!()
P.load_and_apply_csv!(joinpath(out2, "exp2.csv"))
println("export 2 on its own (originals gone): N = ", P.manager.active_config.shared[:N], ", failures = ", P.manager.source_failures)
@test P.manager.active_config.shared[:N] == ran
