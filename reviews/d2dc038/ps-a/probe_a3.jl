# Does an exception escaping an observable callback that runs in GLMakie's renderloop stop the window?
include(joinpath(@__DIR__, "common.jl"))
@testset "renderloop survives a throwing callback?" begin
    fig = open_studio()
    screen = only(filter(s -> s isa GLMakie.Screen, fig.scene.current_screens))
    @test GLMakie.renderloop_running(screen)
    fired = Ref(false)
    l = on(events(fig).tick) do _
        fired[] && return
        fired[] = true
        error("boom from a callback in the renderloop")
    end
    t0 = time(); while !fired[] && time() - t0 < 10; sleep(0.1); end
    sleep(1.0)
    off(l)
    @info "after the throwing tick callback" fired[] GLMakie.renderloop_running(screen) isopen(screen)
    @test GLMakie.renderloop_running(screen)
end
