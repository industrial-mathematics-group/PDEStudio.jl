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

@testset "GUI probes" begin
@testset "lines_1d shows the data of the selected slider values" begin
    click_menu!(manager.widgets[:plot_style], :lines_1d)
    click_menu!(manager.widgets[:x_axis], :x); click_menu!(manager.widgets[:y_axis], :none); click_menu!(manager.widgets[:z_axis], :none)
    click_button!(:layout_apply)
    set_close_to!(manager.widgets[manager.reverse_map[:cfl]], 0.4); yield()
    set_close_to!(manager.widgets[:t], 1.0); yield()
    tsel = manager.widgets[:t].value[]
    c = manager.caches[1][:upwind]
    params = assemble_params(config.shared, config.methods, :upwind); params[:cfl] = 0.4
    d = load_sim_data(params, Val(:eulerian), PDEStudio.build_res_tuple((:x, :t)))
    ti = findmin(v -> abs(v - tsel), d.axes[2])[2]
    expected = [s[1] for s in d.stats[:Solution][:, ti]]
    @test length(c.obs_u[]) == length(expected)
    @test maximum(abs.(c.obs_u[] .- expected)) < 1e-12
    println("lines_1d max diff vs. direct load: ", maximum(abs.(c.obs_u[] .- expected)), " (t slider ", tsel, ", data t ", d.axes[2][ti], ")")
    save(joinpath(S, "lines_1d.png"), fig)
end

@testset "Reference lines: listeners on finallimits per UI update" begin
    manager.ui[:plot_style][:reference] = Any[-1.0]
    ax = first(axes_of(fig))
    n0 = length(ax.finallimits.listeners)
    for _ in 1:20
        manager.triggers[:UI][] += 1; yield()
    end
    n1 = length(ax.finallimits.listeners)
    nref = count(p -> haskey(p, :label) && p.label[] == "Reference Lines", ax.scene.plots)
    println("finallimits listeners: before $n0, after 20 UI updates $n1; reference line plots on the axis: $nref")
    @test n1 - n0 < 5
    manager.ui[:plot_style][:reference] = Any[]
end

@testset "contour_3d keeps its colormap after the UI step" begin
    click_menu!(manager.widgets[:plot_style], :contour_3d)
    click_menu!(manager.widgets[:x_axis], :x); click_menu!(manager.widgets[:y_axis], :t); click_menu!(manager.widgets[:z_axis], :cfl)
    click_button!(:layout_apply)
    m = only(keys(manager.caches[1]))
    prim = manager.caches[1][m].primitives[:contour_3d]
    col = prim.color[]
    println("contour_3d color attribute after UI step: ", repr(col), " (method $m)")
    @test isnothing(col) || col isa AbstractVector
    save(joinpath(S, "contour_3d.png"), fig)
end

@testset "heatmap: u matrix matches the axes" begin
    click_menu!(manager.widgets[:plot_style], :heatmap_flat)
    click_menu!(manager.widgets[:x_axis], :x); click_menu!(manager.widgets[:y_axis], :t); click_menu!(manager.widgets[:z_axis], :none)
    click_button!(:layout_apply)
    m = only(keys(manager.caches[1]))
    c = manager.caches[1][m]
    @test size(c.obs_u[]) == (length(c.obs_x[]), length(c.obs_y[]))
    println("heatmap method drawn: $m; size u $(size(c.obs_u[])), x $(length(c.obs_x[])), t $(length(c.obs_y[]))")
    # Move the cfl slider: dt changes, so the time axis length changes
    n_before = length(c.obs_y[])
    set_close_to!(manager.widgets[manager.reverse_map[:cfl]], 0.2); yield()
    c = manager.caches[1][m]
    println("after cfl 0.2: size u $(size(c.obs_u[])), x $(length(c.obs_x[])), t $(length(c.obs_y[])) (before $n_before)")
    @test size(c.obs_u[]) == (length(c.obs_x[]), length(c.obs_y[]))
    save(joinpath(S, "heatmap.png"), fig)
end

@testset "Stat over parameter (substitute axis)" begin
    click_menu!(manager.widgets[:plot_style], :lines_1d)
    opts = [o isa Tuple ? o[2] : o for o in manager.widgets[:x_axis].options[]]
    println("x axis options (1D): ", opts)
    click_menu!(manager.widgets[:x_axis], :t); click_menu!(manager.widgets[:u_axis], :l2error)
    click_button!(:layout_apply)
    c = manager.caches[1][:upwind]
    params = assemble_params(config.shared, config.methods, :upwind); params[:cfl] = manager.widgets[manager.reverse_map[:cfl]].value[]
    d = load_sim_data(params, Val(:eulerian), PDEStudio.build_res_tuple((:x, :t)))
    exp = [v[1] for v in d.stats[:l2error]]
    println("l2error over t: drawn ", length(c.obs_u[]), " values, data ", length(exp), "; max diff ",
            length(exp) == length(c.obs_u[]) ? maximum(abs.(c.obs_u[] .- exp)) : NaN)
    @test length(c.obs_u[]) == length(exp)
    save(joinpath(S, "l2error_t.png"), fig)
end

end
reset_plotter!()
