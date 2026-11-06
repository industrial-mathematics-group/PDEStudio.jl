# 473d788: "all copies are the sources once one differs" (PDEStudioCore without load_sources) and its effect on
# unlisted helpers and data files at Run; plus load -> Run -> export -> reload. A = original folder, B = bundle folder.
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
               "$(RUNLOG) failures=$(P.manager.source_failures) note=$(repr(P.manager.source_note))")
origins(csv) = P.parse_csv_to_dict(csv)["Metadata"]["General"]["source_origins"]
loc(s) = occursin("_sources", s) ? "B/" * basename(s) : "A/" * basename(s)
hv() = try Base.invokelatest(Main.hval) catch; missing end
h(v) = "push!(Main.RUNLOG, \"h v$v @\" * $(tagdir()))\nhval() = $v\n"
cfg(pre) = """
    push!(Main.RUNLOG, "cfg @" * $(tagdir()))
    include("h.jl")
    $pre
    SimulationConfig(create_param_dict(:N => 20, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m]; sources = [joinpath(@__DIR__, "h.jl")])
    """
function case(tag; pre = "", extra = Dict{String, String}(), edit! = (A, E) -> write(joinpath(A, "h.jl"), h(2)), after = nothing)
    A = mktempdir(); E = mktempdir()
    write(joinpath(A, "h.jl"), h(1)); write(joinpath(A, "cfg.jl"), cfg(pre))
    for (k, v) in extra; write(joinpath(A, k), v); end
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    edit!(A, E)
    reset_manager!()
    println(tag)
    println("   load:    ", loadcsv!(joinpath(E, "exp.csv")), "  hval() = ", hv())
    println("   sources: ", loc.(P.manager.active_config.sources))
    Main.eval(:(hval() = 0))
    println("   Run:     ", run!(), "  hval() = ", hv())
    isnothing(after) || after(A, E)
    return A, E
end
@testset "probe" begin
case("1. listed h.jl edited (finding 1 of d302bc6)"; edit! = (A, E) -> write(joinpath(A, "h.jl"), h(2)))
case("2. listed h.jl edited; cfg.jl includes an unlisted u.jl"; pre = "include(\"u.jl\")",
     extra = Dict("u.jl" => "uN() = 1\n"), edit! = (A, E) -> write(joinpath(A, "h.jl"), h(2)))
case("3. listed h.jl edited; cfg.jl reads a data file next to it"; pre = "n0 = read(joinpath(@__DIR__, \"n.txt\"), String)",
     extra = Dict("n.txt" => "3"), edit! = (A, E) -> write(joinpath(A, "h.jl"), h(2)))
case("4. the copy of cfg.jl is missing, listed h.jl edited";
     edit! = (A, E) -> (rm(joinpath(E, "exp_sources", "cfg.jl")); write(joinpath(A, "h.jl"), h(2))))
case("5. nothing edited, unlisted u.jl (control)"; pre = "include(\"u.jl\")", extra = Dict("u.jl" => "uN() = 1\n"),
     edit! = (A, E) -> nothing)
case("6. h.jl edited: load -> Run -> export -> reload, then the originals are gone -> reload";
     after = (A, E) -> begin
         E2 = mktempdir(); exp!("exp", E2)
         println("   export E2 origins in A: ", [dirname(o) == A for o in origins(joinpath(E2, "exp.csv"))])
         reset_manager!(); println("   reload E2: ", loadcsv!(joinpath(E2, "exp.csv")), "  hval() = ", hv())
         Main.eval(:(hval() = 0)); println("   Run:       ", run!(), "  hval() = ", hv())
         rm(A; recursive = true)
         reset_manager!(); println("   reload E2, A gone: ", loadcsv!(joinpath(E2, "exp.csv")), "  hval() = ", hv())
         Main.eval(:(hval() = 0)); println("   Run:       ", run!(), "  hval() = ", hv())
     end)
end
