# Review: PDEStudio.jl — open findings of reviews/9fa97ea.md and reviews/03e98ab.md, default resolutions (a515df4..f3ed3a2) at f3ed3a2
Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

Fifth review, of the single commit f3ed3a2. It addresses findings 1–5 and the minor issues of `reviews/9fa97ea.md` and findings 2, 5, 6 of `reviews/03e98ab.md`, and changes the default space resolutions to 100 (data) / 200 (references), as the owner decided. The owner also chose the rule for bundled sources (an export runs as exported); this review checks how it is implemented, not the rule itself. Probes and outputs referenced below (`probes/...`) are in the review folder next to this report.

## Scope

Read completely: `reviews/9fa97ea.md`, `reviews/03e98ab.md` and their probes, the full diff of f3ed3a2 (src, tests, docs, CHANGELOG, AIDECL), the workspace/variant/project/repo `CLAUDE.md` files.

Read for context:
- `src/ConfigIO.jl`: `_include_as`, `_run_bundled_sources`, `_relocate_sources`, `load_config_file!`, both methods of `load_and_apply_csv!`, the bundling in `save_params_to_csv`.
- `src/UILogic.jl`: `_handle_load`, `_load_key`, `_empty_literals`, the Resolution page, the animation guards.
- `src/DataHandler.jl`: `_load_snapshots`, `_select_snapshots`, `_make_reference`, `_reference_particles_at`, `_with_spacing`, `_uniform_axis`, `_allow_dims_of!`.
- `src/PlottingUtils.jl`: `set_axis_limits_manager!`, `calculate_padded_axis_range`, the tick formats of `set_axis_styles!`.
- Docs: `docs/src/file_ops.md` (bundled sources, loading), `docs/src/index.md`, `docs/src/rendering.md`.
- The bundled-sources UI test (`test/runtests.jl:1239-1310`).
- Git history of the bundle format: `dce3990` wrote `<export>_source_<i>.jl` with `source_origins`; `ba752bf` introduced `<export>_sources/<file>`.

## Tests run

- **Full suite** at f3ed3a2 under the lock (`DISPLAY=:99 flock /tmp/julia-suite.lock timeout 60m julia -t 8 --project=test test/runtests.jl`): **all pass.** Log: `probes/suite.log`.
  - helpers 144/144 (29.7 s)
  - plots-2 47 + 1 broken, the known `@test_skip` for Core's built-in examples (60.9 s)
  - editors 473/473 (73.5 s)
  - plots-1 104/104 (83.0 s)
  - final 5/5
  - browser skipped (no node; the 1 broken is the skip marker)
- **Do the new tests fail without their fixes?** Yes. A scratch copy with the old `src/` (a515df4) and the new tests (`probes/oldsrc/`, groups helpers and editors under the lock): helpers 12 failed + 4 errored, editors 1 failed (`probes/oldsrc_newtests_helpers.log`, `…_editors.log`). Failing on the old code:
  - time resolution 1 (the data is `nothing`);
  - `set_resolution!(:x, 0)` and `set_resolution!(:x, 100_001)` don't throw;
  - the 100/200 defaults, also the ↺ row of the editors test;
  - the CSV row 2.5 (`InexactError` on the old code);
  - the bundled-sources testset: with the edited helper, export 2 bundles `helper_N() = 24`; the missing copy isn't re-bundled; `source_note` doesn't exist;
  - the `_raw_text(Any['"', ""])` round trip;
  - `fine_labels` (unknown keyword).

  So every fix has a test that catches its regression. Three assertions pass on the old code too and are only guards: `get_resolution(:y) == 1`, `_empty_literals("Any['\\'', <empty>]")` and `"x' * <empty>"` (neither string contains `"`).
- **Probes** (`probes/`, `julia --project=test`, ≤ 4 threads, temp save paths):

