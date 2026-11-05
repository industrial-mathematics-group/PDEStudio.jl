# Probe: render pipeline (window on the Xvfb display). Run from the repo root:
#   DISPLAY=:99 julia -t 4 --project=test <scratch>/probe_gui.jl
using PDEStudio, GLMakie, Test, StaticArrays
import PDEStudio: manager, menu_opt
const S = @__DIR__

PDEStudioCore.set_target_module!(@__MODULE__)

function advection_solver_1d(params::ParamDict)
    N = params[:N]; scheme = get(params, :scheme, "upwind"); cfl = get(params, :cfl, 0.5)
    L = 2π; dx = L / N; dt = cfl * dx; T_end = 2.0; Nt = ceil(Int, T_end / dt) + 1
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
exact_advection_factory(params) = st -> SVector{1, Float64}(sin(st[1] - st[2]) + 2.0)

function click_menu!(widget, target_sym)
    if widget isa PDEStudio.StyleChoice
        widget.selection[] = target_sym; return
    end
    options = widget.options[]
    idx = findfirst(opt -> (opt isa Tuple ? opt[2] : opt) == target_sym, options)
    if isnothing(idx)
        push!(options, menu_opt(target_sym)); widget.options[] = options; idx = length(options)
    end
    widget.i_selected[] = idx
end
click_button!(b) = (manager.widgets[b].clicks[] += 1; yield())
axes_of(fig) = [c for c in fig.content if c isa Axis || c isa Axis3]

set_stat_preset!("hyperbolic")
set_save_path!(mktempdir())
reset_manager!()
GLMakie.activate!()

config = SimulationConfig(create_param_dict(:cfl => 0.5, :N => 40, :sim_func_name => :advection_solver_1d),
    create_method_dict(:analytical_solution => create_param_dict(), :upwind => create_param_dict(:scheme => "upwind"),
                       :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
    [:upwind, :lax_friedrichs, :analytical_solution]; varied = create_varied_dict(:cfl => [0.2, 0.4, 0.5]),
    reference = :exact_advection_factory)

fig = launch_plotter(); display(fig)
set_sim_config!(config); force_simulation()

