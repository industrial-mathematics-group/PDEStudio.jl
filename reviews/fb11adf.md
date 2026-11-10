# Review: PDEStudio.jl — relaunch view, titles, run status (fb11adf)

Reviewer: Claude Opus 5.5 (Anthropic), new session without the generating conversation

## Scope

I reviewed `git -C $R/repo show fb11adf` (base c3e48d8) against PDEStudioCore a42a9e0, and checked the fallback against the registered PDEStudioCore 0.4.4. The review covers the three claims (relaunch view reset, fitted titles, run status), the tests, and the CHANGELOG and docs. R = `/home/agent/.claude/jobs/d2d299f1/tmp/review-qol1`. I made no edits to the repositories. The only repo-side change is the worktree `$R/old` (c3e48d8 with fb11adf's `test/runtests.jl`), used to check that the new tests catch the old code.

## Tests run

| Run | Result |
|:--|:--|
| `agent` group, `env -u DISPLAY`, env `$R/env` (Core a42a9e0) | 126/126 passed (`probes/test_agent.log`) |
| Full suite, `DISPLAY=:99` | All groups passed: helpers 196, agent 126, editors 476, plots-1 104, plots-2 67, top-level 6. The browser group was skipped (no node). Exit 0 (`probes/test_full.log`) |
| New tests against c3e48d8's `src/` (`$R/old`, env `$R/envold`) | 5 failures and 5 errors, so the tests catch the old behaviour (`probes/test_agent_old.log`) |
| Env with Core 0.4.4 (`$R/env044`) | Resolves and loads. I did not run the suite there, only probe p06 |

| Probe (`$R/probes/`) | What it checks | Result |
|:--|:--|:--|
| `p01_relaunch.jl` → `p01.log` | Relaunch cases A–G: the claim, same setup, other methods, other sweep values, step-by-step, `nothing` then config, particles | Claim holds (A, B, C, F, G). The step-by-step path still leaks (E) |
| `p02_titles.jl` → `p02.log`, `img/t_*.png` | Widths, `" | "` inside values, narrow plots, compare, Axis3, custom title, title size | Line count changes with slider values; values are split at their own `" | "` |
| `p03_anim_export.jl` → `p03.log`, `img/anim_w380_0{1,3}.png` | mp4 export over `scheme`, frames extracted with `Makie.FFMPEG_jll` | The plot jumps between frames |
| `p04_status.jl` → `p04.log` | Failed, empty and new runs, reference only, Run click | Wording and levels as designed (minor notes below) |
| `p05_glmakie.jl` → `p05.log`, `p05_noplay.log`, `p05_repeat.log` | Original reproducer on GLMakie, relaunch while *Play Anim* runs | Slider positions leak while the animation plays (reproduced on all 3 runs with the animation, not without it) |
| `p05_fixcheck.jl` → `p05_fixcheck.log` | Same, with `_reset_config_view!` moved after `reset_plotter!` | Leak gone |
| `p06_core044.jl` → `p06.log` | Core 0.4.4 fallback | `[ok] Simulation finished in 0.0 s (3 methods).` |
| `p07_width_docs.jl` → `p07.log` | `_text_width` against the fallback estimate; the agents.md example | text_bb works (195.8 vs 249.6 px); docs example output is wrong |
| `p08_inplace_jl.jl` → `p08.log` | Relaunch of the same config object mutated in place; `.jl` load into an open window | Both keep or scramble the old view |
| `p09_figresize.jl` → `p09.log` | Tall plot, slider changes the number of title lines | Figure height 1172 → 1202 → 1172 |
| `p10_camera_same.jl` → `p10.log` | Same-setup relaunch after `studio_view!` | Camera is not kept |

## Findings

### 1. Relaunch while an animation plays keeps the old slider positions (medium, CONFIRMED)
- **Where:** `src/MakiePlotting.jl`, `launch_plotter`: `_reset_config_view!()` runs *before* `reset_plotter!()`.
- **What:** The old window is still alive when the caches are cleared. Its animation timer is closed only inside `reset_plotter!`, and `close(screen)` yields on GLMakie. The timer fires in that gap, moves the old sliders, and `PlotData_Sync_Widget` writes `slider_cache`/`plot_cache` again. The param cache is keyed by slot (`:param_1`), so the advection `scheme` index 3 lands on the heat `r` slider. That is the bug class the commit claims to fix.
- **Evidence:** With *Play Anim* running, then `launch_plotter(test_heat_2d(); style = :heatmap)`:
  - `p05.log`, `p05_repeat.log`: `sliders=[(:r, 0.3), (:t, 0.05)]` on 3 out of 3 runs.
  - Without the animation (`p05_noplay.log`): `[(:r, 0.1), (:t, 0.0)]`.
  - With the reset moved after `reset_plotter!` (`p05_fixcheck.log`): `[(:r, 0.1), (:t, 0.0)]`.
- **Fix:** Compute `fresh = isnothing(old) || _view_setup(old) != _view_setup(config)` before, and call `fresh && _reset_config_view!()` right after `reset_plotter!()`.
- **Test:** In a GLMakie group: start *Play Anim*, call `launch_plotter(other_config)`, then check the default slider values.

### 2. The number of title lines changes with slider values, so plots jump, the window resizes and exported videos shift (medium, CONFIRMED; regression)
- **Where:** `_set_title!` / `_fit_title` (`src/PlottingUtils.jl`), called from `_handle_data_trigger!` and `_handle_ui_trigger!` on every slider move.
- **What:** Breaks are recomputed for each value, so `upwind` and `lax_friedrichs` give different line counts. Rows are `Fixed(p_h)` and the title is a protrusion, so the axis moves:
  - In the main window, `resize_to_layout!` in the UI trigger resizes the figure (the window on GLMakie) while the user scrubs or plays an animation.
  - During exports the resize is skipped (`is_exporting`), so the layout shifts inside fixed-size frames, and with more lines it moves towards the frame edges.
  - Before the commit the title was always one line, so its height never changed.
- **Evidence:**
  - `img/t_w340_upwind.png` vs `img/t_w340_lf.png`: the axis top moves about 15 px.
  - `p09.log` (`plot_height = 1000`): figure `(1154, 1172)` → `(1154, 1202)` → `(1154, 1172)` as the scheme slider moves.
  - `img/anim_w380_01.png` vs `img/anim_w380_03.png` (exported mp4): the axis moves down about 15 px, the 3-line title nearly touches the top, and "Position (X)" gets close to the bottom edge.
- **Fix:** Make the breaks stable per layout. Decide them once in the plot/layout trigger using the widest value each part can take (sweep values, formatted time range), and reuse the same break positions (by part index) in the data trigger. Alternatively, reserve the maximum line count.
- **Test:** Move a slider across values of different widths and assert that the axis viewport and the figure size don't change. Also check an animation export over such a slider.

### 3. The leak remains for configurations bound into an open window (medium, CONFIRMED; outside the commit's claim, but the old behaviour there is a real problem)
- **Where:** `set_sim_config!(::SimulationConfig)`, `set_sim_config!("file.jl")` / `load_config_file!` → `_bind_loaded_config!`, and *Files → Load* of a `.jl` file.
- **What:** `docs/src/index.md` presents `launch_plotter(); set_sim_config!(cfg); force_simulation()` as "the same step by step". Its `@plot` macro does the same. Both still open heat 2D as an x–t heatmap with a y slider, with `r` at the old slot's position. CSV loads that carry their own view are fine by design.
- **Evidence:** `p01.log` case E: `axes=(:x, :t) sliders=[(:r, 0.3), (:y, 0.0)]`. `p08.log` (`.jl` load): `axes=(:x, :t) sliders=[(:r, 0.25), (:y, 0.0)]`.
- **Fix:** Apply the same `_view_setup` comparison when binding a non-CSV configuration into an open window. Reset the caches *and* the live axis menus, then let a CSV apply its own view afterwards. At minimum, state in the docstring and docs that only `launch_plotter(config)` resets the view.
- **Test:** After an advection session, call `set_sim_config!(test_heat_2d()); force_simulation()` and also load a `.jl` file, then assert axes `x`/`y` and default sliders.

### 4. "Same setup" is checked against the bound object, which may have been mutated in place (low, CONFIRMED)
- **Where:** `old = manager.active_config` in `launch_plotter`.
- **What:** `cfg.varied[:N] = [50, 100]; launch_plotter(cfg)` compares `cfg` with itself, so the view is kept even though the sweep changed. The Sweep editor also mutates `active_config` in place. Because the param slider cache is keyed by slot, `cfl`'s cached 1.0 is applied to the new `N` slot (clamped to 50), and `cfl` falls back to 0.25. This contradicts the docstring ("other swept parameters than the bound one starts with its default view").
- **Evidence:** `p08.log`: `sliders=[(:N, 50), (:cfl, 0.25)]` (was `cfl = 1.0`).
- **Fix:** Store `_view_setup(config)` when binding in `set_sim_config!` (for example a `manager.bound_setup` field) and compare against that. Or key the param slider cache by parameter name.
- **Test:** As in the evidence: add a swept parameter in place, relaunch, and assert the defaults.

### 5. Titles are broken inside values that contain `" | "` (low, CONFIRMED)
- **Where:** `_fit_title` splits the joined title string on `" | "`.
- **Evidence:** `p02.log`, width 350 with a string sweep `tag = "a | b"`: `"Scheme = upwind | Tag = a\nb | Time (T) = 0.000"`. Also visible in `img/t_w50.png`.
- **Fix:** Have `generate_dynamic_title` return the parts, or fit on the parts before joining.
- **Test:** A string sweep with `" | "` in a value at a narrow width.

### 6. "PDEStudioCore 0.5" in CHANGELOG and overview doesn't match the version or the compat (low, CONFIRMED)
- **Where:** `CHANGELOG.md` (New: status line), `docs/src/overview.md` (status line).
- **What:**
  - Core a42a9e0 still has `version = "0.4.4"`.
  - PDEStudio's compat `PDEStudioCore = "0.4.4"` allows only 0.4.x, so a Core 0.5 could not be installed with this PDEStudio and the summary would never appear.
  - The version number is a release decision that hasn't been made.
- **Fix:** Write "with a PDEStudioCore that returns a `RunSummary`", or settle the version together with the compat bump in the release PR.

### 7. The agents.md example output is wrong (low, CONFIRMED)
- **Where:** `docs/src/agents.md`: `Status [ok]: Simulation finished in 0.1 s: 3 runs, 0 ran, 3 cached.`
- **Evidence:** The documented snippet gives `Simulation finished in 0.1 s: 6 runs, 0 ran, 6 cached.` (`p07.log`, `p01.log`). That is 2 numerical methods × 3 values of `r`.
- **Fix:** Correct the line.

## Test coverage

- The new tests catch the old code. Against c3e48d8's `src/` they fail at runtests.jl:1014, 1019, 1040, 1041 and 1046, and error at 1020, 1023, 1044, 1048 and the testset itself (missing `_fit_title` / `_run_status`). The test "same configuration keeps `cfl = 1.0`" passes on the old code too, which is expected.
- Gaps:
  - Relaunch during an animation (finding 1).
  - Layout stability of titles across slider moves and in exports (finding 2).
  - `" | "` inside values (finding 5).
  - `set_sim_config!` / `.jl` binding (finding 3).
  - A config mutated in place (finding 4).
  - A relaunch check on GLMakie: all relaunch tests are headless, and finding 1 only shows on GLMakie.
  - The status line with failures is only unit-tested through `_run_status`, not through a real Run (p04 shows the real path works).

## Minor issues

- **Launch status always says "0 ran, N cached":** `_prepare_for_config!` runs everything first, so the status reports only the second pass, including its time. A fresh launch says "0 ran" right after computing everything (p04 "flaky launch": `0 ran, 1 cached, 1 failed`). Failing tasks also run twice at launch; that predates this commit. Consider reporting the summary of the prepare run on launch.
- **"without output" stays at level `:ok`** (p04 "empty launch"), although those slider positions show nothing. `:warn` would fit better.
- **Reference-only configurations** report `0 runs, 0 ran, 0 cached.` (p04). Something like "no numerical runs" would read better.
- **Docstring overclaims the camera:** "launching the same setup again keeps the view of the last window", but a locked camera / `studio_view!` view is not kept, because `reset_plotter!` unlocks it (p10: limits `(0.2, 0.4)` → `(0.0, 1.0)`). List what is kept (axes, sliders, comparison).
- **Orphaned comment:** in `MakiePlotting.jl` the new functions were inserted between `_prepare_for_config!`'s comment ("Runs `config` (cached) and sets the data kind…") and the function, so that comment now sits above `_view_setup`.
- **Custom titles in `studio_state`:** the `"\n" => " | "` replacement also rewrites user-entered multi-line custom titles. Harmless.
- **SIGNOFF.toml:** the new annotation declares `AI-Review = "A2"` "reviewed in reviews/" before a `reviews/fb11adf*` exists.
- **Clearing `manager.methods.val` is safe:** I found no problems. The window is rebuilt and `set_sim_config!` notifies with the new methods. Legend order is kept (`p01` C: `[:fd_b, :fd_a]`), and the Methods tab and editor pages are rebuilt (`editor_view` is emptied by `reset_plotter!`).
- **Everything else I checked works:** compare-mode labels (single part, untouched), Axis3 titles, custom titles (kept as entered), the title-size option (fitted at the UI size), `@launch`, `nothing` then a config, and the Lagrangian/Eulerian switch.

## Verdict

The three claims hold as stated for `launch_plotter(config)`, the title text and the status line. The Core 0.4.4 fallback works and the full suite passes. Two medium problems should be fixed before merging:
- **Finding 1** is a one-line reorder.
- **Finding 2** is a regression: plots and the GLMakie window jump while scrubbing, and exported animations shift between frames.

Finding 3 should at least be documented, or handled the same way when a configuration is bound into an open window.

Counts: high 0, medium 3, low 4, plus 8 minor issues.
