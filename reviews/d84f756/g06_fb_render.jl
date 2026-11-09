using PDEStudio, GLMakie
GLMakie.activate!(px_per_unit = 2)
set_save_path!(mktempdir())
fig = launch_plotter(test_heat_2d(); style = :heatmap); display(fig)
scr = Makie.getscreen(fig.scene)
fb() = (ppu = scr.px_per_unit[], cfgppu = scr.config.px_per_unit, fb = size(scr.framebuffer))
sleep(1); @show fb()
studio_snapshot(joinpath(@__DIR__, "g06_hidpi_1x.png"))
sleep(1); @show fb()
studio_set!(:t => 0.02)          # a data update: the renderloop draws a new frame
sleep(1.5); @show fb()
println("END")
