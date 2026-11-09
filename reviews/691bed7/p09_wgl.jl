using PDEStudio, WGLMakie
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
WGLMakie.activate!()
set_save_path!(mktempdir())
fig = launch_plotter(test_heat_2d(); style = :heatmap_surface)
@try_ studio_state().backend
@try_ studio_zoom!(2)
@try_ studio_rotate!(30)
@try_ studio_snapshot(joinpath(P, "p09_wgl_surface.png"))
@try_ studio_set!(:plot_style => :heatmap_flat)
@try_ studio_snapshot(joinpath(P, "p09_wgl_flat.png"))
println("--- particles reset vs automatic")
reset_plotter!()
studio_headless!()
launch_plotter(test_particles_2d())
@try_ studio_set!(:t => 1.0)
a = studio_state().plots[1]; @show a.xlims a.ylims
@try_ studio_zoom!(3)
@try_ studio_reset_view!()
b = studio_state().plots[1]; @show b.xlims b.ylims
println("--- status truncation")
@try_ studio_set!(:methods => [:euler, :rk2, :rk4], :plot_style => :particles_2d, :compare_target => :methods, :compare_columns => 3, :legend_base => :top)
@show studio_state().status
println("--- animation")
PDEStudio.manager.widgets[:play_anim_button].clicks[] += 1
@show PDEStudio.manager.is_animating[]
@try_ studio_zoom!(2)
for i in 1:3; sleep(0.3); yield(); end
@try_ studio_state().plots[1].xlims
@try_ studio_state().sliders
@try_ studio_snapshot(joinpath(P, "p09_anim.png"))
PDEStudio.manager.widgets[:play_anim_button].clicks[] += 1
@show PDEStudio.manager.is_animating[]
@try_ studio_reset_view!()
