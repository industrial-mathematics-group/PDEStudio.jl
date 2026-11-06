# f3ed3a2: the status line of `_handle_load` (source_note), a stale note after loading a .jl file, and the
# absolute-path case K of probe_bundle_cases.jl one generation further
using Test, PDEStudio, GLMakie
const P = PDEStudio
set_save_path!(mktempdir())
reset_plotter!()
fig = launch_plotter(); display(fig)
w = P.manager.widgets
status() = replace(w[:status][], '\n' => ' ')
orig = mktempdir(); out1 = mktempdir()
cfgtext(n) = """
    include("helper.jl")
    SimulationConfig(create_param_dict(:N => helper_N() + $n, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m]; sources = [joinpath(@__DIR__, "helper.jl")])
    """
write(joinpath(orig, "helper.jl"), "helper_N() = 24\n"); write(joinpath(orig, "config.jl"), cfgtext(0))
P.load_config_file!(joinpath(orig, "config.jl"))
P.save_params_to_csv("exp", out1, Dict("Save Type" => "test"))
write(joinpath(orig, "helper.jl"), "helper_N() = 25\n")
@testset "all" begin
@testset "status line" begin
    P._handle_load(joinpath(out1, "exp.csv"))
    println("status after loading the export: ", status(), "  colour = ", w[:status_color][])
    @test occursin("changed since the export", status())
    # now a .jl file: load_config_file! doesn't reset the note
    other = joinpath(mktempdir(), "other.jl")
    write(other, "SimulationConfig(create_param_dict(:N => 30, :sim_func_name => :advection_solver_1d), create_method_dict(:m => create_param_dict()), [:m])\n")
    P._handle_load(other)
    println("status after loading other.jl: ", status())
    @test !occursin("changed since the export", status())
end

@testset "K: absolute source path, two generations" begin
    reset_manager!()
    o2 = mktempdir(); e1, e2 = mktempdir(), mktempdir()
    h = joinpath(o2, "helper.jl"); write(h, "helper_N() = 24\n")
    write(joinpath(o2, "config.jl"), replace(cfgtext(0), "joinpath(@__DIR__, \"helper.jl\")" => repr(h)))
    P.load_config_file!(joinpath(o2, "config.jl")); P.save_params_to_csv("exp", e1, Dict("Save Type" => "test"))
    write(h, "helper_N() = 25\n")
    reset_manager!(); P.load_and_apply_csv!(joinpath(e1, "exp.csv"))
    println("K load 1: N = ", P.manager.active_config.shared[:N], " sources = ", P.manager.active_config.sources)
    P.save_params_to_csv("exp2", e2, Dict("Save Type" => "test"))
    for f in readdir(joinpath(e2, "exp2_sources")); println("  exp2_sources/$f: ", strip(read(joinpath(e2, "exp2_sources", f), String))[1:min(end, 40)]); end
    rm(o2; recursive = true); rm(e1; recursive = true)
    reset_manager!(); P.load_and_apply_csv!(joinpath(e2, "exp2.csv"))
    println("K export 2 alone: N = ", P.manager.active_config.shared[:N], " failures = ", P.manager.source_failures)
    @test P.manager.active_config.shared[:N] == 24
end
end
