# Probe: CSV round trip of simulation parameter values (headless)
using PDEStudio, Test, StaticArrays
PDEStudioCore.set_target_module!(Main)
roundtrip(cfg) = begin
    rows = PDEStudio._CSVRows(); PDEStudio._add_simulation_rows!(rows, cfg)
    path = joinpath(mktempdir(), "sim.csv"); PDEStudio._write_rows(path, rows)
    PDEStudio.csv_to_simulation_config(PDEStudio.parse_csv_to_dict(path)), read(path, String)
end
vals = Dict{Symbol, Any}(
    :missing_ => missing, :nothing_ => nothing, :sym_space => Symbol("a b"), :str_space => " lead", :str_nl => "a\nb",
    :str_quote => "\"q\"", :str_comma => "a, b", :str_empty => "", :str_emptytag => "<empty>", :str_Nothing => "Nothing",
    :dict32 => Dict{Symbol, Any}(:a => 1.5f0), :smat => SMatrix{2,2}(1.0, 2.0, 3.0, 4.0), :mvec => MVector(1.0, 2.0),
    :sv0 => SVector{0, Float64}(), :f32nan => NaN32, :f32neg => -0.0f0, :f16inf => -Inf16, :bigf32 => 3.4f38,
    :int32 => Int32(3), :uint8 => UInt8(7), :rational => 1//3, :cplx32 => ComplexF32(1, 2), :char => 'x', :bool => true,
    :vec_sym => [:a, :b], :empty_any => Any[], :tuple1_32 => (1.5f0,), :nt => (a = 1, b = 2.0), :range => 0.0:0.5:1.0,
    :str_num => "1e3", :str_sym => ":abc", :str_tuple => "(1, 2)", :str_true => "true", :float_round => 0.1 + 0.2,
    :neg_sv32 => SVector(-1.5f0), :sv_int => SVector(1, 2), :vec_vec32 => Any[Float32[1, 2]], :tuple_sv => (SVector(1.0f0), 1)
)
cfg = SimulationConfig(ParamDict(vals...), create_method_dict(:m => create_param_dict()), [:m])
back, txt = roundtrip(cfg)
h(c) = calculate_hash(get_clean_params(assemble_params(c.shared, c.methods, :m)))
@testset "csv values" begin
@testset "value $(k)" for k in sort!(collect(keys(vals)), by = string)
    v = vals[k]; b = get(back.shared, k, :__absent__)
    ok = isequal(b, v) && typeof(b) == typeof(v)
    ok || println("  $k: wrote ", repr(v), " ($(typeof(v))) -> read ", repr(b), " ($(typeof(b)))  | line: ",
                  first(filter(l -> occursin(",$k,", l), split(txt, '\n')), 1))
    @test ok
end
@testset "hash" begin
    @show h(back) h(cfg)
    @test h(back) == h(cfg)
end
end
