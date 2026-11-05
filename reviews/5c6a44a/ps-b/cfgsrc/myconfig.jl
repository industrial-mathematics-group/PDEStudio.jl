initial_condition(x) = sin(x) + 2.0
function probe_cfg()
    return SimulationConfig(create_param_dict(:N => 16, :ic => initial_condition, :sim_func_name => :probe_solver),
                            create_method_dict(:m => create_param_dict()), [:m])
end
probe_cfg          # the file ends with a function that returns the configuration (supported by load_config_file!)
