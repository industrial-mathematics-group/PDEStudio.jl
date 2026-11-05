# Probe: a file the studio writes reads back without "Unknown scope/category" warnings, for every plot style
using PDEStudio, Test, Logging
PDEStudioCore.set_target_module!(Main)
set_save_path!(mktempdir()); reset_manager!()
cfg = SimulationConfig(create_param_dict(:N => 8, :sim_func_name => :nothing_here),
                       create_method_dict(:a => create_param_dict(:k => 1)), [:a]; varied = create_varied_dict(:N => [8, 16]))
set_sim_config!(cfg)
@testset "no unknown-scope warnings on reload ($style)" for style in vcat([o[2] for opts in values(PDEStudio.EULERIAN_PLOT_STYLE_OPTIONS) for o in opts], collect(keys(PDEStudio.PARTICLE_STYLES)))
    PDEStudio.switch_ui_plot_type!(PDEStudio._base_style(style))
    dir = mktempdir()
    @test PDEStudio.save_params_to_csv("s", dir, Dict("Save Type" => "t"))
    parsed = PDEStudio.parse_csv_to_dict(joinpath(dir, "s.csv"))
    logger = Test.TestLogger(min_level = Logging.Warn)
    with_logger(logger) do
        PDEStudio._warn_unknown_scopes(parsed)
    end
    msgs = [l.message for l in logger.logs]
    isempty(msgs) || println("  $style: ", msgs)
    @test isempty(msgs)
end
