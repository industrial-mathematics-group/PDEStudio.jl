# f3ed3a2: a resolution of 1 through the whole window (time res 1: grid data, particles on a grid, references,
# statistics over time, compare over time, x-t heatmap, time slider, animation and static export; space res 1)
using Test, PDEStudio, GLMakie, StaticArrays
const P = PDEStudio
import PDEStudio: manager
PDEStudioCore.set_target_module!(@__MODULE__)
OUT = joinpath(@__DIR__, "res1_png"); mkpath(OUT)

function adv(params::ParamDict)
    N = params[:N]; x = collect(range(0.0, step = 2π / N, length = N)); t = collect(0.0:0.05:2.0)
    create_sim_data(x, [SVector(sin(xi - ti) + 2.0) for xi in x, ti in t], t, params; time_dim = :t, dims = :x)
end
exact_fac(params) = xt -> SVector(sin(xt[1] - xt[2]) + 2.0)
function parts(params::ParamDict)
    t = collect(0.0:0.1:1.0); x0 = collect(range(0.0, 2π, length = 40))
    create_sim_data([[SVector(p + ti) for p in x0] for ti in t], [[SVector(sin(p) + 2.0) for p in x0] for ti in t], t, params; time_dim = :t)
end

function click_menu!(widget, target)
    if widget isa P.StyleChoice; widget.selection[] = target; return; end
    opts = widget.options[]
    idx = findfirst(o -> (o isa Tuple ? o[2] : o) == target, opts)
    isnothing(idx) && (println("  (menu has no $target: ", [o isa Tuple ? o[2] : o for o in opts], ")"); return)
    widget.i_selected[] = idx
end
click!(b) = (manager.widgets[b].clicks[] += 1; yield())
w() = manager.widgets
status() = replace(w()[:status][], '\n' => ' ')
function axes!(x, y = :none; style = :lines_1d, u = nothing, compare = :none)
    P._choose_plot_style!(style)
    click_menu!(w()[:x_axis], x); click_menu!(w()[:y_axis], y); click_menu!(w()[:z_axis], :none)
    isnothing(u) || click_menu!(w()[:u_axis], u)
    click_menu!(w()[:compare_target], compare)
    click!(:layout_apply)
end
shot(fig, name) = (save(joinpath(OUT, name * ".png"), fig); println("  saved $name.png; status: ", status()))
tax(m) = (d = manager.plot_data[][m].data[1]; isnothing(d) ? nothing : (d isa LSimData ? d.t : d.axes[end]))

set_save_path!(mktempdir())
reset_plotter!()
set_mode!(:eulerian); set_stat_preset!("hyperbolic")
fig = launch_plotter(); display(fig)

@testset verbose = true "resolution 1" begin
@testset "grid data, time resolution 1" begin
    set_resolution!(:t, 1); set_resolution!(:t, 1; is_ref = true)
    cfg = SimulationConfig(create_param_dict(:N => 64, :sim_func_name => :adv),
                           create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                           [:num, :analytical_solution]; varied = create_varied_dict(:N => [48, 64]), reference = :exact_fac)
    set_sim_config!(cfg); click!(:run_button)
    println("status after run: ", status())
    axes!(:x)
    println("  t axes: num ", tax(:num), " ref ", tax(:analytical_solution), "; t slider range ", w()[:t].range[])
    @test tax(:num) == [2.0] && tax(:analytical_solution) == [2.0]
    shot(fig, "grid_t1_lines_x")
    axes!(:t)
    shot(fig, "grid_t1_lines_t")
    axes!(:t; u = :l2error)
    shot(fig, "grid_t1_l2error_t")
    axes!(:x, :t; style = :heatmap_flat, u = :Solution)
    shot(fig, "grid_t1_heatmap_xt")
    axes!(:x; compare = :time)
    println("  compare over time: ", length(manager.caches), " subplots")
    shot(fig, "grid_t1_compare_time")
    axes!(:x)
    click_menu!(w()[:anim_target], :t); click!(:layout_apply)
    manager.ui[:export][:animation_time] = 0.5; manager.ui[:export][:animation_FPS] = 4
    base = joinpath(mktempdir(), "anim")
    w()[:export_text].stored_string[] = base * ".mp4"; yield(); click!(:export_button)
    adir = joinpath(get_save_path(), "animations"); anims = isdir(adir) ? readdir(adir) : String[]
    println("  animation files: ", anims, "; status: ", status())
    @test any(endswith(".mp4"), anims)
    click_menu!(w()[:anim_target], :none); click!(:layout_apply)
    manager.ui[:export][:save_formats] = ["png"]
    w()[:export_text].stored_string[] = base; yield(); click!(:export_button)
    @test isfile(base * ".png")
    click!(:play_anim_button); sleep(0.5); click!(:play_anim_button)
    println("  play anim: ", status())
end

@testset "particle data, grid style and particle style, time resolution 1" begin
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :parts),
                           create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                           [:num, :analytical_solution]; reference = :exact_fac)
    set_sim_config!(cfg); click!(:run_button)
    axes!(:x)
    println("  grid style: t axes num ", tax(:num), " ref ", tax(:analytical_solution))
    @test tax(:num) == [1.0]
    shot(fig, "parts_t1_lines_x")
    axes!(:x; style = :particles_1d)
    click!(:layout_apply)
    println("  particle style: t num ", tax(:num), " ref ", tax(:analytical_solution), " status ", status())
    shot(fig, "parts_t1_particles")
end

@testset "grid data, space resolution 1" begin
    set_resolution!(:t, 50); set_resolution!(:t, 100; is_ref = true)
    set_resolution!(:x, 1); set_resolution!(:x, 1; is_ref = true)
    cfg = SimulationConfig(create_param_dict(:N => 64, :sim_func_name => :adv),
                           create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                           [:num, :analytical_solution]; reference = :exact_fac)
    set_sim_config!(cfg); click!(:run_button)
    axes!(:x; style = :lines_1d)
    d = manager.plot_data[][:num].data[1]
    println("  x axis: ", isnothing(d) ? nothing : d.axes[1], " size ", isnothing(d) ? nothing : size(d.u))
    shot(fig, "grid_x1_lines_x")
    axes!(:t)
    shot(fig, "grid_x1_lines_t")
    axes!(:x, :t; style = :heatmap_flat)
    shot(fig, "grid_x1_heatmap_xt")
    set_resolution!(:x, 100); set_resolution!(:x, 200; is_ref = true)
end
end
