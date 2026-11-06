# d302bc6: what runs at the load and at Run (`_run_simulations`, as simulation_trigger calls it), per environment.
# Every file logs "<file> v<VAL> @<dir tag>" into RUNLOG when it runs; A = original folder, B = bundle folder.
using Test, PDEStudio
const P = PDEStudio
include(joinpath(@__DIR__, "old", "solver.jl"))
set_save_path!(mktempdir())
const RUNLOG = String[]
println("Core skips sources: ", P._CORE_SKIPS_SOURCES)
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
logline(f) = "push!(Main.RUNLOG, \"$f vVAL @\" * (occursin(\"_sources\", @__DIR__) ? \"B\" : \"A\"))\n"
cfgend(expr; listed) = """
    SimulationConfig(create_param_dict(:N => $expr, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m];
                     sources = [$(join(["joinpath(@__DIR__, $(repr(l)))" for l in listed], ", "))])
    """
function project(dir, files, v)
    for (n, t) in files
        mkpath(dirname(joinpath(dir, n)))
        write(joinpath(dir, n), replace(t, "VAL" => string(v)))
    end
end
function run!()
    empty!(RUNLOG)
    msg = try
        P._run_simulations(P.manager.active_config; force_overwrite = true); "ok"
    catch e
        "FAILS: " * first(split(sprint(showerror, e isa LoadError ? e.error : e), '\n'))[1:min(end, 90)]
    end
    return "$msg $(RUNLOG)"
end
srcs() = [replace(s, r".*/(jl_\w+)/" => "") for s in P.manager.active_config.sources]
function case(tag; files, edit_files = files, v_edit = 2, listed = String[], gone = false, between = nothing)
    A = mktempdir(); E = mktempdir()
    project(A, files, 1)
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    v_edit === nothing || project(A, edit_files, v_edit)
    gone && rm(A; recursive = true)
    reset_manager!(); empty!(RUNLOG)
    P.load_and_apply_csv!(joinpath(E, "exp.csv"))
    println(tag)
    println("   load: $(RUNLOG) failures=$(P.manager.source_failures) note=$(repr(P.manager.source_note))")
    println("   sources: ", [occursin("_sources", s) ? "B/" * basename(s) : "A/" * basename(s) for s in P.manager.active_config.sources])
    println("   Run 1: ", run!())
    isnothing(between) || (between(A, E); println("   Run 2: ", run!()))
    return A, E
end
L(f) = logline(f)
cfg_u = L("cfg") * "include(\"u.jl\")\n" * cfgend("uN()"; listed = [])
@testset "probe" begin
println("== 1. never exported: _run_simulations vs Core's run_all_simulations")
let A = mktempdir()
    project(A, ["u.jl" => L("u") * "uN() = 20\n", "cfg.jl" => cfg_u], 1)
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl"))
    println("   studio Run: ", run!())
    empty!(RUNLOG); run_all_simulations(P.manager.active_config; force_overwrite = true); println("   Core run:   ", RUNLOG)
end
println("== 2. unlisted helper; cfg edited")
case("unlisted u.jl, cfg.jl edited"; files = ["u.jl" => L("u") * "uN() = 20\n", "cfg.jl" => cfg_u], edit_files = ["cfg.jl" => cfg_u])
println("== 3. listed helper h.jl edited, cfg.jl unchanged: which hval() is defined after Run?")
cfg_h = L("cfg") * "include(\"h.jl\")\n" * cfgend("20"; listed = ["h.jl"])
case("listed h.jl edited"; files = ["h.jl" => L("h") * "hval() = VAL\n", "cfg.jl" => cfg_h], edit_files = ["h.jl" => L("h") * "hval() = VAL\n"],
     between = (A, E) -> println("   after Run 1: hval() = ", Base.invokelatest(Main.hval)))
println("   after Run 2: hval() = ", Base.invokelatest(Main.hval))
println("== 4. Load -> Run -> the user edits the bundled copy of the edited cfg.jl (now the source) -> Run")
case("edit the copy (source) between runs"; files = ["u.jl" => L("u") * "uN() = 20\n", "cfg.jl" => cfg_u], edit_files = ["cfg.jl" => cfg_u],
     between = (A, E) -> (f = joinpath(E, "exp_sources", "cfg.jl"); write(f, replace(read(f, String), "v1" => "v3"));
                         println("   _origin_of(copy) after the edit: ", P._origin_of(f))))
println("== 5. originals deleted, listed subfolder helper lib/h.jl")
cfg_lib = L("cfg") * "include(\"lib/h.jl\")\n" * cfgend("hN()"; listed = ["lib/h.jl"])
case("lib/h.jl, originals gone"; files = ["lib/h.jl" => L("h") * "hN() = 20\n", "cfg.jl" => cfg_lib], v_edit = nothing, gone = true)
println("== 6. unchanged originals, unlisted helper edited between load and Run (runs as it is now)")
case("unchanged, u edited before Run 2"; files = ["u.jl" => L("u") * "uN() = 20\n", "cfg.jl" => cfg_u], v_edit = nothing,
     between = (A, E) -> project(A, ["u.jl" => L("u") * "uN() = 20\n"], 7))
println("== 7. reset_manager! between load and Run, config object kept (set_sim_config!(cfg))")
let (A, E) = case("cfg edited, then reset + set_sim_config!"; files = ["u.jl" => L("u") * "uN() = 20\n", "cfg.jl" => cfg_u], edit_files = ["cfg.jl" => cfg_u])
    c = P.manager.active_config; reset_manager!(); set_sim_config!(c)
    println("   Run after reset: ", run!())
end
println("== 8. a bundled copy loaded as .jl (load_config_file!) after its export was loaded: @__DIR__ at load vs Run")
cfg_hl = L("cfg") * "include(\"h.jl\")\n" * cfgend("hN()"; listed = ["h.jl"])
let (A, E) = case("both edited"; files = ["h.jl" => L("h") * "hN() = 20\n", "cfg.jl" => cfg_hl])
    empty!(RUNLOG); P.load_config_file!(joinpath(E, "exp_sources", "cfg.jl")); println("   load_config_file!(B/cfg.jl): ", RUNLOG)
    println("   sources: ", [occursin("_sources", s) ? "B/" * basename(s) : "A/" * basename(s) for s in P.manager.active_config.sources])
    println("   Run: ", run!())
end
end
