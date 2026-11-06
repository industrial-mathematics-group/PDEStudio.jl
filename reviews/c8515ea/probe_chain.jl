# c8515ea: re-export chains and manager.source_origins (copy => original), never cleared except by reset_manager!
using Test, PDEStudio
const P = PDEStudio
set_save_path!(mktempdir())
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
N() = P.manager.active_config.shared[:N]
origins(csv) = P.parse_csv_to_dict(csv)["Metadata"]["General"]["source_origins"]
st() = (N = isnothing(P.manager.active_config) ? nothing : N(), note = P.manager.source_note, failures = copy(P.manager.source_failures))
load!(csv) = (reset_manager!(); P.load_and_apply_csv!(csv); st())
cfgtext(extra = "") = """
    include("h.jl")
    SimulationConfig(create_param_dict(:N => hN()$extra, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m]; sources = [joinpath(@__DIR__, "h.jl")])
    """
function project(dir, v; extra = "")
    mkpath(dir); write(joinpath(dir, "h.jl"), "hN() = $v\n"); write(joinpath(dir, "cfg.jl"), cfgtext(extra))
end
@testset verbose = true "chain" begin
@testset "3+ generations, originals edited / moved / recreated" begin
    root = mktempdir(); A = joinpath(root, "A"); E1, E2, E3 = mktempdir(), mktempdir(), mktempdir()
    project(A, 1); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E1)
    project(A, 2)
    r = load!(joinpath(E1, "exp.csv")); println("gen1 load (A edited): ", r); @test r.N == 1
    exp!("exp", E2); println("  E2 origins: ", origins(joinpath(E2, "exp.csv")))
    mv(A, joinpath(root, "A2")); rm(E1; recursive = true)
    r = load!(joinpath(E2, "exp.csv")); println("gen2 load (A moved, E1 deleted): ", r); @test r.N == 1 && isempty(r.failures)
    exp!("exp", E3); println("  E3 origins: ", origins(joinpath(E3, "exp.csv")))
    @test all(o -> startswith(o, A), origins(joinpath(E3, "exp.csv")))
    project(A, 4)   # a new folder at the old place (e.g. another checkout)
    r = load!(joinpath(E3, "exp.csv")); println("gen3 load (A recreated with 4): ", r); @test r.N == 1
    exp!("exp", E3)  # re-export over itself (copies == destination)
    r = load!(joinpath(E3, "exp.csv")); println("gen3 re-exported over itself: ", r, " origins ", origins(joinpath(E3, "exp.csv")))
    @test r.N == 1
end
@testset "stale entry: a loaded bundle is overwritten by another export, then its file is loaded as .jl" begin
    A, B, D, E = mktempdir(), mktempdir(), mktempdir(), mktempdir()
    project(A, 1); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", D)
    r = load!(joinpath(D, "exp.csv")); println("load D/exp (from A): ", r)
    # another project B, same file names, exported to the same place (no reset_manager! in between: one session)
    project(B, 50; extra = " + 0"); P.load_config_file!(joinpath(B, "cfg.jl")); exp!("exp", D)
    println("  D/exp origins now: ", origins(joinpath(D, "exp.csv")))
    # the user opens the bundled configuration file itself and exports again
    P.load_config_file!(joinpath(D, "exp_sources", "cfg.jl")); println("  loaded the bundled cfg.jl: N = ", N())
    exp!("exp2", E)
    o = origins(joinpath(E, "exp2.csv")); println("  E/exp2 origins: ", o, "   (content is B's)")
    @test all(x -> startswith(x, B) || startswith(x, D), o)
    r = load!(joinpath(E, "exp2.csv")); println("  load E/exp2: ", r)
end
@testset "relative sources entry and an unrelated file of that name in the working directory" begin
    A, D, W = mktempdir(), mktempdir(), mktempdir()
    write(joinpath(A, "h.jl"), "hN() = 1\n")
    write(joinpath(A, "cfg.jl"), replace(cfgtext(), "joinpath(@__DIR__, \"h.jl\")" => "\"h.jl\""))
    cd(A) do; P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", D); end
    println("  D/exp bundled: ", readdir(joinpath(D, "exp_sources")), " origins ", origins(joinpath(D, "exp.csv")))
    write(joinpath(W, "h.jl"), "unrelated() = 0\n")
    cd(W) do; r = load!(joinpath(D, "exp.csv")); println("  load from another working dir with an unrelated h.jl: ", r,
                                                         " sources = ", P.manager.active_config.sources); end
end
end
