using PDEStudio, GLMakie
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
sc = ARGS[1]
set_save_path!(mktempdir())
scrinfo(fig) = (s = Makie.getscreen(fig.scene); isnothing(s) ? nothing : (id = objectid(s), open = isopen(s), ppu = s.px_per_unit[], fb = size(Makie.colorbuffer(s)), vis = s.config.visible))
if sc == "gl"
    GLMakie.activate!()
    fig = launch_plotter(test_heat_2d(); style = :heatmap)
    display(fig)
    @show studio_state().backend studio_state().window_size
    i0 = scrinfo(fig); @show i0
    for st in (:heatmap_surface, :contour_surface, :lines_3d)
        @try_ studio_set!(:plot_style => st)
        @try_ studio_snapshot(joinpath(P, "g01_gl_$st.png"))
        @show studio_state().status
    end
    @try_ studio_rotate!(60, 10)
    @try_ studio_snapshot(joinpath(P, "g01_gl_surface_rot_ppu2.png"); px_per_unit = 2)
    @show scrinfo(fig)
    @try_ studio_snapshot(joinpath(P, "g01_gl_window.png"); area = :window)
    @try_ studio_snapshot(joinpath(P, "g01_gl_window_ppu2.png"); area = :window, px_per_unit = 2)
    @show scrinfo(fig)
    save(joinpath(P, "g01_gl_native_after.png"), fig)
    @try_ studio_set!(:plot_style => :volume_3d)
    @show studio_state().style studio_state().axes
    @try_ studio_snapshot(joinpath(P, "g01_gl_volume.png"))
    @show studio_state().status
    @try_ studio_set!(:compare_target => :methods)
    @try_ studio_snapshot(joinpath(P, "g01_gl_volume_p2.png"); plot = 2)
    @try_ studio_set!(:compare_target => :none, :plot_style => :heatmap_flat)
    @try_ studio_snapshot(joinpath(P, "g01_gl_flat.png"))
    @show scrinfo(fig) studio_state().window_size
    println("--- now studio_headless!() while the GLMakie window is open")
    studio_headless!()
    @try_ studio_set!(:plot_style => :heatmap_surface)
    @try_ studio_snapshot(joinpath(P, "g01_gl_then_cairo_surface.png"))
    @show studio_state().backend
elseif sc == "notshown"
    GLMakie.activate!()
    fig = launch_plotter(test_heat_2d(); style = :heatmap_surface)   # never displayed
    @show Makie.getscreen(fig.scene)
    @try_ studio_snapshot(joinpath(P, "g01_notshown_surface.png"))
    @show scrinfo(fig)
    @try_ studio_snapshot(joinpath(P, "g01_notshown_window.png"); area = :window)
elseif sc == "wgl_then_gl"
    using WGLMakie
    WGLMakie.activate!()
    fig = launch_plotter(test_heat_2d(); style = :heatmap_surface)
    @show studio_state().backend
    @try_ studio_snapshot(joinpath(P, "g01_wgl_surface.png"))
    GLMakie.activate!()
    @show studio_state().backend
    @try_ studio_snapshot(joinpath(P, "g01_wgl_then_gl_surface.png"))
    @show Makie.getscreen(fig.scene)
    @try_ studio_set!(:t => 0.02)
    @try_ studio_snapshot(joinpath(P, "g01_wgl_then_gl_surface2.png"))
elseif sc == "gl_then_wgl"
    using WGLMakie
    GLMakie.activate!()
    fig = launch_plotter(test_heat_2d(); style = :heatmap_surface)
    display(fig)
    WGLMakie.activate!()
    @show studio_state().backend
    @try_ studio_snapshot(joinpath(P, "g01_gl_then_wgl_surface.png"))
    @try_ studio_set!(:plot_style => :heatmap_flat)
    @try_ studio_snapshot(joinpath(P, "g01_gl_then_wgl_flat.png"))
end
println("END")