| Probe | What | Result |
|:--|:--|:--|
| `probe_bundle_cases.jl` (new code; `…_oldsrc.out` on a515df4) | A: 9fa97ea `probe_reexport_helper` (edited included helper); B: 03e98ab `probe_reexport_origin` (edited top-level file) + 2nd/3rd generation with export 1 deleted; C: helper included but not listed; D: data file read via `@__DIR__`; E: originals moved / one original deleted; F: copy missing + helper edited; G: file ending with a function; H: older `<export>_source_<i>.jl` exports; I: symlinked original; J: CRLF; K: absolute source path | A, B, E, G pass and fail on the old code (the findings are fixed). **C, D, H fail on the new code and pass on the old one** (finding 1). I fails on both (finding 5). F gives a misleading note (finding 4). J: CRLF counts as an edit (conservative, fine). K: see `probe_status_line.jl` |
| `probe_status_line.jl` | `_handle_load` status text and colour; a `.jl` loaded after it; K over two generations | the note is shown in warn colour (OK); **stale note after the `.jl` load** (finding 2); **K: export 2 alone runs the edited helper** (finding 3) |
| `probe_res1_ui.jl` → `res1_png/*.png` (viewed) | time resolution 1 in the window: grid data + reference, solution and `l2error` over time, x–t heatmap, compare over time, static and mp4 export, Play Anim; particle data in a grid style and in a particle style with a reference; space resolution 1 (lines, heatmap x–t) | no crash. Data and reference at t = 2.0 (the last snapshot), correct curves; the x–t heatmap has one row; compare over time gives 1 subplot; the static export is written; animation and Play Anim are refused with "Slider has no range to animate" (no file). Particles: the grid style shows t = 1.0 (the last snapshot); the particle style shows all 11 stored times with the reference at t = 1.0, as documented. Space resolution 1: x = [0.0], the x–t heatmap is correct. A one-point line (anything drawn over time) draws nothing (minor) |
| `probe_res1_space.jl` (9fa97ea) | 2-D particles on a line, `set_resolution!(:y, 1)` | loads `(100, 1, 3)` (OK) |
| `probe_res_csv.jl` (9fa97ea), `probe_res_csv2.jl` | CSV resolution rows 0, 1, 2.5, 1e3, 100000, 100001, −5, 1e20, 99999999999999999999, abc, true, Inf, NaN | all warned and ignored, or applied, as expected, **except 1e20 and the Int128 value: `InexactError`, so the whole load fails** (finding 6). `true` is taken as 1 |
| `spread_indices.out` | `_spread_indices` edge cases (1,1), (5,1), (1,5), (5,5), (5,2), (100,3), (3,100) | `[1] [5] [1] [1..5] [1,5] [1,50,100] [1,2,3]` (OK) |
| `probe_fine_labels.jl` → `fine_png/*.png` (viewed) | the real window with data `1 + 1e-9 sin` on `x = 1 + 1e-9 k`: default; y `scale_offset`; x and y `scale_offset`; custom y `tick_format` `{:.12f}` and `{:.2f}`; log y + `scale_offset` | the default is flat (2e-3 wide). `scale_offset` resolves y (2.1e-9) and x (4.9e-8) independently. Log scale unchanged (only the linear branch uses the flag). **`{:.2f}` also fills the axis, every label reads "1.00"** (finding 7) |
| `probe_char_literals.jl` | `_empty_literals` with `'"'`, `'\''`, `'\\'`, `'\u00e9'`, `'é'`; adjoints `x'`, `A'`, `[1 2]'`, `(x)''`; Chars inside strings; unterminated `'`; `f('"')`; `? '"' :`; `in '"'`. `_raw_text`/`_parse_raw` round trips, including `'"'` next to a literal `"<empty>"` | all correct except `a in '"'`: a keyword before a Char is taken for an adjoint (minor; `_raw_text` never produces it) |
| `probe_missing_copy.jl`, `probe_particles_grid.jl` (9fa97ea), `probe_time_display.jl` (03e98ab) | regressions of the earlier fixes | all pass. `probe_time_display.jl` now needs `set_resolution!(:x, 200)`: with the new default 100 its N = 200 grid is resampled, so its exactness check no longer applies (expected) |

## Findings

### 1. Bundle mode breaks exports that use files not in the bundle (unlisted includes, data files, older exports) once any original changed — medium — CONFIRMED
- **Where:**
  - `src/ConfigIO.jl:308-327`: `as_originals`, and `runs_as = isempty(copy) || as_originals ? origin(i) : copy`.
  - Docs: `docs/src/file_ops.md:47-49, 62-63`, `docs/src/index.md:160`, CHANGELOG lines 26-31.
