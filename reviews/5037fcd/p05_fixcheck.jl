# p05 with a patched launch_plotter (view reset after reset_plotter!): does the animation leak go away?
using PDEStudio
@eval PDEStudio function launch_plotter(config::Union{Nothing, SimulationConfig} = nothing; style::Union{Nothing, Symbol} = nothing)
    fresh = false
    if !isnothing(config)
        _prepare_for_config!(config, style)
        old = manager.active_config
        fresh = isnothing(old) || _view_setup(old) != _view_setup(config)
    end
    plot_style = isnothing(style) ? nothing : _resolve_plot_style(style)
    reset_plotter!()
    fresh && _reset_config_view!()
    master_fig = Figure()
    ctrl_layout = master_fig[1, 1] = GridLayout()
    plot_layout = master_fig[1, 2] = GridLayout(alignmode = Outside())
    create_controls(ctrl_layout)
    isnothing(plot_style) || _set_public_style!(manager.widgets[:plot_style], plot_style)
    isnothing(manager.active_config) || _map_parameters_to_sliders!(manager.active_config)
    setup_ui_interactions!(master_fig, plot_layout, Val(manager.mode[]))
    manager.is_open = true
    manager.master_fig = master_fig
    setup_plot_window!(master_fig, plot_layout)
    resize_to_layout!(master_fig)
    if !isnothing(config)
        set_sim_config!(config)
        force_simulation()
    end
    return master_fig
end
include(joinpath(@__DIR__, "p05_glmakie.jl"))
