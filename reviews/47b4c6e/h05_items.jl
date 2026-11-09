using PDEStudio
const P = @__DIR__
macro try_(ex)
    s = string(ex)
    quote
        try
            r = $(esc(ex)); println("OK   ", $s, " => ", r)
        catch e
            println("ERR  ", $s, " => ", typeof(e), ": ", first(sprint(showerror, e), 400))
        end
    end
end
studio_headless!()
set_save_path!(mktempdir())
println("=== F8 reset with only the exact method")
launch_plotter(test_advection_1d())
@try_ studio_set!(:methods => [:exact])
auto = studio_state().plots[1]; @show auto.xlims auto.ylims
@try_ studio_zoom!(4)
@try_ studio_reset_view!()
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
@try_ studio_set!(:t => 0.5)
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
println("=== F8b reset after a lims option (UI tab) — reset keeps the tab's limits?")
@try_ studio_option!(:x_axis_1d, :lims, [0.2, 0.6])
@try_ studio_zoom!(2)
@try_ studio_reset_view!()
@show studio_state().plots[1].xlims
@try_ studio_option!(:x_axis_1d, :lims, [])
@try_ studio_set!(:methods => [:exact, :upwind])
reset_plotter!()
println("=== F5 non-numeric sweep")
shared = create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind", :sim_func_name => :solve_advection_1d)
methods = create_method_dict(:fd => create_param_dict())
cfg = SimulationConfig(shared, methods, [:fd]; varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))
launch_plotter(cfg)
c = only(c for c in studio_controls() if c.name === :scheme); @show c
@show only(sl for sl in studio_state().sliders if sl.name === :scheme)
@try_ studio_set!(:scheme => "lax_wendroff")
@try_ studio_set!(:scheme => 2)
c = only(c for c in studio_controls() if c.name === :scheme); @try_ studio_set!(:scheme => c.value)
io = IOBuffer(); describe_studio(io); println(filter(l -> occursin("scheme", l), split(String(take!(io)), '\n')))
reset_plotter!()
println("=== F9 unslid parameters")
shared = create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :sim_func_name => :solve_advection_1d)
methods = create_method_dict(:exact => create_param_dict(), :upwind => create_param_dict(:scheme => "upwind"))
cfg = SimulationConfig(shared, methods, [:exact, :upwind]; varied = create_varied_dict(:cfl => [0.25, 0.5], :N => [50, 100], :c => [1.0, 2.0]),
                       reference = :exact_advection_1d)
launch_plotter(cfg)
io = IOBuffer(); describe_studio(io); txt = String(take!(io)); println(join(filter(l -> occursin("swept", l) || occursin("[slider]", l), split(txt, '\n')), "\n"))
for p in (:cfl, :N, :c); @try_ studio_set!(p => (p === :N ? 100 : p === :c ? 2.0 : 0.5)); end
@try_ studio_set!(:nope => 1)
reset_plotter!()
println("=== azimuth wrap, 3D")
launch_plotter(test_heat_2d(); style = :heatmap)
@try_ studio_set!(:plot_style => :heatmap_surface)
for i in 1:4; v = studio_rotate!(120); println(v[1].azimuth); end
@try_ studio_rotate!(-500)
@try_ studio_view!(azimuth = 725)
@show studio_state().plots[1].azimuth
@try_ studio_view!(elevation = 120)
@show studio_state().plots[1].elevation
@try_ studio_zoom!(2; dims = :z)
studio_snapshot(joinpath(P, "h05_surface.png"))
studio_reset_view!()
@show studio_state().plots[1].azimuth studio_state().plots[1].elevation
println("=== volume headless: warning")
@try_ studio_set!(:plot_style => :volume_3d, :z_axis => :t)
@show studio_state().style
f = studio_snapshot(joinpath(P, "h05_volume.png")); @show studio_state().status
@try_ studio_set!(:t => 0.0)
@show studio_state().status
@try_ studio_set!(:plot_style => :heatmap_flat, :z_axis => :none)
println("=== F6 subplot crops")
@try_ studio_set!(:compare_target => :methods, :compare_columns => 3)
s = studio_state(); @show length(s.plots)
for i in 1:length(s.plots); studio_snapshot(joinpath(P, "h05_coupled_p$i.png"); plot = i); end
studio_snapshot(joinpath(P, "h05_coupled_all.png"))
@try_ studio_set!(:compare_link => :decoupled)
for i in 1:length(s.plots); studio_snapshot(joinpath(P, "h05_decoupled_p$i.png"); plot = i); end
studio_snapshot(joinpath(P, "h05_decoupled_all.png"))
@try_ studio_set!(:compare_columns => 2)
for i in 1:length(studio_state().plots); studio_snapshot(joinpath(P, "h05_decoupled2col_p$i.png"); plot = i); end
studio_snapshot(joinpath(P, "h05_decoupled2col_all.png"))
@try_ studio_set!(:plot_style => :heatmap_surface)
for i in 1:length(studio_state().plots); studio_snapshot(joinpath(P, "h05_surf2col_p$i.png"); plot = i); end
studio_snapshot(joinpath(P, "h05_surf2col_all.png"))
reset_plotter!()
println("=== 1D compare with legends")
launch_plotter(test_advection_1d())
@try_ studio_set!(:compare_target => :cfl, :compare_columns => 2)
@show length(studio_state().plots)
for i in 1:length(studio_state().plots); studio_snapshot(joinpath(P, "h05_1d_p$i.png"); plot = i); end
studio_snapshot(joinpath(P, "h05_1d_all.png"))
@try_ studio_set!(:compare_link => :decoupled)
for i in 1:length(studio_state().plots); studio_snapshot(joinpath(P, "h05_1d_dec_p$i.png"); plot = i); end
studio_snapshot(joinpath(P, "h05_1d_dec_all.png"))
