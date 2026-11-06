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

@testset "probe: Play Anim and Lock Camera (adoptable)" begin
    show_tab!(:plot)
    at = w()[:anim_target]
    @test any(o -> o[2] === :t, at.options[])
    at.i_selected[] = findfirst(o -> o[2] === :t, at.options[]); yield()
    t_slider = w()[get(manager.reverse_map, :t, :t)]
    v0 = t_slider.value[]
    manager.ui[:export][:animation_time] = 1.0
    click_button!(:play_anim_button)
    @test manager.is_animating[] && w()[:play_anim_button].label[] == "Stop Anim"
    sleep(0.6)
    @test t_slider.value[] != v0                 # the timer drives the time slider
    click_button!(:play_anim_button)
    @test !manager.is_animating[] && isnothing(manager.animation_timer[]) && w()[:play_anim_button].label[] == "Play Anim"
    v1 = t_slider.value[]; sleep(0.3)
    @test t_slider.value[] == v1                 # stopped
    # an active plot axis can't be animated
    at.i_selected[] = findfirst(o -> o[2] === :x, at.options[] ) |> x -> something(x, 1); yield()
    click_button!(:play_anim_button)
    @show status()
    @test !manager.is_animating[]

    click_button!(:lock_camera_button)
    @test manager.camera_locked[] && w()[:lock_camera_button].label[] == "Camera: Locked"
    click_button!(:lock_camera_button)
    @test !manager.camera_locked[] && isempty(manager.camera_cache) && w()[:lock_camera_button].label[] == "Lock Camera"
end
