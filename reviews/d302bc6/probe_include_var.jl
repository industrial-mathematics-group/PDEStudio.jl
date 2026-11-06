# d302bc6: a configuration that uses a variable / keyword named `include`, exported and reloaded with NOTHING edited.
# (`_redirect_includes` replaces every bare `include` symbol while `copies` is non-empty, which at the load is the case
# for every export that records its originals.)
using Test, PDEStudio
const P = PDEStudio
include(joinpath(@__DIR__, "old", "solver.jl"))
set_save_path!(mktempdir())
A = mktempdir(); E = mktempdir()
write(joinpath(A, "cfg.jl"), """
    # e.g. an option of a helper function
    resolution(; include_boundary::Bool = true, include::Bool = include_boundary) = include ? 21 : 20
    SimulationConfig(create_param_dict(:N => resolution(), :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m])
    """)
reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl"))
println(".jl load: N = ", P.manager.active_config.shared[:N])
P.save_params_to_csv("exp", E, Dict("Save Type" => "test"))
reset_manager!(); P.load_and_apply_csv!(joinpath(E, "exp.csv"))
println("export load (nothing edited): failures = ", P.manager.source_failures, ", note = ", repr(P.manager.source_note))
println("   N = ", P.manager.active_config.shared[:N], " (from the CSV if the source failed)")
r = try P._run_simulations(P.manager.active_config); "ok" catch e; "FAILS " * sprint(showerror, e)[1:min(end, 100)] end
println("Run: ", r, "   resolution() now = ", try Base.invokelatest(Main.resolution) catch e; sprint(showerror, e)[1:min(end, 80)] end)
