# GUI probes (GLMakie on Xvfb): invalid style values from a CSV, stale pending slider positions
using PDEStudio, GLMakie, Test, StaticArrays
import PDEStudio: manager, menu_opt
PDEStudioCore.set_target_module!(Main)
include(joinpath(@__DIR__, "solvers.jl"))
set_stat_preset!("hyperbolic"); set_save_path!(mktempdir()); reset_manager!(); set_mode!(:eulerian)
GLMakie.activate!()
function click_menu!(widget, target_sym)
    if widget isa PDEStudio.StyleChoice; widget.selection[] = target_sym; return; end
    options = widget.options[]
    idx = findfirst(opt -> (opt isa Tuple ? opt[2] : opt) == target_sym, options)
    if isnothing(idx); push!(options, menu_opt(target_sym)); widget.options[] = options; idx = length(options); end
    widget.i_selected[] = idx
end
click_button!(b) = (manager.widgets[b].clicks[] += 1; yield())
function set_axes_for_dim!(dim)
    click_menu!(manager.widgets[:x_axis], :x)
    click_menu!(manager.widgets[:y_axis], dim == 2 ? :t : :none)
    click_menu!(manager.widgets[:z_axis], :none)
    click_button!(:layout_apply)
end
fig = launch_plotter(); display(fig)
cfg = SimulationConfig(create_param_dict(:cfl => 0.5, :N => 40, :sim_func_name => :advection_solver_1d),
                       create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                          :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
                       [:upwind, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.2, 0.4, 0.5]))
set_sim_config!(cfg); click_button!(:run_button)
click_menu!(manager.widgets[:plot_style], :lines_1d); set_axes_for_dim!(1)

which = get(ENV, "PROBE", "all")
if which in ("all", "style")
@testset "CSV with style values the renderer can't draw" begin
    for (key, val) in (("color_range", "[1.0]"), ("colors", "Any[]"), ("line_styles", "Any[]"))
        dir = mktempdir(); path = joinpath(dir, "bad.csv")
        write(path, "Category,Scope,Parameter,Value\nUI,plot_style,$key,\"$val\"\n")
        err = try
            PDEStudio.load_and_apply_csv!(path)
            click_button!(:layout_apply)
            click_button!(:plot_button)
            nothing
        catch e
            e
        end
        println("  $key = $val: stored ", repr(manager.ui[:plot_style][Symbol(key)]), "; ",
                isnothing(err) ? "no exception" : "exception: " * first(sprint(showerror, err), 200))
        @test isnothing(err)
        @test PDEStudio._valid_ui_value(Symbol(key), manager.ui[:plot_style][Symbol(key)])
        set_plot_preset!(); click_button!(:layout_apply)
    end
end
end

if which in ("all", "pending")
@testset "stale pending slider position" begin
    set_plot_preset!(); click_menu!(manager.widgets[:plot_style], :lines_1d); set_axes_for_dim!(1)
    # a file whose time position is outside the data's time range (hand-edited, or data run to a shorter time)
    dir = mktempdir(); path = joinpath(dir, "t.csv")
    write(path, "Category,Scope,Parameter,Value\nScene,Plot,t,5.0\n")
    PDEStudio.load_and_apply_csv!(path); yield()
    @show manager.pending_sliders
    tsl = manager.widgets[:t]
    # the user moves the time slider afterwards and keeps working
    set_close_to!(tsl, 0.5); yield()
    @show tsl.value[]
    # ... then runs a configuration with another final time (new time range)
    other = deepcopy(cfg); other.shared[:N] = 50
    set_sim_config!(other); click_button!(:run_button); yield()
    @show tsl.value[] last(tsl.range[]) manager.pending_sliders
    @test abs(tsl.value[] - 0.5) < 0.05        # the user's position, not the stale file value
end
end
