# c8515ea: structural (staged) load of an export into an open window: status line, Run Simulation, re-export origins;
# and a structural load whose bundled source fails (is the failure still shown?)
using Test, PDEStudio, GLMakie
const P = PDEStudio
include(joinpath(@__DIR__, "solver.jl"))
set_save_path!(mktempdir())
w() = P.manager.widgets
status() = replace(w()[:status][], '\n' => ' ')
click!(b) = (w()[b].clicks[] += 1; yield())
A = mktempdir(); out1, out2 = mktempdir(), mktempdir()
write(joinpath(A, "h.jl"), "hN() = 24\n")

write(joinpath(A, "cfg.jl"), """
    include("h.jl")
    SimulationConfig(create_param_dict(:N => hN(), :cfl => 0.5, :scheme => "upwind", :q => 1, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:upwind => create_param_dict()), [:upwind];
                     varied = create_varied_dict(:cfl => [0.4, 0.5], :q => [1, 2], :N => [hN(), hN() + 2]),
                     sources = [joinpath(@__DIR__, "h.jl")])
    """)
reset_manager!()
P.load_config_file!(joinpath(A, "cfg.jl"))      # no window: max_params grows to 3
@test P.save_params_to_csv("exp", out1, Dict("Save Type" => "test"))
set_max_params!(2)
fig = launch_plotter(); display(fig)
write(joinpath(A, "h.jl"), "hN() = 25\n")
@testset "all" begin
@testset "staged" begin
    P._handle_load(joinpath(out1, "exp.csv"))
    println("structural status: ", status(), "  colour = ", w()[:status_color][])
    @test occursin("changes the dimensions", status()) && occursin("h.jl changed since the export", status())
    @test !isnothing(P.manager.csv_cache)
    click!(:run_button)
    sleep(1)
    println("after Run: N = ", P.manager.active_config.shared[:N], " sources = ", P.manager.active_config.sources,
            " max_params = ", P.manager.max_params)
    @test P.manager.active_config.shared[:N] == 24
    @test P.save_params_to_csv("exp2", out2, Dict("Save Type" => "test"))
    o = P.parse_csv_to_dict(joinpath(out2, "exp2.csv"))["Metadata"]["General"]["source_origins"]
    println("export 2 origins: ", o)
    @test all(x -> startswith(x, A), o)
end
@testset "structural + failing source" begin
    set_max_params!(2); fig = launch_plotter(); display(fig)
    rm(joinpath(A, "h.jl")); rm(joinpath(out1, "exp_sources", "h.jl"))   # copy and original gone: cfg.jl fails, the parameters come from the CSV (3 swept)
    P._handle_load(joinpath(out1, "exp.csv"))
    println("failures = ", P.manager.source_failures)
    println("structural status with a failure: ", status())
    @test !isempty(P.manager.source_failures)
    @test occursin("failed", status())
end
end