- **What:** if any bundled copy differs from its original, every copy runs from `<name>_sources/`, so `@__DIR__` and relative `include`s resolve there. Anything the code reads next to the original that isn't a listed source is then missing, and the code fails: the parameters come from the CSV and the solvers are undefined. Three cases:
  - (a) Helpers included but not listed in `sources`. This is the default: `load_config_file!` adds only the file itself, and the suite's own UI test uses such a config (`runtests.jl:1245-1256`).
  - (b) Data files read relative to `@__DIR__`, which rule 4 of the docs recommends ("keep them with the configuration").
  - (c) Older exports in the `<export>_source_<i>.jl` format (dce3990, which records `source_origins`), whose included helper has a different name in the bundle.

  On a515df4 all three loaded, because the copies ran as the originals while the originals' folder existed. Now, editing any listed file makes the old export fail, including the configuration itself, which is the usual thing to do after an export. Neither the CHANGELOG nor the docs say so. Rule 4 and the index sentence "the exported copies run and become its sources, so the export reproduces itself" are now inaccurate for these configurations.
- **Evidence:**
  - `probe_bundle_cases.out`, case C: after editing `config.jl` (with an unlisted `helper.jl`), the failures are `["config.jl: SystemError: opening file \"…/exp_sources/helper.jl\"…"]`.
  - Case D: after editing a `cfg.jl` that reads `n.txt`: `"…/exp_sources/n.txt": No such file`.
  - Case H: an old-format export with an edited helper: `exp_source_2.jl: SystemError … helper.jl`.
  - `probe_bundle_cases_oldsrc.out`: C, D and H load without failures on a515df4.
- **Fix:** keep the rule, but make the bundle run complete. Options:
  - Run in bundle mode first. If a file fails and the originals' folders exist, run again as the originals (the a515df4 behaviour) and say so in the note ("X is not bundled: ran next to the originals").
  - More precise: run the copies as their originals, but redirect `include`s of *listed* originals to their copies (e.g. via the `mapexpr` of `include_string`, or by putting the copies into a temporary copy of the original folder). Unlisted helpers and data files keep working, and listed helpers run as exported.
  - At the least, document that in bundle mode only listed sources are found: change rule 4 and the index sentence, and add it to the CHANGELOG entry.
- **Test:** cases C and D of `probe_bundle_cases.jl` (unlisted helper / data file, original edited) in the bundled-sources testset.

### 2. The source note stays after loading a `.jl` file, so the status line blames an unrelated file — low — CONFIRMED
- **Where:** `src/UILogic.jl:410-422` (`_handle_load`) reads `manager.source_note`. Only `_run_bundled_sources` resets it; `load_config_file!` (`src/ConfigIO.jl:394`) doesn't.
- **Evidence:** `probe_status_line.out`: after loading an export with an edited helper, loading `other.jl` shows, in the warn colour: "Loaded other.jl (helper.jl changed since the export: the exported version ran). Run Simulation to apply it."
- **Also:**
  - In the structural branch (more sliders or dimensions) the note is never shown.
  - Loads from code (`set_sim_config!("exp.csv")`) only log "Executing bundled source: cfg.jl", with no hint that the exported version ran instead of the originals.
- **Fix:** set `manager.source_note = ""` in `load_config_file!` (or at the top of `_handle_load`). Log the note with `@info`/`@warn` in `_run_bundled_sources`, and add it to the structural status.

### 3. In bundle mode, sources listed by absolute path stay the (edited) originals, so a re-export doesn't reproduce — low — CONFIRMED
- **Where:** `load_and_apply_csv!` calls `_relocate_sources(bundled_config.sources, bundled, origins)` (`src/ConfigIO.jl:358`), which keeps every file that exists.
- **What/Evidence:** `probe_status_line.out`, case K: `sources = ["/abs/helper.jl"]`, and the helper is edited after the export.
  - Load 1 runs N = 24, which is correct. But its sources are `[/orig/helper.jl (edited), …/exp_sources/helper.jl, …/exp_sources/config.jl]`.
  - Export 2 bundles `helper.jl` (the edited one, 25), `2_helper.jl` (24) and `config.jl`.
  - With the originals gone, export 2's `include("helper.jl")` runs the edited helper: **N = 25**.

  The docs discourage absolute paths (rule 2), hence low.
