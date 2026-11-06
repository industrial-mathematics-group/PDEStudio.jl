# Probe: simulation CSV write/read round trips (no window). Run from the repo root:
#   julia -t 2 --project=test <scratch>/probe_csv_roundtrip.jl
using PDEStudio, Test, StaticArrays
const P = PDEStudio

@enum ProbeScheme probe_upwind probe_central
struct ProbeOpts; a::Int; b::Float64; end

function roundtrip(config)
    rows = P._CSVRows()
    P._add_simulation_rows!(rows, config)
    path = joinpath(mktempdir(), "sim.csv")
    P._write_rows(path, rows)
    return P.csv_to_simulation_config(P.parse_csv_to_dict(path)), path
end

hash_of(cfg, m) = calculate_hash(get_clean_params(assemble_params(cfg.shared, cfg.methods, m)))

@testset "CSV round trip: value types" begin
    vals = Dict{Symbol, Any}(
        :int => 3, :float => 0.30000000000000004, :f32 => 1.5f0, :neg0 => -0.0, :inf => Inf, :big => 1e300,
        :bool => true, :sym => :upwind, :sym_space => Symbol("a b"), :char => 'c',
        :str_num => "1e3", :str_type => "Float64", :str_nothing => "nothing", :str_Nothing => "Nothing",
        :str_sym => ":a", :str_range => "1:10", :str_empty_tag => "<empty>", :str_empty => "",
        :str_spaces => "  padded  ", :str_newline => "line1\nline2", :str_comma_quote => "he said \"hi\", ok",
        :str_quoted => "\"q\"", :str_trailing_quote => "a\"", :str_none => "none",
        :vec => [1.0, 2.0], :vec_str => ["a", "b c"], :tuple => (10, 20), :vec_tuple => [(1, 2), (3, 4)],
        :mat => [1 2; 3 4], :rational => 1 // 3, :complex => 1 + 2im, :nothing_val => nothing,
        :dict => Dict(:k => 1), :svec => SVector(1.0, 2.0),
    )
    cfg = SimulationConfig(ParamDict(vals...), create_method_dict(:m => create_param_dict(:scheme => "upwind")), [:m])
    back, path = roundtrip(cfg)
    bad = String[]
    for (k, v) in vals
        w = get(back.shared, k, :MISSING)
        ok = isequal(w, v) && typeof(w) == typeof(v)
        ok || push!(bad, "$k: $(repr(v))::$(typeof(v)) -> $(repr(w))::$(typeof(w))")
    end
    println("Type/value changes after the round trip:\n  ", join(bad, "\n  "))
    @test hash_of(back, :m) == hash_of(cfg, :m)
    println("hash equal: ", hash_of(back, :m) == hash_of(cfg, :m))
end

@testset "CSV round trip: lossy values (enums, structs, functions)" begin
    vals = Dict{Symbol, Any}(:enum => probe_upwind, :struct => ProbeOpts(1, 2.0), :fun => sin)
    cfg = SimulationConfig(ParamDict(vals...), create_method_dict(:m => create_param_dict()), [:m])
    back, _ = roundtrip(cfg)
    for (k, v) in vals
        println("  $k: $(repr(v))::$(typeof(v)) -> $(repr(back.shared[k]))::$(typeof(back.shared[k]))")
    end
    # The data-file hash is the same (val2str of the text equals val2str of the value), the solver gets text
    println("  hash equal: ", hash_of(back, :m) == hash_of(cfg, :m))
end

@testset "CSV round trip: sweeps, defaults, reference" begin
    cfg = SimulationConfig(create_param_dict(:N => 20, :sim_func_name => :solver),
        create_method_dict(:b => create_param_dict(), :a => create_param_dict(:x => 1), :analytical => create_param_dict()),
        [:b, :a, :analytical]; varied = create_varied_dict(:cfl => [0.2, 0.4], :scheme => ["u", "lf"], :Ns => [(10, 10), (20, 20)], :one => [5]),
        reference = :ref_factory, postprocess = nothing)
    back, _ = roundtrip(cfg)
    @test back.defaults == [:b, :a, :analytical]
    @test back.reference === :ref_factory && isnothing(back.postprocess)
    for k in keys(cfg.varied)
        @test isequal(back.varied[k], cfg.varied[k]) && typeof(back.varied[k]) == typeof(cfg.varied[k])
        isequal(back.varied[k], cfg.varied[k]) && typeof(back.varied[k]) == typeof(cfg.varied[k]) ||
            println("  sweep $k: $(repr(cfg.varied[k])) -> $(repr(back.varied[k]))")
    end
    @test Set(keys(back.methods)) == Set(keys(cfg.methods))
end

@testset "Hand-written CSV (spaces after the commas)" begin
    path = joinpath(mktempdir(), "hand.csv")
    write(path, """
    Category, Scope, Parameter, Value
    Simulation, Shared, N, 40
    Simulation, Config, defaults, [:upwind]
    """)
    res = try
        P.parse_csv_to_dict(path)
    catch e
        e
    end
    println("  parse result: ", res isa Exception ? sprint(showerror, res) : res)
    @test !(res isa Exception)
    path2 = joinpath(mktempdir(), "hand2.csv")
    write(path2, "Category,Scope,Parameter,Value\nSimulation, Shared, N, 40\n")
    res2 = P.parse_csv_to_dict(path2)
    println("  hand2 (spaces in rows only): ", res2)
    @test haskey(res2, "Simulation") && haskey(res2["Simulation"], "Shared")
end
