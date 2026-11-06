# 8b6ce45: the origin rule without digest (`_origin_of`), entries dropped by load_config_file! and by exports that
# write over a bundle. A = original folder, B = bundle folder (E/exp_sources). Every file logs "<f> v<v> @A|B".
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
entries() = Dict(loc(k) => loc(v isa NamedTuple ? v.origin : v) for (k, v) in P.manager.source_origins)   # (473d788 stores (origin, digest))
cfg(v; listed = String[]) = """
    push!(Main.RUNLOG, "cfg v$v @" * $(tagdir()))
    include("u.jl")    # unlisted helper next to the original
    SimulationConfig(create_param_dict(:N => uN() + $v, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m];
                     sources = [$(join(["joinpath(@__DIR__, $(repr(l)))" for l in listed], ", "))])
    """
@testset "probe" begin
println("== 1. load E (cfg.jl edited -> copy recorded); Run; Files -> Load of the copy FAILS (u.jl not in B); the active config is still E's; Run")
let A = mktempdir(), E = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    println("   sources: ", loc.(P.manager.active_config.sources), "  entries: ", entries())
    println("   Run 1: ", run!())
    r = try P.load_config_file!(joinpath(E, "exp_sources", "cfg.jl")); "ok" catch e "FAILS: " * short(sprint(showerror, e isa LoadError ? e.error : e)) end
    println("   load_config_file!(B/cfg.jl): ", r)
    println("   active sources still: ", loc.(P.manager.active_config.sources), "  entries: ", entries())
    println("   Run 2 (same config as Run 1): ", run!())
    E2 = mktempdir(); exp!("exp", E2); println("   export now records: ", loc.(origins(joinpath(E2, "exp.csv"))))
end
println("== 2. h.jl (listed, edited) uses a data file next to it; load E; Files -> Load of B/cfg.jl; Run: where does h.jl run?")
hfile(v) = """
    push!(Main.RUNLOG, "h v$v @" * $(tagdir()) * " d=" * strip(read(joinpath(@__DIR__, "d.txt"), String)))
    hN() = $v
    """
let A = mktempdir(), E = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "d.txt"), "dataA")
    write(joinpath(A, "h.jl"), hfile(1)); write(joinpath(A, "cfg.jl"), cfg(1; listed = ["h.jl"]))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "h.jl"), hfile(2)); write(joinpath(A, "cfg.jl"), cfg(2; listed = ["h.jl"]))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    B = joinpath(E, "exp_sources")
    write(joinpath(B, "u.jl"), "uN() = 30\n"); write(joinpath(B, "d.txt"), "dataB")   # the user makes B self-contained
    empty!(RUNLOG); P.load_config_file!(joinpath(B, "cfg.jl"))
    println("   load_config_file!(B/cfg.jl): ", RUNLOG, " N=", P.manager.active_config.shared[:N])
    println("   sources: ", loc.(P.manager.active_config.sources), "  entries: ", entries())
    println("   Run: ", run!())
    println("   Core's own run_all_simulations (plain includes): ", (empty!(RUNLOG); run_all_simulations(P.manager.active_config; force_overwrite = true); RUNLOG))
    E2 = mktempdir(); exp!("exp", E2); println("   export records: ", loc.(origins(joinpath(E2, "exp.csv"))))
end
println("== 3. export into the bundle folder through a symlinked path (same files, other abspath)")
let A = mktempdir(), E = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    L = joinpath(mktempdir(), "link"); symlink(E, L)
    ok = exp!("exp", L)
    println("   export to symlink of E returns ", ok, "; copy still there: ", isfile(joinpath(E, "exp_sources", "cfg.jl")),
            "; content v1: ", occursin("cfg v1", read(joinpath(E, "exp_sources", "cfg.jl"), String)))
end
println("== 4. export of the loaded config into the same folder and name (src == dst), reload, Run")
let A = mktempdir(), E = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    exp!("exp", E); println("   re-export records: ", loc.(origins(joinpath(E, "exp.csv"))))
    reset_manager!(); println("   reload: ", loadcsv!(joinpath(E, "exp.csv")))
    println("   Run: ", run!())
end
println("== 5. load E; export the loaded config to E2; load E2; Run; Files -> Load of E's copy (a different file); Run E2 config again")
let A = mktempdir(), E = mktempdir(), E2 = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!(); println("   load E: ", loadcsv!(joinpath(E, "exp.csv")))
    exp!("exp", E2)
    println("   load E2: ", loadcsv!(joinpath(E2, "exp.csv")), " entries: ", length(P.manager.source_origins))
    println("   Run: ", run!())
end
println("== 6. status line after a failed source (headless: status observables installed by hand)")
let A = mktempdir(), E = mktempdir()
    write(joinpath(A, "u.jl"), "uN() = 20\n"); write(joinpath(A, "cfg.jl"), cfg(1))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    rm(joinpath(A, "u.jl")); write(joinpath(A, "cfg.jl"), cfg(2))
    reset_manager!()
    P.manager.widgets[:status] = P.Observable(""); P.manager.widgets[:status_color] = P.Observable(P.STATUS_COLORS[:info])
    try P.load_and_apply_csv!(joinpath(E, "exp.csv")) catch e println("   load threw: ", short(sprint(showerror, e))) end
    println("   failures: ", P.manager.source_failures)
    println("   status line as shown:\n", join(["   | " * l for l in split(P.manager.widgets[:status][], '\n')], "\n"))
    println("   failing file name visible: ", occursin("cfg.jl", P.manager.widgets[:status][]))
end
end
