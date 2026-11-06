# c8515ea: Run Simulation after loading an export whose listed helper is in a subfolder (originals unchanged)
using Test, PDEStudio, GLMakie
const P = PDEStudio
include(joinpath(@__DIR__, "solver.jl"))
set_save_path!(mktempdir())
w() = P.manager.widgets
fig = launch_plotter(); display(fig)
dir = mktempdir(); out = mktempdir(); mkpath(joinpath(dir, "lib"))
write(joinpath(dir, "lib", "h.jl"), "hN() = 20\n")
write(joinpath(dir, "cfg.jl"), """
    include("lib/h.jl")
    SimulationConfig(create_param_dict(:N => hN(), :sim_func_name => :advection_solver_1d),
                     create_method_dict(:upwind => create_param_dict()), [:upwind]; sources = [joinpath(@__DIR__, "lib", "h.jl")])
    """)
P.load_config_file!(joinpath(dir, "cfg.jl")); P.save_params_to_csv("exp", out, Dict("Save Type" => "test"))
P._handle_load(joinpath(out, "exp.csv"))
println("load: N = ", P.manager.active_config.shared[:N], " failures = ", P.manager.source_failures)
err = try w()[:run_button].clicks[] += 1; yield(); "" catch e; sprint(showerror, e isa LoadError ? e.error : e)[1:min(end, 120)] end
println("Run: ", isempty(err) ? "ok: " * replace(w()[:status][], '\n' => ' ') : "THROWS " * err)
@test isempty(err)
