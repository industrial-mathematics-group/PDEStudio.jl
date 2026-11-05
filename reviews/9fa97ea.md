# Review: PDEStudio.jl — fixes of the third review (diff 4b8e1a9..9fa97ea) at 9fa97ea
Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

Fourth review (of the change set that addressed reviews/03e98ab.md). The two commits it found regressions in (40e6813, 3b58cb8) were reverted afterwards, which restores the state of those parts reviewed in reviews/03e98ab.md; the other findings are left open (see the pull request). Probes and outputs referenced below (`round4/ps/...`) are bundled in `reviews/9fa97ea/`.

## Scope

Read completely: `reviews/03e98ab.md` (findings 1–6 and minor issues), the full diff `4b8e1a9..9fa97ea` commit by
commit (src, tests, docs, CHANGELOG), the workspace/variant/project/repo `CLAUDE.md` files.
Read for context: `src/DataHandler.jl` (`_load_for_display`, `_load_snapshots`, `_select_snapshots`, `_time_axis`,
`_make_reference`), `src/ConfigIO.jl` (`_include_as`, `_run_bundled_sources`, `_relocate_sources`,
`load_and_apply_csv!`, `load_config_file!`), `src/PlottingUtils.jl` (`_pad_degenerate_range`,
`set_axis_limits_manager!`, `calculate_padded_axis_range`, `set_axis_styles!` tick formats / `scale_offset`), the
Resolution page validation (`src/UILogic.jl:1680`), the bundled-sources UI test (`test/runtests.jl:1164-1240`).
PDEStudioCore 0.4.0 (what the test env resolves; 0.4.3 has the same code): `convert_to_eulerian` (keeps the stored
times when the time resolution equals their count, slices time-only stats by `steps`), `resample_eulerian`,
`LSimData` constructor.

## Tests run