- **Fix:** in bundle mode, map a source found in `origins` to its copy before the `isfile` check (pass `as_originals` out of `_run_bundled_sources`).

### 4. Copy missing + another original edited: the note says the exported version ran, but the edited one did — low — CONFIRMED
- **Where:** `src/ConfigIO.jl:307-327`: a missing copy runs as its original, the others run from the bundle.
- **Evidence:** `probe_bundle_cases.out`, case F (`exp_sources/config.jl` deleted, `helper.jl` edited 24 → 25): N = 25, with the note "helper.jl changed since the export: the exported version ran". The original `config.jl` ran in its own folder, so its `include("helper.jl")` ran the edited helper after the bundled one. The sources then hold both helpers.
- **Fix:** either name the missing file in the note too ("config.jl is missing from the bundle: its original ran"), or run the missing file's original from the bundle folder (`runs_as` = the would-be copy path) so its includes find the bundled helpers. Rare: it needs someone to delete a file from the bundle.

### 5. A symlinked source is bundled as a symlink, so the "snapshot" follows the original and the comparison always says "unchanged" — low — CONFIRMED (pre-existing export behaviour)
- **Where:** `save_params_to_csv` calls `cp(src_path, dst_path; force = true)` (`src/ConfigIO.jl:827`). Julia's `cp` copies links as links by default (`follow_symlinks = false`).
- **Evidence:** `probe_bundle_cases.out`, case I: `exp_sources/config.jl` is a symlink. After the helper is edited through the link, the export loads N = 25 with no note; the new rule can't see the change. A relative link would be dangling in the bundle, so the copy would count as missing.
- **Fix:** `cp(src_path, dst_path; force = true, follow_symlinks = true)`.

### 6. CSV resolution rows with huge integer values still throw and abort the load — low — CONFIRMED
- **Where:** `src/ConfigIO.jl:536-543`: `n = v isa Real && isinteger(v) ? Int(v) : nothing` runs `Int(v)` before the range check.
- **Evidence:** `probe_res_csv2.out`: `1e20` gives `InexactError: Int64(1.0e20)`, and `99999999999999999999` (parsed as Int128) also gives `InexactError`. `load_and_apply_csv!` throws, so the whole file fails instead of one row being warned and ignored. `true` is accepted as 1 (harmless).
- **Fix:** `n = v isa Real && !(v isa Bool) && isinteger(v) && 1 <= v <= MAX_RESOLUTION ? Int(v) : nothing`.

### 7. Any custom `tick_format` counts as "fine labels", including coarse ones — low — CONFIRMED (PNG viewed)
- **Where:** `_fine_labels` (`src/PlottingUtils.jl:550`).
- **What:** the threshold now trusts any non-default `tick_format`. With a format such as `"{:.2f}"`, a 1e-9 variation fills the axis and every tick reads "1.00", which is the symptom the 1e-6 threshold exists to avoid. The CHANGELOG says "(those labels show them)". For `scale_offset` this holds: the offset labels resolve both axes independently (`fine_png/x and y scale_offset.png`), and log scales are unaffected.
- **Evidence:** `probe_fine_labels.out` and `fine_png/y tick_format {:.2f} (coarse).png`.
- **Fix:** count only `scale_offset`, or word the docstring and CHANGELOG as "a custom tick format (which then has to show enough digits)".

## Per-item status of the addressed findings

reviews/9fa97ea.md:
- **1 OK (with findings 1, 3, 4).** The edited-included-helper case is fixed: the exported helper runs, the copies are the sources, export 2 bundles `helper_N() = 24`, and it reloads with N = 24 without the originals (probe A, the 9fa97ea probe adapted). An edited top-level file and second/third generations also work (B, G), as do moved originals (E). This holds only when everything the code needs is a listed source (finding 1).
- **2 OK.** Space resolution 1 is accepted by `set_resolution!`, CSV rows and the Resolution page. Flat particles load `(100, 1, 3)`, and grid data at x resolution 1 draws correctly.
- **3 OK (with finding 7).** Correct for `scale_offset` on x and y, at both call sites; log scale untouched. `calculate_padded_axis_range` has no other callers.
- **4 OK.** Char literals with escapes, unicode and `'"'` are skipped; adjoints and Chars inside strings are handled; an unterminated `'` doesn't crash. Only `in '"'` (a keyword before a Char) is misread (minor).
- **5 OK.** A missing copy whose original exists runs, becomes a source, and the next export bundles it (tested). The note is misleading in the mixed case (finding 4).
- **Minor issues:** OK: the test now compares with constants (`set_resolution!(:x, 200)` up front), and the CHANGELOG names the CSV rows. Not addressed (cosmetic): the CHANGELOG lines over 120 columns.

