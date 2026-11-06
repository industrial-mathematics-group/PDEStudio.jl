# f3ed3a2: resolution rows of old/hand-written CSVs (0, 1, 2.5, 1e3, huge, negative, text, Bool), _spread_indices edges
using Test, PDEStudio
const P = PDEStudio
set_save_path!(mktempdir())
@testset "CSV resolution rows" begin
    for v in ("0", "1", "2.5", "1e3", "100000", "100001", "-5", "1e20", "99999999999999999999", "abc", "true", "Inf", "NaN")
        reset_manager!()
        csv = joinpath(mktempdir(), "res.csv")
        write(csv, "Category,Scope,Parameter,Value\nConfig,Resolution_Base,x,$v\n")
        parsed = try P.parse_csv_to_dict(csv)["Config"]["Resolution_Base"]["x"] catch e; e end
        res = try
            P.load_and_apply_csv!(csv); "x = $(P.get_resolution(:x))"
        catch e
            "THROWS $(sprint(showerror, e))"
        end
        println(rpad(v, 22), " parsed as ", repr(parsed), " (", typeof(parsed), ") -> ", res)
        @test !startswith(res, "THROWS")
    end
end
@testset "_spread_indices" begin
    for (n, k) in ((1, 1), (5, 1), (1, 5), (5, 5), (5, 2), (100, 3), (3, 100))
        println("_spread_indices($n, $k) = ", P._spread_indices(n, k))
    end
    @test P._spread_indices(5, 1) == [5] && P._spread_indices(1, 5) == [1] && P._spread_indices(5, 2) == [1, 5]
end
