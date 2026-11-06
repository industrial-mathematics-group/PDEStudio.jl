# 8b6ce45: _NAME_HEADS (:global, :local, :const, :parameters, :macrocall), tuple targets, defaults in signatures.
# The listed helper h.jl (form_val() = 1) is edited to 2 after the export ("copy" = 1, "ORIGINAL" = 2).
# mode :edited = h.jl edited after the export; :none = nothing edited (only checks that the export load still works).
using Test, PDEStudio
const P = PDEStudio
include(joinpath(@__DIR__, "old", "solver.jl"))
set_save_path!(mktempdir())
println("Core skips sources: ", P._CORE_SKIPS_SOURCES)
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
cfgend(; listed = ["h.jl"]) = """
    SimulationConfig(create_param_dict(:N => 20, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m];
                     sources = [$(join(["joinpath(@__DIR__, $(repr(l)))" for l in listed], ", "))])
    """
val() = try Base.invokelatest(Main.form_val) catch; missing end
verdict(v) = v === 1 ? "copy" : v === 2 ? "ORIGINAL" : v === 0 ? "none" : string(v)
short(s) = first(split(s, '\n'))[1:min(end, 95)]
function form(tag, body; mode = :edited)
    A = mktempdir(); E = mktempdir()
    write(joinpath(A, "h.jl"), "form_val() = 1\n")
    write(joinpath(A, "cfg.jl"), body * "\n" * cfgend())
    reset_manager!()
    Main.eval(:(form_val() = 0))
    ok = try P.load_config_file!(joinpath(A, "cfg.jl")); true catch e
        println(rpad(tag, 46), "the .jl itself fails: ", short(sprint(showerror, e))); false end
    ok || return
    jl = verdict(val())
    exp!("exp", E)
    Main.BMG_CALLED[] = false
    mode === :edited && write(joinpath(A, "h.jl"), "form_val() = 2\n")
    reset_manager!()
    Main.eval(:(form_val() = 0))
    P.load_and_apply_csv!(joinpath(E, "exp.csv"))
    f = P.manager.source_failures
    load = isempty(f) ? verdict(val()) : "FAIL " * short(first(f))
    Main.eval(:(form_val() = 0))
    run = try
        P._run_simulations(P.manager.active_config; force_overwrite = false); verdict(val())
    catch e
        "FAIL " * short(sprint(showerror, e isa LoadError ? e.error : e))
    end
    println(rpad(tag, 46), "jl: ", rpad(jl, 5), " export load: ", rpad(load, 10), " Run: ", run, occursin("own include", tag) ? "   (own include called: $(Main.BMG_CALLED[]))" : "")
end
forms = [
    # the new tests' forms (control)
    "kw value: kwget(; v = include(\"h.jl\"))" => "kwget(; v) = v\nkwget(; v = include(\"h.jl\"))",
    "global g = include(\"h.jl\")" => "global gform = include(\"h.jl\")",
    "local r = include(\"h.jl\") in a let" => "let\n local r = include(\"h.jl\")\nend",
    "curly: Ref{typeof(include(\"h.jl\"))}" => "Ref{typeof(include(\"h.jl\"))}",
    # tuple targets
    "(a, b) = (include(\"h.jl\"), 1)" => "(ta, tb) = (include(\"h.jl\"), 1)",
    "global (a, b) = (include(\"h.jl\"), 1)" => "global (gta, gtb) = (include(\"h.jl\"), 1)",
    "const (a, b) = (include(\"h.jl\"), 1)" => "const (cta, ctb) = (include(\"h.jl\"), 1)",
    "(; a) = (; a = include(\"h.jl\"))" => "(; nta) = (; nta = include(\"h.jl\"))",
    "(include, b) = (\"h.jl\", 1) top level" => "(include, tb2) = (\"h.jl\", 1)\nBase.include(@__MODULE__, joinpath(@__DIR__, include))",
    "for (k, f) in pairs: include(f)" => "for (k, f) in [(1, \"h.jl\")]\n include(f)\nend",
    "[include(f) for (k, f) in …]" => "[include(f) for (k, f) in [(1, \"h.jl\")]]",
    # declarations
    "const inc = include; inc(\"h.jl\")" => "const cinc = include\ncinc(\"h.jl\")",
    "global inc = include (in a function)" => "function gset()\n global ginc = include\nend\ngset()\nginc(\"h.jl\")",
    "local include = …; include(\"h.jl\")" => "let\n local include = p -> Base.include(@__MODULE__, joinpath(@__DIR__, p))\n include(\"h.jl\")\nend",
    # keyword shorthand / parameters
    "kw shorthand: kwi(; include) → include(\"h.jl\")" => "kwi(; include) = include(\"h.jl\")\nlet include = include\n kwi(; include)\nend",
    "kw splat: kws(; kw...) with (; v = include)" => "kws(; kw...) = kw[:v](\"h.jl\")\nkws(; (; v = include)...)",
    # macro arguments
    "@. include([\"h.jl\"])" => "@. include([\"h.jl\"])",
    "@invokelatest include(\"h.jl\")" => "@invokelatest include(\"h.jl\")",
    "Base.@invokelatest foreach(include, …)" => "Base.@invokelatest foreach(include, [\"h.jl\"])",
    "@time include(\"h.jl\")" => "@time include(\"h.jl\")",
    "macro m(f) f end; @m(include)(\"h.jl\")" => "macro idm(f)\n esc(f)\nend\n(@idm include)(\"h.jl\")",
    "@static if true include(\"h.jl\") end" => "@static if true\n include(\"h.jl\")\nend",
    # defaults in signatures (kept as a whole)
    "default: fdef(x = include(\"h.jl\")) = x; fdef()" => "fdef(x = include(\"h.jl\")) = x\nfdef()",
    "kw default: fkw(; v = include(\"h.jl\")) = v" => "fkw(; v = include(\"h.jl\")) = v\nfkw()",
    "function f(; v = include(\"h.jl\")) … end" => "function fkw2(; v = include(\"h.jl\"))\n v\nend\nfkw2()",
    # catch variable
    "catch include … end; include(\"h.jl\")" => "try\n error(\"x\")\ncatch include\nend\ninclude(\"h.jl\")",
]
const BMG_CALLED = Ref(false)
for (tag, body) in forms
    form(tag, body)
end
println("-- nothing edited (export load must not fail)")
for (tag, body) in forms
    form(tag, body; mode = :none)
end
