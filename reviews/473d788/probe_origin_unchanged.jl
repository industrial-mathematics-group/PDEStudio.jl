# 473d788: `_origin_of(copy; unchanged = false)` at Run vs `unchanged = true` at export, and stale entries of
# `manager.source_origins` (never cleared by load_config_file!). A = original folder, B = bundle folder (E/exp_sources).
using Test, PDEStudio
const P = PDEStudio
include(joinpath(@__DIR__, "old", "solver.jl"))
set_save_path!(mktempdir())
println("Core skips sources: ", P._CORE_SKIPS_SOURCES)
const RUNLOG = String[]
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
tagdir() = "(occursin(\"_sources\", @__DIR__) ? \"B\" : \"A\")"
short(s) = first(split(s, '\n'))[1:min(end, 100)]
function run!()
    empty!(RUNLOG)
    msg = try
        P._run_simulations(P.manager.active_config; force_overwrite = true); "ok"
    catch e
        "FAILS: " * short(sprint(showerror, e isa LoadError ? e.error : e))
    end
    return "$msg $(RUNLOG)"
end
loadcsv!(f) = (empty!(RUNLOG); P.load_and_apply_csv!(f);
               "$(RUNLOG) failures=$(P.manager.source_failures) note=$(repr(P.manager.source_note)) N=$(P.manager.active_config.shared[:N])")
origins(csv) = P.parse_csv_to_dict(csv)["Metadata"]["General"]["source_origins"]
loc(s) = occursin("_sources", s) ? "B/" * basename(s) : "A/" * basename(s)
cfg(v) = """
    push!(Main.RUNLOG, "cfg v$v @" * $(tagdir()))
    include("u.jl")    # unlisted helper next to the original
    SimulationConfig(create_param_dict(:N => uN() + $v, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m])
    """
@testset "probe" begin
println("== 1. cfg.jl edited after the export; load; the user edits the copy (the source, as the docs say); Run; export; reload")
let A = mktempdir(), E = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    println("   sources: ", loc.(P.manager.active_config.sources))
    copy = joinpath(E, "exp_sources", "cfg.jl")
    write(copy, cfg(3))
    println("   Run after editing the copy: ", run!())
    E2 = mktempdir(); exp!("exp", E2)
    println("   export E2 records origins: ", origins(joinpath(E2, "exp.csv")), "  (A = $A)")
    reset_manager!(); println("   reload E2: ", loadcsv!(joinpath(E2, "exp.csv")))
end
println("== 2. as 1, but the edited copy is loaded with load_config_file! (Files -> Load) and includes a helper the user put next to it")
let A = mktempdir(), E = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    B = joinpath(E, "exp_sources")
    write(joinpath(B, "u.jl"), "uN() = 30\n")      # the user's own helper next to the copy
    write(joinpath(B, "cfg.jl"), cfg(4))
    empty!(RUNLOG); P.load_config_file!(joinpath(B, "cfg.jl"))
    println("   load_config_file!(B/cfg.jl): ", RUNLOG, " N=", P.manager.active_config.shared[:N], " uN()=", Base.invokelatest(Main.uN))
    println("   sources: ", loc.(P.manager.active_config.sources))
    println("   Run: ", run!(), "   uN() after Run = ", Base.invokelatest(Main.uN), " (30 = B/u.jl as loaded, 20 = A/u.jl)")
end
println("== 3. the bundle of the loaded export is overwritten by an export of another configuration, which is then loaded as .jl")
let A = mktempdir(), E = mktempdir(), O = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    # another project O, whose cfg.jl includes its listed helper u.jl (uN() = 50)
    write(joinpath(O, "u.jl"), "uN() = 50\n")
    write(joinpath(O, "cfg.jl"), replace(cfg(5), "[:m])" => "[:m]; sources = [joinpath(@__DIR__, \"u.jl\")])"))
    P.load_config_file!(joinpath(O, "cfg.jl")); exp!("exp", E)          # overwrites E/exp_sources/{u,cfg}.jl
    empty!(RUNLOG); P.load_config_file!(joinpath(E, "exp_sources", "cfg.jl"))
    println("   load_config_file!(E/exp_sources/cfg.jl): ", RUNLOG, " N=", P.manager.active_config.shared[:N])
    println("   Run: ", run!(), "   uN() after Run = ", Base.invokelatest(Main.uN), " (50 = O's helper, 20 = A's)")
    E3 = mktempdir(); exp!("exp", E3); println("   its export records: ", origins(joinpath(E3, "exp.csv")))
end
end
