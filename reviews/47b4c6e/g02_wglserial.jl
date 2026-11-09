# Simulates what a connected browser does to the figure (WGLMakie serialises every scene and plot), then snapshots.
using PDEStudio, WGLMakie
const P = @__DIR__
macro try_(ex)
    s = string(ex)
    quote
        try
            r = $(esc(ex)); println("OK   ", $s, " => ", typeof(r))
        catch e
            println("ERR  ", $s, " => ", typeof(e), ": ", first(sprint(showerror, e), 400))
        end
    end
end
WGLMakie.activate!()
set_save_path!(mktempdir())
style = Symbol(ARGS[1])
fig = launch_plotter(test_heat_2d(); style = style)
occursin("first", get(ARGS, 2, "")) && @try_ studio_snapshot(joinpath(P, "g02_$(style)_before.png"))
@try_ WGLMakie.serialize_scene(fig.scene)
@try_ studio_snapshot(joinpath(P, "g02_$(style)_after.png"))
println("END")