- Full suite at 9fa97ea under the lock (`DISPLAY=:99 PDESTUDIO_BROWSER_TESTS=true flock … timeout 60m julia -t 8
  --project=test test/runtests.jl`): **all pass**, 89 s wall. helpers 126/126, browser 9/9 (ran), plots-2 47 + 1
  broken (the known `@test_skip` for Core's built-in examples, Core 0.4.0), editors 473/473, plots-1 104/104, final 5/5.
  No warnings of note. Log: `round4/ps/suite.log`.
- **Do the new tests fail without their fixes?** Scratch copy with the old `src/` (4b8e1a9) and the new tests
  (`round4/ps/oldsrc/`, helpers group, under the lock): 10 failures, `round4/ps/oldsrc_newtests.log`:
  particle-on-grid times and values (2 × 2: lines 348/349), `set_resolution!(:t, 1)` / `(:x, 0)` throws (368/369), the
  CSV warning (376), the edited-original re-export (444), the 1e-7 / 1e-12 axis cases (506 × 2). Every fix has a test
  that catches its regression. Two assertions pass on the old code too: `length(d.stats[:mass]) == length(d.axes[2])`
  (Core slices time stats as well; a consistency check) and `get_resolution(:t) == r` at line 377 — passes on old code
  for the wrong reason: `r` is read *after* the old `set_resolution!(:t, 1)` succeeded, so `r == 1` (minor below).
- Probes (`round4/ps/`, `julia --project=test`, ≤ 4 threads):
  - `probe_particles_grid.jl` — particle data drawn on a grid, 1-D (nt = 4, 30, 80, 400) and 2-D (nt = 4, 50, 51,
    120, Float64 and Float32), non-uniform stored times, with an `analytical_solution` reference: shown times ⊂ stored
    times, count = min(nt, 50), first/last kept, values = the shown snapshot, reference time axis == data time axis
    and reference values at those times, `mass` over time sliced consistently (mass/t constant), element type kept;
    static particle data loads unchanged. **All 97 pass.**
  - `probe_res_csv.jl` — valid CSV resolutions (80, `1e3`) still applied, 1 and 2.5 warned and ignored (pass).
  - `probe_res1_space.jl` — finding 2. `probe_reexport_helper.jl` — finding 1. `probe_axis_threshold.jl` →
    `axis_threshold.png` (looked at it) — finding 3. `probe_missing_copy.jl` — finding 5.

## Findings

### 1. Re-export now bundles the *stale* copy of an included helper whose edited original is what actually ran — medium — CONFIRMED
- **Where:** `src/ConfigIO.jl:340-353` (`_relocate_sources`, 40e6813) together with `_run_bundled_sources`
  (`runs_as = origin`, line ~305) / `_include_as`.
- **What:** the commit's premise "the copy is what ran" holds for the file that returns the configuration, not for
  helpers it `include`s by relative path — the documented pattern (`include("helper.jl")` + `sources = [joinpath(@__DIR__,
  "helper.jl")]`, tested in `runtests.jl:1176-1240`). Every copy runs *as its original*, so after the helper copy ran,
  the config copy's `include("helper.jl")` runs the **original** helper, whose definitions win. If that original was
  edited after the export, the loaded configuration comes from the edited original, but 40e6813 now points the
  helper source at the copy (contents differ), so export 2 records the parameters of the edited code and bundles the
  old helper. Before 40e6813 (original preferred) this case was consistent.
- **Scenario/evidence:** `probe_reexport_helper.jl` (`helper_N() = 24`, exported, original edited to 25):
  new code: loaded export 1 runs N = 25, export 2 records N = 25 but bundles `helper_N() = 24`; with the originals
  gone, export 2 loads N = 24 (test fails). Old code (4b8e1a9): bundles 25, reloads 25.
  (The root cause is older: loading export 1 itself silently runs the edited helper, N = 25 although export 1
  recorded 24, so export 1 doesn't reproduce itself either.)
- **Fix:** decide per load, not per file: if every bundled copy has the content of its existing original, run them as
  the originals (as now); otherwise run all copies from the bundle folder (`runs_as = copy`, their relative includes
  then resolve to the bundled helpers) and make the copies the sources. That makes "the copy is what ran" true for
  includes and fixes the export-1 reproduction as well. Add the edited-helper case to the bundled-sources test.

### 2. Space resolution 1 is refused everywhere now, although PDEStudioCore asks for it — low — CONFIRMED
- **Where:** `src/PDEStudio.jl:226` (`set_resolution!`), `src/ConfigIO.jl:522` (CSV rows), 3b58cb8.
- **What:** the fix refuses `val < 2` for every dimension, but only a *time* resolution of 1 broke loading (review
  finding 5). For space, 1 is meaningful: Core's `convert_to_eulerian` throws "the particles have no extent along :y;
  use a resolution of 1 for that dimension" (`ConversionUtils.jl:113`). That advice could be followed from code or a
  CSV before; now it can't (the Resolution page already refused it, pre-existing). Saved CSVs with a space
  resolution 1 now load with a warning and a different resolution.
- **Evidence:** `probe_res1_space.jl` (2-D particles on the line y = 0.5): new code — `set_resolution!(:y, 1)` throws,
  data fails to load ("Could not load the data"); old code — loads `(200, 1, 50)`.
- **Fix:** require ≥ 2 only for the time axis (or allow ≥ 1 and handle `res[D] == 1` in `_load_snapshots` /
  `_make_reference` with `idx = [nt]`), and let the Resolution page accept 1 for space axes.

### 3. The 1e-6 threshold also flattens data the studio's own offset tick labels can resolve — low — CONFIRMED (PNG viewed)
- **Where:** `src/PlottingUtils.jl:536` (`calculate_padded_axis_range`, 0bcebe1), `set_axis_limits_manager!:298-307`;
  tick format with `scale_offset` at `src/PlottingUtils.jl:747-750`.
- **What:** the threshold is justified by Makie's *default* labels, but the studio has a `scale_offset` axis option
  that labels ticks as `1.0 + 5.0e-10`. With it set, a 1e-9 variation would be readable, yet it is drawn flat
  (panel 11 vs panel 12 of `axis_threshold.png`). Exactly the conserved-mass round-off use case the review named.
  Otherwise the threshold behaves as claimed: width 2e-6 and 1.2e-6 relative fill the axis with distinct labels;
  8e-7 and 1e-12 are flat with readable labels; negative data (−1 ± 1e-6), large (1e5 ± 0.2), around zero (±1e-9)
  and tiny magnitudes (1e-8 ± 1e-14) are correct; Float32 unchanged (100 eps(Float32) = 1.2e-5 > 1e-6).
- **Fix:** pass the tolerance from `set_axis_limits_manager!`: only `100 eps(precision)` when that axis has
  `scale_offset ≠ 0` or a custom `tick_format`, `max(…, 1e-6)` otherwise; mention `scale_offset` in the CHANGELOG
  entry as the way to see such variations.

### 4. Review finding 6 (`<empty>` after a Char literal `'"'`) not addressed nor mentioned — low — CONFIRMED (no change)
- **Where:** `src/UILogic.jl:987-1010` `_empty_literals` unchanged in this diff; no commit message, CHANGELOG or
  review note defers it. Niche; either fix (skip `'…'` Char literals outside strings) or note the deferral.

### 5. A missing bundled copy whose original ran is not a source of the loaded configuration — low — CONFIRMED (pre-existing)
- **Where:** `src/ConfigIO.jl:434-435` (`runs = … for i in eachindex(bundled) if !isempty(bundled[i])`).
- **What:** when the copy is missing, `_run_bundled_sources` runs the original, but the comprehension drops it, so a
  file returning the configuration isn't listed and the next export bundles nothing: the ps-b N1 "Closure" problem
  for this case. Predates 40e6813 but sits in the "missing files" logic it touched.
- **Evidence:** `probe_missing_copy.jl`: copy deleted, original present → `sources = String[]`, export 2 has no
  `bundled_sources`.
- **Fix:** take `origins[i]` when `bundled[i]` is empty and the original exists (it is what ran).

## Per-item status of the addressed review items (reviews/03e98ab.md)

- **1 OK** — particle data drawn on a grid shows its stored times on both paths (≤ and > the time resolution),
  values are the shown snapshot, references at exactly those times, time statistics (also per-particle fields)
  sliced with the snapshots, static particle data unchanged; 1-D/2-D, Float32/Float64 (`probe_particles_grid.jl`);
  `_stored_steps(::ESimData)` now also requires a time dimension (fixes static grids being mistaken for timed ones).
  Docs/CHANGELOG now accurate.
- **2 NOT OK (partly)** — correct for the file returning the configuration and for missing originals (tested), but
  wrong for helpers included by relative path, where the edited original is what ran (finding 1); the missing-copy
  case is still dropped (finding 5, pre-existing).
- **3 OK (with finding 3)** — the threshold works as stated and as the CHANGELOG says; it ignores the `scale_offset`
  labels that could resolve narrower ranges.
- **4 OK** — documentation only, as the review allowed; the cost, its cause and the remedy (raise the time
  resolution) are stated accurately in the CHANGELOG and `docs/src/rendering.md`.
- **5 OK (with finding 2)** — `set_resolution!` and CSV rows validated, test fails on the old code; over-broad for
  space axes.
- **6 NOT OK** — not addressed and not mentioned (finding 4).
- **Minor issues:** `git_dirty` docstring/CHANGELOG and the `_make_reference` docstring fixed (accurate). Not
  addressed (acceptable, all low): stale `domain.spacing` in `_select_snapshots` when the space resolution matches,
  UI text options losing surrounding spaces, component menu label `"1"`, `_csv_value_text` whole-file search, stale
  `stored_time_counts` keys.

## Test coverage

Every fix has a test that fails on the old code. Worth adopting:
- `probe_particles_grid.jl` (2-D particles, the `nt > res` 2-D path, references and time statistics of particle data
  on a grid; the suite covers 1-D without a reference) — ~15 s.
- `probe_reexport_helper.jl` once finding 1 is fixed (edited included helper), `probe_missing_copy.jl` for finding 5.
- `probe_res1_space.jl` once finding 2 is decided.

## Minor issues

- `test/runtests.jl:370`: `r = get_resolution(:t)` is read after the `@test_throws` lines, so with a regressed
  `set_resolution!` it captures the bad value and line 377 can't fail; read it first.
- CHANGELOG: the *Changed* entry names `set_resolution!` only; resolution rows of CSV files outside 2–100000 are now
  ignored with a warning too (a user-facing file format) — say so.
- CHANGELOG lines 62 and 113 exceed the file's ~120-column wrapping (cosmetic).

## Verdict

A careful, well-tested change set: the suite is green including the browser group, every new test fails without its
fix, and the particle-on-grid time axis (finding 1 of the last round) is now correct in 1-D/2-D, both paths, with
references and statistics. The axis threshold and the documentation of the load cost are accurate. Remaining: the
re-export rule picks the stale helper copy when an included helper's original was edited (medium, a regression for
that case), the resolution check is broader than needed and blocks Core's advised space resolution 1, the threshold
ignores the offset tick labels, and review finding 6 was silently skipped.
