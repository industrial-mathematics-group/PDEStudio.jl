# _run_status wording and levels for RunSummary variants (no window)
using PDEStudio
a, b = create_param_dict(:a => 1), create_param_dict(:a => 2)
for (tag, s) in [("outdated", RunSummary(tasks = [a, b], cached = [a, b], postprocessing = Dict(:skipped => 1, :outdated => 1))),
                 ("empty", RunSummary(tasks = [a, b], ran = [a], empty = [b])),
                 ("no tasks", RunSummary()),
                 ("changed+outdated+failed", RunSummary(tasks = [a, b], cached = [a], failed = [b => "boom"], changed = [a],
                                                         postprocessing = Dict(:outdated => 1)))]
    println(rpad(tag, 26), PDEStudio._run_status(s, 0.42, 2))
end
