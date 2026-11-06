# pre-existing: the bundled copy is missing but the original exists (it runs instead); is it a source of the loaded config?
using Test, PDEStudio
const P = PDEStudio
set_save_path!(mktempdir())
dir, out1, out2 = mktempdir(), mktempdir(), mktempdir()
write(joinpath(dir, "cfg.jl"), "ic3(x) = x\nSimulationConfig(create_param_dict(:N => 16, :ic => ic3, :sim_func_name => :advection_solver_1d), create_method_dict(:m => create_param_dict()), [:m])\n")
P.load_config_file!(joinpath(dir, "cfg.jl"))
@test P.save_params_to_csv("exp", out1, Dict("Save Type" => "test"))
rm(joinpath(out1, "exp_sources", "cfg.jl"))
reset_manager!()
P.load_and_apply_csv!(joinpath(out1, "exp.csv"))
println("ic is Function: ", P.manager.active_config.shared[:ic] isa Function, "; sources = ", P.manager.active_config.sources)
@test P.save_params_to_csv("exp2", out2, Dict("Save Type" => "test"))
println("export 2 bundled_sources: ", get(P.parse_csv_to_dict(joinpath(out2, "exp2.csv"))["Metadata"]["General"], "bundled_sources", "(none)"))