reviews/03e98ab.md:
- **2 OK (with findings 1, 3).** The 03e98ab `probe_reexport_origin` passes: export 2 bundles `:version => 1`, which is what ran.
- **5 OK.** Time resolution 1 shows the last stored snapshot for grid data, particle data on a grid and references. Statistics, compare over time and the x–t heatmap work. Animation and Play Anim are refused with a warning; the static export works (`probe_res1_ui.out`, PNGs viewed).
- **6 OK.** See 9fa97ea 4.

**Default resolutions 100/200:** applied everywhere: `_sync_resolution_dims!`, the `get_resolution` fallback, the ↺ "default" of the Resolution page, the docstring and the CHANGELOG. No doc still says 200/400. The suite was adapted (`set_resolution!(:x, 200)` for the exactness test; the ↺ row expects 100).

## Test coverage

Each fix has a test that fails on a515df4 (see Tests run). Not covered:
- unlisted helpers and data files with an edited original (finding 1; probe cases C, D);
- the status text of `_handle_load` with a note, and its reset (finding 2): the tests only check `manager.source_note`;
- time resolution 1 for particle data on a grid and for Lagrangian references (both work, see `probe_res1_ui.jl`), and the refusal of animation/Play Anim at one time point;
- older `<export>_source_<i>.jl` exports with `source_origins` (case H).

## Minor issues

- `src/UILogic.jl:1668`: the comment "Points per dimension the studio resamples to; …" stayed behind after `_default_resolution` moved to `src/PDEStudio.jl`, and now documents nothing.
- Note text: "the original sources are gone" appears also when only one of several originals is gone and the others are unchanged (probe E, helper deleted). Files with the same basename are listed twice.
- `_char_literal_start`: a keyword before a Char (`a in '"'`, `return '"'`) is taken for an adjoint. `_raw_text` never produces this; it only affects hand-typed input.
- `_default_resolution` checks `dim === :t`. A time axis with another name (`:iteration`) gets 100/200 from the Resolution page's "default"/↺ and from the `get_resolution` fallback, but 50/100 from `_allow_dims_of!` (`src/DataHandler.jl:62`). Pre-existing.
- With time resolution 1, anything drawn over time is a single point, and `lines` draw nothing for it (empty axis in `res1_png/grid_t1_l2error_t.png`). Expected, but worth a sentence in `docs/src/rendering.md` next to "a time resolution of 1 shows the last snapshot", together with the refused animation.
- Comparison cost: each copy and its original are read in full up to twice (`unchanged` runs for `as_originals` and again for `edited`). Negligible for source files. A CRLF conversion of an original counts as an edit (probe J), which is conservative and fine.
- `docs/src/rendering.md:49` now runs to about 170 columns; the rest of the paragraph is wrapped at 120.

## Verdict

A focused commit with good tests: the suite is green, and every fix has a test that fails on the old code. The reported bundled-sources cases are fixed: an edited included helper or top-level file, second and third generations, moved originals, missing copies, and files that end with a function. Time resolution 1 now works across the window (grid data, particles on a grid, references, statistics, compare, exports). Space resolution 1 is allowed again, `scale_offset` labels resolve small variations, and Char literals no longer break `<empty>`.

The main problem is that the new bundle mode only finds listed sources (medium). Configurations that include unlisted helpers (the default when loading a `.jl` file) or read data files next to themselves, and older exports, now fail to load once an original is edited; on a515df4 they loaded. The rest are smaller: a stale status note, absolute-path sources in a re-export, a misleading note in the mixed missing-copy case, symlinked sources, an overflow in the CSV row check, and coarse custom tick formats.

Counts: 0 high, 1 medium, 6 low (all CONFIRMED); 7 minor issues.
