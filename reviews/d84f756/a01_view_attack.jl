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
const m = PDEStudio.manager
st() = (s = studio_state(); (locked = s.camera_locked, xl = s.plots[1].xlims, yl = s.plots[1].ylims,
        api = PDEStudio._api_view_locked(), ctx = !isnothing(m.view_context), status = s.status))
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
auto = studio_state().plots[1]; @show auto.xlims auto.ylims

println("--- 1: zoom, set_plot_preset!() (UI reset), then a slider move")
studio_zoom!(4; center = (0.3, 0.5)); @show st()
@try_ set_plot_preset!()
@show st()
@try_ studio_set!(:t => 0.5)
@show st()
studio_reset_view!()

println("--- 2: zoom, save CSV (with camera), reset, load it: a loaded camera is the user's")
dir = mktempdir()
studio_zoom!(4; center = (0.3, 0.5))
PDEStudio.save_params_to_csv("cam", dir, Dict{String, Any}())
studio_reset_view!()
@try_ PDEStudio.load_and_apply_csv!(joinpath(dir, "cam.csv"))
@show st()
@try_ studio_set!(:x_axis => :t)
@show st()
studio_reset_view!(); studio_set!(:x_axis => :x)

println("--- 3: zoom, then load a CSV without a camera (saved unlocked)")
PDEStudio.save_params_to_csv("nocam", dir, Dict{String, Any}())
studio_zoom!(4; center = (0.3, 0.5))
@try_ PDEStudio.load_and_apply_csv!(joinpath(dir, "nocam.csv"))
@show st()
println("    … then Lock Camera, then a style change (the person's lock stays)")
studio_press!(:lock_camera); @show st()
@try_ studio_set!(:plot_style => :scatter_1d); @show st()
studio_set!(:plot_style => :lines_1d); studio_reset_view!()

println("--- 4: zoom, save visual preset, reset, apply it; built-in preset while API-locked")
studio_zoom!(4; center = (0.3, 0.5))
save_plot_preset(:mine)
studio_reset_view!()
@try_ set_plot_preset!(:mine); @show st()
studio_reset_view!()
studio_zoom!(4; center = (0.3, 0.5))
@try_ set_plot_preset!(:publication); @show st()
@try_ studio_set!(:x_axis => :t); @show st()
studio_reset_view!(); studio_set!(:x_axis => :x)
set_plot_preset!()

println("--- 5: a zoom between a pending change (apply = false) and its press")
@try_ studio_set!(:x_axis => :t; apply = false)
studio_zoom!(4; center = (0.3, 0.5)); @show st()
@try_ studio_press!(:update_plot)
@show st()
studio_snapshot(joinpath(P, "a01_5_pending_zoom.png"))
studio_reset_view!(); studio_set!(:x_axis => :x)

println("--- 6: Lock Camera first, then an API zoom, then a style change (whose lock?)")
studio_press!(:lock_camera); @show st()
studio_zoom!(2); @show st()
@try_ studio_set!(:plot_style => :scatter_1d); @show st()
studio_set!(:plot_style => :lines_1d); studio_reset_view!()

println("--- 7: style change pending (apply = false), then Update Plot (the wrong button) releases?")
studio_zoom!(4; center = (0.3, 0.5))
@try_ studio_set!(:plot_style => :scatter_1d; apply = false)
@show m.flags[:Layout][] m.flags[:Plot][]
@try_ studio_press!(:update_plot)
@show st() m.active_plot_type
@try_ studio_press!(:apply_layout); @show st() m.active_plot_type
studio_set!(:plot_style => :lines_1d); studio_reset_view!()

println("--- 8: reset_plotter! and relaunch after an API zoom")
studio_zoom!(4; center = (0.3, 0.5))
reset_plotter!()
@show m.view_context m.camera_locked[]
launch_plotter(test_advection_1d())
@show st()
println("END")
