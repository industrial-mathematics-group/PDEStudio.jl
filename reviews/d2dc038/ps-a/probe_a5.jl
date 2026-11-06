include(joinpath(@__DIR__, "common.jl"))
@testset "ps-a probe 5: what the load confirmation covers" begin
    fig = open_studio()
    w = manager.widgets
    dir = mktempdir()
    write(joinpath(dir, "helper.jl"), "helper_N() = 24\n")
    cfg = joinpath(dir, "config.jl")
    write(cfg, """
        include("helper.jl")
        SimulationConfig(create_param_dict(:N => helper_N(), :cfl => 0.5, :sim_func_name => :advection_solver_1d),
                         create_method_dict(:upwind => create_param_dict(:scheme => "upwind")), [:upwind])
        """)
    PDEStudio._show_editor_text!(w[:export_text], cfg)
    click_button!(:load_config_button)
    @test occursin("click Load again", status())
    # the included file changes between the two clicks (the confirmed file itself doesn't)
    write(joinpath(dir, "helper.jl"), "helper_N() = 99\n")
    click_button!(:load_config_button)
    @info "after the second click" status() manager.active_config.shared[:N]
    @test occursin("click Load again", status())   # expected to FAIL: the changed include runs without a new confirmation

    # wrap: a message without spaces, and one that is exactly n + 1 characters
    n = PDEStudio.STATUS_LINE_CHARS
    s = PDEStudio._wrap_status(repeat("x", 2n + 5))
    @info "no-space wrap" split(s, '\n') length.(split(s, '\n'))
    @test all(l -> length(l) <= n, split(s, '\n'))
    s2 = PDEStudio._wrap_status(" " * repeat("y", n + 3))   # a leading space is the only space
    @info "leading space wrap" split(s2, '\n')
    @test !isempty(first(split(s2, '\n')))
end
