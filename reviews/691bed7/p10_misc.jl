using PDEStudio
const P = @__DIR__
macro try_(ex)
    s = string(ex)
    quote
        try
            r = $(esc(ex)); println("OK   ", $s, " => ", r)
        catch e
            println("ERR  ", $s, " => ", typeof(e), ": ", first(sprint(showerror, e), 300))
        end
    end
end
studio_headless!()
set_save_path!(mktempdir())
shared = create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :sim_func_name => :solve_advection_1d)
methods = create_method_dict(:exact => create_param_dict(), :upwind => create_param_dict(:scheme => "upwind"))
cfg = SimulationConfig(shared, methods, [:exact, :upwind]; varied = create_varied_dict(:cfl => [0.25, 0.5], :N => [50, 100], :c => [1.0, 2.0]),
                       reference = :exact_advection_1d)
launch_plotter(cfg)
s = studio_state()
@show s.config.swept [(x.name, x.value) for x in s.sliders] PDEStudio.manager.max_params
io = IOBuffer(); describe_studio(io); txt = String(take!(io)); println(join(filter(l -> occursin("swept", l) || occursin("[slider]", l), split(txt, '\n')), "\n"))
for p in (:cfl, :N, :c); @try_ studio_set!(p => (p === :N ? 100 : p === :c ? 2.0 : 0.5)); end
println("--- apply=false / pending")
@try_ studio_set!(:plot_style => :scatter_1d, :legend_base => :left, :compare_columns => 3, :plot_width => 640, :plot_height => 480; apply = false)
s = studio_state(); @show s.pending s.status
io = IOBuffer(); describe_studio(io); println(split(String(take!(io)), '\n')[1:4])
@try_ studio_press!(:apply_layout)
@show studio_state().style studio_state().pending
println("--- time compare: t slider")
@try_ studio_set!(:compare_target => :time)
@try_ studio_set!(:t => 0.5)
@try_ studio_set!(:compare_target => :none)
println("--- anim_target")
@try_ studio_set!(:anim_target => :cfl)
@try_ studio_set!(:anim_target => :q)
println("--- u_axis / component after stats")
c = only(c for c in studio_controls() if c.name === :u_axis); @show c.choices
println("--- log x on 1D (positive data via c axis?)")
@try_ studio_set!(:x_axis => :t)
@try_ studio_option!(:x_axis_1d, :log_scale, true)
@try_ studio_state().plots[1].xlims
@try_ PDEStudio._plot_axes()[1].xscale[]
@try_ studio_zoom!(2)
