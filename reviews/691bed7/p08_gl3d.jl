using PDEStudio, GLMakie
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
GLMakie.activate!()
set_save_path!(mktempdir())
style = Symbol(ARGS[1])
fig = launch_plotter(test_heat_2d(); style = style)
display(fig)
@show studio_state().style studio_state().window_size
@try_ studio_snapshot(joinpath(P, "p08_$(style)_a.png"))
@try_ studio_snapshot(joinpath(P, "p08_$(style)_b.png"))
@try_ studio_snapshot(joinpath(P, "p08_$(style)_win.png"); area = :window)
@try_ studio_set!(:plot_style => :heatmap_flat)
@try_ studio_snapshot(joinpath(P, "p08_$(style)_then_flat.png"))
save(joinpath(P, "p08_$(style)_native_after.png"), fig)
@show studio_state().status
