# 473d788: `_redirected` and the skipped heads (:parameters, :curly, :braces), at the .jl load, the export load and Run.
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
    # :parameters is skipped as a whole: include calls in keyword values
    "kw value: kwget(; v = include(\"h.jl\"))" => "kwget(; v) = v\nkwget(; v = include(\"h.jl\"))",
    "kw value after ;: kwget2(1; v = include)" => "kwget2(x; v) = v(\"h.jl\")\nkwget2(1; v = include)",
    "named tuple (; a = include(\"h.jl\"))" => "nt = (; a = include(\"h.jl\"))",
    "curly: Ref{typeof(include(\"h.jl\"))}" => "Ref{typeof(include(\"h.jl\"))}",
    # value check: code that names `include`
    "tuple destructuring (include, b) = …" => "function destr()\n (include, b) = (\"h.jl\", 1)\n Base.include(@__MODULE__, joinpath(@__DIR__, include))\nend\ndestr()",
    "catch variable named include" => "try\n error(\"x\")\ncatch include\nend\ninclude(\"h.jl\")",
    "@enum Opt include exclude" => "module EM\n@enum FormOpt2 include exclude\nend\ninclude(\"h.jl\")",
    "@isdefined include" => "@isdefined(include) && include(\"h.jl\")",
    "inc = include; inc(\"h.jl\")" => "inc = include\ninc(\"h.jl\")",
    "macro inc(f) :(include(\$f)) end" => "macro incm(f)\n esc(:(include(\$f)))\nend\n@incm \"h.jl\"",
    "macro (hygienic) :(include(\$f))" => "macro incm2(f)\n :(include(\$f))\nend\n@incm2 \"h.jl\"",
    "closure: (() -> include(\"h.jl\"))()" => "(() -> include(\"h.jl\"))()",
    "generator: collect(include(f) for f in …)" => "collect(include(f) for f in [\"h.jl\"])",
    "arg named include: g(include) = include(…)" => "gi(include) = include(\"h.jl\")\ngi(include)",
    "@eval with \$include" => "@eval \$include(\"h.jl\")",
    "baremodule, no using Base, Base.include" => "baremodule BMF\nimport Base\nBase.include(BMF, Base.joinpath(Base.@__DIR__, \"h.jl\"))\nend\nform_val() = BMF.form_val()",
    "baremodule with own include + using Base" => "baremodule BMG\nusing Base\ninclude(p) = (Main.BMG_CALLED[] = true; Base.include(BMG, p))\ninclude(\"h.jl\")\nend\nform_val() = BMG.form_val()",
    "module with mapexpr include(f, path)" => "module MJ\ninclude(identity, \"h.jl\")\nend\nform_val() = MJ.form_val()",
    "string interpolation \"\$include\"" => "s = \"\$include\"\ninclude(\"h.jl\")",
    "typeof(include) in a method signature" => "fti(::typeof(include)) = 1\nfti(include)\ninclude(\"h.jl\")",
    "global g = include(\"h.jl\")" => "global gform = include(\"h.jl\")",
    "local r = include(\"h.jl\") in a let" => "let\n local r = include(\"h.jl\")\nend",
    "const C = include(\"h.jl\") (control)" => "const CFORM = include(\"h.jl\")",
    "for (include, x) in pairs" => "for (include, x) in [(\"h.jl\", 1)]\n Base.include(@__MODULE__, joinpath(@__DIR__, include))\nend",
]
const BMG_CALLED = Ref(false)
for (tag, body) in forms
    form(tag, body)
end
println("-- nothing edited (export load must not fail)")
for (tag, body) in forms
    form(tag, body; mode = :none)
end
