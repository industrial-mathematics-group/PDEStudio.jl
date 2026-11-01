# ==============================================================================
# --- PRECOMPILE WORKLOAD ---
# ==============================================================================
# Opens the window and runs a tiny sweep while the package precompiles, so the code for the first window, simulation
# and plot is in the package image: the first `launch_plotter()` + simulation of a session takes ~18 s instead of
# ~32 s. Only Makie code (no backend), the state is reset afterwards. To skip it (e.g. while developing PDEStudio):
# `PrecompileTools.Preferences.set_preferences!(PDEStudio, "precompile_workload" => false; force = true)`.

# A small 1-D solution: u(x, t) = sin(x) + t on 8 points and 3 times
function _precompile_solver(params::ParamDict)
    x = collect(range(0.0, 1.0, length = 8))
    t = [0.0, 0.5, 1.0]
    u = [SVector{1, Float64}(sin(xi) + ti) for xi in x, ti in t]
    return create_sim_data(x, u, t, params; time_dim = :t, dims = :x)
end

@setup_workload begin
    dir = mktempdir()
    @compile_workload begin
        Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            target, save_path = get_target_module(), get_save_path()
            try
                set_target_module!(@__MODULE__)
                set_save_path!(dir)
                reset_manager!()
                launch_plotter()
                set_sim_config!(SimulationConfig(create_param_dict(:N => 8, :sim_func_name => :_precompile_solver),
                                                 create_method_dict(:a => create_param_dict(), :b => create_param_dict()),
                                                 [:a, :b]))
                force_simulation()
            finally
                reset_plotter!()
                reset_manager!()
                set_target_module!(target)
                set_save_path!(save_path)
            end
        end
    end
    rm(dir; recursive = true, force = true)
end
