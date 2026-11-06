# Shared setup for the ps-a probes: the solver of test/runtests.jl and a few helpers (run from the repo root,
# --project=test, DISPLAY=:99).
using PDEStudio, GLMakie, Test, StaticArrays
import PDEStudio: manager, show_tab!, show_editor_page!
PDEStudioCore.set_target_module!(@__MODULE__)

function advection_solver_1d(params::ParamDict)
    N = params[:N]; scheme = get(params, :scheme, "upwind"); cfl = get(params, :cfl, 0.5)
    dx = 2π / N; dt = cfl * dx; Nt = ceil(Int, 2.0 / dt) + 1
    x = collect(range(0.0, step = dx, length = N)); t = collect(range(0.0, step = dt, length = Nt))
    u = fill(SVector{1, Float64}(0.0), N, Nt)
    for i in 1:N; u[i, 1] = SVector(sin(x[i]) + 2.0); end
    for n in 1:Nt-1, i in 1:N
        im1 = i == 1 ? N : i - 1; ip1 = i == N ? 1 : i + 1
        v = scheme == "upwind" ? u[i, n][1] - cfl * (u[i, n][1] - u[im1, n][1]) :
            0.5 * (u[ip1, n][1] + u[im1, n][1]) - 0.5 * cfl * (u[ip1, n][1] - u[im1, n][1])
        u[i, n+1] = SVector(v)
    end
    return create_sim_data(x, u, t, params; time_dim = :t, dims = :x)
end

click_button!(k) = (manager.widgets[k].clicks[] += 1; yield())
function editor_row(key)
    i = findfirst(isequal(key), manager.editor_row_keys)
    isnothing(i) && error("no row for $(repr(key)) (rows: $(manager.editor_row_keys))")
    w = manager.widgets
    return (text = w[Symbol("editor_row_", i, "_text")], button = w[Symbol("editor_row_", i, "_button")])
end
type_into!(key, s) = (editor_row(key).text.stored_string[] = s; yield())
status() = replace(manager.widgets[:status][], '\n' => ' ')
function press_preset!(name, which)
    i = findfirst(isequal(name), manager.editor_row_keys)
    isnothing(i) && error("no preset $(repr(name)) (presets: $(manager.editor_row_keys))")
    manager.widgets[Symbol("method_row_", i, "_", which)].clicks[] += 1
    yield()
end

function open_studio(; varied = create_varied_dict(:cfl => [0.2, 0.5]), methods = [:upwind])
    set_stat_preset!("hyperbolic")
    set_save_path!(mktempdir())
    reset_plotter!()
    set_mode!(:eulerian)
    GLMakie.activate!()
    fig = launch_plotter()
    display(fig)
    shared = create_param_dict(:cfl => 0.5, :N => 20, :sim_func_name => :advection_solver_1d)
    ms = create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                            :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs"))
    set_sim_config!(SimulationConfig(shared, ms, methods; varied = varied))
    click_button!(:run_button)
    return fig
end
