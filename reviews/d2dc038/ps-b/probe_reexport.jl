# Probe: does an export of a reloaded export keep its bundled sources?
using PDEStudio, Test, StaticArrays
isempty(get(ENV, "OLD_CONFIGIO", "")) || Base.include(PDEStudio, ENV["OLD_CONFIGIO"])
PDEStudioCore.set_target_module!(Main)
set_save_path!(mktempdir())
reset_manager!()
dir = mktempdir()
write(joinpath(dir, "fn_cfg.jl"), """
    initial_condition(x) = sin(x) + 2.0
    fn_cfg() = SimulationConfig(create_param_dict(:N => 16, :ic => initial_condition, :sim_func_name => :whatever),
                                create_method_dict(:m => create_param_dict()), [:m])
    fn_cfg
    """)
# plain config file ending with a SimulationConfig (no function)
write(joinpath(dir, "plain_cfg.jl"), """
    ic2(x) = x
    SimulationConfig(create_param_dict(:N => 16, :ic => ic2, :sim_func_name => :whatever),
                     create_method_dict(:m => create_param_dict()), [:m])
    """)
@testset "re-export keeps bundled sources ($f)" for f in split(get(ENV, "PROBE_FILES", "fn_cfg.jl plain_cfg.jl"))
    reset_manager!()
    PDEStudio.load_config_file!(joinpath(dir, f))
    @show PDEStudio.manager.active_config.sources
    out1 = mktempdir(); out2 = mktempdir()
    @test PDEStudio.save_params_to_csv("exp", out1, Dict("Save Type" => "test"))
    reset_manager!()
    PDEStudio.load_and_apply_csv!(joinpath(out1, "exp.csv"))
    @show PDEStudio.manager.active_config.sources PDEStudio.manager.source_failures
    @test PDEStudio.save_params_to_csv("exp2", out2, Dict("Save Type" => "test"))
    p2 = PDEStudio.parse_csv_to_dict(joinpath(out2, "exp2.csv"))
    @show get(p2["Metadata"]["General"], "bundled_sources", nothing)
    @test haskey(p2["Metadata"]["General"], "bundled_sources")
    # loading the second export in a fresh state: the function parameter must survive
    reset_manager!()
    PDEStudio.load_and_apply_csv!(joinpath(out2, "exp2.csv"))
    @show typeof(PDEStudio.manager.active_config.shared[:ic])
    @test PDEStudio.manager.active_config.shared[:ic] isa Function
end
