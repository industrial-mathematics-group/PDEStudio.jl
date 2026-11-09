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
println("=== 1. zoom dims=:z on a 2D plot")
launch_plotter(test_advection_1d())
@show studio_state().camera_locked
@try_ studio_zoom!(2; dims = :z)
@show studio_state().camera_locked studio_state().status.text
@try_ studio_reset_view!()
println("=== 2. reset after zoom, default methods (heatmap of x,t)")
@try_ studio_set!(:plot_style => :heatmap, :y_axis => :t)
auto = studio_state().plots[1]; @show auto.xlims auto.ylims
@try_ studio_zoom!(3)
@try_ studio_reset_view!()
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
@try_ studio_set!(:plot_style => :lines_1d, :x_axis => :x)
auto = studio_state().plots[1]; @show auto.xlims auto.ylims
println("=== 3. only the exact method")
@try_ studio_set!(:methods => [:exact])
auto = studio_state().plots[1]; @show auto.xlims auto.ylims
@try_ studio_zoom!(4)
@try_ studio_reset_view!()
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
println("--- t change after reset (exact only)")
@try_ studio_set!(:t => 0.5)
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
println("=== 4. two methods, unlock via button")
@try_ studio_set!(:methods => [:exact, :upwind])
auto = studio_state().plots[1]; @show auto.xlims auto.ylims
@try_ studio_zoom!(4)
@try_ studio_press!(:lock_camera)
@try_ studio_set!(:t => 0.25)
@show studio_state().plots[1].xlims studio_state().plots[1].ylims studio_state().camera_locked
@try_ studio_reset_view!()
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
println("=== 5. option types")
@try_ studio_option!(:y_axis_1d, :log_scale, "yes")
@show studio_state().status
@try_ studio_option!(:y_axis_1d, :log_scale, false)
@try_ studio_option!(:y_axis_1d, :padding, "a")
@show studio_state().status
@try_ studio_option!(:y_axis_1d, :padding, 0.05)
@try_ studio_option!(:plot_style, :line_width, :thick)
@show studio_state().status
@try_ studio_options(:plot_style)
