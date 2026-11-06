# GUI probes of the UI area (GLMakie on the Xvfb display), in the style of test/runtests.jl
using PDEStudio, GLMakie, Test, StaticArrays
import PDEStudio: manager, show_tab!, show_editor_page!, preset_dir, sim_preset_dir
PDEStudioCore.set_target_module!(@__MODULE__)

function advection_solver_1d(params::ParamDict)
    N = params[:N]; cfl = get(params, :cfl, 0.5); dx = 2π / N; dt = cfl * dx
    Nt = ceil(Int, 2.0 / dt) + 1
    x = collect(range(0.0, step = dx, length = N)); t = collect(range(0.0, step = dt, length = Nt))
    u = fill(SVector{1, Float64}(0.0), N, Nt)
    for i in 1:N; u[i, 1] = SVector(sin(x[i]) + 2.0); end
    for n in 1:Nt-1, i in 1:N
        im1 = i == 1 ? N : i - 1
        u[i, n+1] = SVector(u[i, n][1] - cfl * (u[i, n][1] - u[im1, n][1]))
    end
    return create_sim_data(x, u, t, params; time_dim = :t, dims = :x)
end

set_save_path!(mktempdir())
reset_manager!()
set_mode!(:eulerian)
GLMakie.activate!()
click_button!(k) = (manager.widgets[k].clicks[] += 1; yield())
w() = manager.widgets
status() = replace(w()[:status][], '\n' => ' ')

shared = create_param_dict(:cfl => 0.5, :N => 20, :sim_func_name => :advection_solver_1d)
methods = create_method_dict(:upwind => create_param_dict(:scheme => "upwind"))
cfg = SimulationConfig(shared, methods, [:upwind])
fig = launch_plotter(); display(fig)
set_sim_config!(cfg)
click_button!(:run_button)

@testset "GUI probes 2" begin

@testset "probe: a deleted preset file stays in the list" begin
    save_sim_preset("gone"; description = "will be deleted")
    rm(joinpath(sim_preset_dir(), "gone.csv"))
    click_button!(:tab_files)
    click_button!(:sim_presets_button)
    @show manager.editor_row_keys
    @test !(:gone in manager.editor_row_keys)
    i = findfirst(isequal(:gone), manager.editor_row_keys)
    if !isnothing(i)
        w()[Symbol("method_row_", i, "_b")].clicks[] += 1; yield()
        @show status()
        @test !occursin("built in", status())
    end
end

@testset "probe: fewer active methods while Compare = methods is shown" begin
    two = SimulationConfig(shared, create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                                      :upwind2 => create_param_dict(:scheme => "upwind", :cfl => 0.4)),
                           [:upwind, :upwind2])
    set_sim_config!(two)
    click_button!(:run_button)
    show_tab!(:plot)
    w()[:compare_target].i_selected[] = findfirst(o -> o[2] === :methods, w()[:compare_target].options[])
    click_button!(:layout_apply)
    @test length(manager.caches) == 2
    set_sim_config!(cfg)                     # one method: nothing re-run yet
    errs = Ref(0)
    logger = Test.TestLogger(min_level = Base.CoreLogging.Error)
    Base.CoreLogging.with_logger(logger) do
        show_editor_page!(:ui, :x_axis_1d)
        i = findfirst(isequal(:log_scale), manager.editor_row_keys)
        w()[Symbol("editor_row_", i, "_button")].clicks[] += 1; yield()   # a replot option
    end
    @show [r.message for r in logger.logs]
    @test isempty(logger.logs)
end

end
