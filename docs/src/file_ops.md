## Deep Dive: File Operations & Execution

The **Files** tab (name / path and description boxes, loading, export, presets) and the execution buttons below the tabs handle serialization and execution. Because PDE simulations and 3D graphics can be computationally heavy, this region works with a lock system that keeps the UI responsive.

### 🚦 The Reactive State Machine (Triggers & Locks)

To keep the Makie rendering engine from stuttering while the backend computes, the studio uses hierarchical locks: **Simulation → Layout → Plot**.

The three execution buttons (`Run Simulation`, `Apply Layout`, `Update Plot`) are your traffic lights:

*   **Green (Synced):** The plot matches the backend data and your UI settings.
*   **Yellow (Pending Action):** You changed something, and the studio waits for you to confirm it with a click on the yellow button.
*   **Coral / Red (Locked):** A higher-priority action is required first. For example, after changing a physics parameter, `Apply Layout` and `Update Plot` stay locked until you click `Run Simulation`.

Simulations that already exist on disk (same parameters, same hash) are loaded instead of recomputed.

### 📂 Loading a Saved State

In the **Files** tab, choose the file with **Browse…** (the system's file dialog; in a browser, an upload), type its path into the **Name / path** box and click **Load**, or drop it anywhere onto the window; the status line reports the result. A bare file name is enough: the studio searches the working directory, the `figures` and `animations` folders of the figure path and of the save path, the preset folders and `./Experiments` (each including one level of subfolders; a name without extension means a CSV). The same works from code: `set_sim_config!("my_run.csv")`, `set_sim_config!("configs/euler2d.jl")`.

Two kinds of files can be loaded:

*   **CSV files** (exports and presets): values only, parsed safely. This is the preferred way: a CSV without bundled source files never runs code.
*   **Julia files** (`.jl`) whose last expression is the `SimulationConfig`, or a function without arguments that returns it. The file runs in the target module (`set_target_module!`) and becomes the last of the configuration's `sources` (moved there if the configuration lists it elsewhere): runs include it after the helper files, so it may use and override what they define, and exports bundle it.

> **⚠️ Code execution:** loading a Julia file, or a CSV that bundles source files (see below), **runs that code with your rights**. Only load files you trust. In the studio, such a file needs a second click on **Load**: the first one only shows the warning in the status line. The second click confirms that file as it was at the first one: the file itself and, for a CSV, the bundled copies it names; another file under the same name (a new upload) or a change of these files in between asks again. Files the code includes (`include("helper.jl")`) and the originals a CSV runs instead of its copies are **not** covered: a change of those between the two clicks runs without a new warning.

The load button turns **green** when the file was read; press *Run Simulation* to compute and show it.

**File dialog:** *Browse…* uses the tools the operating system brings: AppleScript on macOS, PowerShell on Windows, `zenity` or `kdialog` on Linux (GNOME, KDE and most desktops install one of them; otherwise install `zenity`, or type the path or drop the file). `PDEStudio.FILE_DIALOG[]` can be replaced by any function returning a path.

**In a browser (WGLMakie):** *Browse…* opens the browser's own file picker, and files can be dropped onto the studio; both **upload** the file to the computer running Julia, so a studio served from a remote compute node loads configurations from your own computer. The files are stored under `<save path>/Uploads/<name>/` and loaded like the *Load* button (files that run code ask for the second click). Choose (or drop) the files that belong together at once: a CSV **with the files of its `<name>_sources/` folder**, or a Julia file with the helpers it includes relative to `@__DIR__`; they are stored next to each other, where the loader finds them. Uploads are limited to 20 MB per file. If the browser doesn't open the picker right away (it only does so shortly after a click), a small panel asks for one more click on *Choose file…*.

If the file needs more parameter sliders or other physical dimensions than the open window has, the buttons turn **orange**: the configuration is staged, and the next click on *Run Simulation* rebuilds the whole window with the new limits, applies the file and runs it. (Save your current look as a preset first if you want to keep it.) Without an open window, the limits are applied directly.

### 🧩 Config Files and Bundled Sources

A configuration that comes from a Julia file (listed in its `sources`, which loading a `.jl` file does by itself) is
**bundled with every export**: the files of `sources` are copied into `<name>_sources/` next to the exported CSV,
under their own file names. Loading that CSV runs the copies again to restore the solvers:

*   **the export runs as it was exported:** the copies run, also if an original was edited since. The status line
    names originals that were edited or are gone;
*   the copies run **as if they were the original files**: `@__DIR__` and relative `include`s find the files next to
    the originals (helpers that aren't in `sources`, data files), and an `include` of a file in `sources` (also
    `include(f, path)`, `Base.include`, `foreach(include, files)`; not in default values of function arguments, or
    when a macro passes `include` on) runs its bundled copy. Files that aren't in `sources` are not bundled, so they
    run as they are now, and are missing if the originals' folder is gone. A copy keeps running in place of its
    original (also after you edit it) until a `.jl` file is loaded;
*   the configuration's sources are the originals that are unchanged and the copies of the others: *Run Simulation*
    includes them again in the same way, and a new export bundles them (recording the originals), so it reproduces
    the old one. (With PDEStudioCore versions before `run_all_simulations(...; load_sources = false)`, *Run
    Simulation* includes the sources as they are: once an original was edited or is gone, all copies are the
    sources, and they run from `<name>_sources/`, where only bundled files are found. An `include` by absolute path,
    or of the original of a missing copy, then runs the edited original.);
*   a missing copy is replaced by its original, if that still exists (and the original becomes a source);
*   if a copy fails, the load does not stop: the **parameters come from the CSV**, and the status line names the file
    and the error. *Run Simulation* includes the sources again, so restore what the file needs (e.g. a missing helper)
    and load the export again, or remove the file from the sources (*Advanced* tab) and define the solvers otherwise
    (e.g. by loading their package).

Configuration files that reload reliably, from the studio and from any bundled copy:

1.  **End with the configuration:** the last expression is the `SimulationConfig`, or a function without arguments
    that returns it (`() -> SimulationConfig(...)`); nothing interactive (no `launch_plotter()`, no `display`).
2.  **No absolute paths:** include helper files relative to the file (`include("solvers.jl")` or
    `include(joinpath(@__DIR__, "solvers.jl"))`) and list them in `sources` too
    (`sources = [joinpath(@__DIR__, "solvers.jl")]`), so they are bundled with it.
3.  **Solvers in a package** are the most robust: `using MySolvers` at the top, and the bundled file only holds the
    configuration. Packages must be installed in the environment that loads the file.
4.  **Data files** (meshes, initial conditions) are read relative to `@__DIR__` and are not bundled; keep them with the
    configuration (an export finds them there while that folder exists) or in a package.
5.  **Post-processor, reference and statistics too:** an export records only their names, and the statistics are
    global (not part of the configuration). Define the post-processor, the reference, custom statistics
    (`register_stat!` + `calc_stat`) and the `set_stat_preset!` call in a file of `sources`, or in a package.

An export checks this: solvers, reference, post-processor and statistics defined neither in a file of `sources` nor
in a package (e.g. in the REPL, or in a script that isn't a source) are named in the status line and the log, and
recorded in the CSV (`Metadata, General, code_outside_sources`): the export can't run them elsewhere. The CSV also
lists the registered statistics (`statistics`); loading it warns about the ones the session doesn't register
(after its bundled sources ran).

```julia
# configs/advection.jl
using PDEStudio
include("solvers.jl")                    # defines advection_1d (relative to this file)

SimulationConfig(create_param_dict(:N => 100, :cfl => 0.5, :sim_func_name => :advection_1d),
                 create_method_dict(:upwind => create_param_dict(:scheme => "upwind")), [:upwind];
                 varied = create_varied_dict(:cfl => [0.3, 0.5]),
                 sources = [joinpath(@__DIR__, "solvers.jl")])   # bundled with exports, too
```

### 💾 Exporting (Images & Animations)

The **Name / path** box is also the gateway for saving your work. Exports land in `<figure path>/figures` (static frames; with the export option `create_savefolder`, in a subfolder per name) and `<figure path>/animations`. A path in the name (`study/run_1`, or an absolute path) is honoured.

The figure path is the save path of the data unless [`set_figure_path!`](@ref) sets another folder. When the data lies on a remote machine, e.g. a server drive mounted locally and given to `set_save_path!`, this keeps figures, animations and snapshots on your own computer while the cached runs stay on the server:

```julia
set_save_path!("/mnt/cluster/results")   # the data
set_figure_path!("~/Pictures/study")     # figures, animations, snapshots
get_figure_path()                        # where exports go now
set_figure_path!()                       # back to the save path
```

**The Direct Format Trick:**
By default, **Export** saves the figure in every format listed in the export setting `save_formats` (*Files → Settings ›*, usually `png`). Typing an extension into the filename bypasses that list:
*   **Static formats** (`png`, `jpg`, `jpeg`, `pdf`, `svg`, `eps`): `my_figure.svg` exports exactly that one file.
*   **Animations** (`mp4`, `webm`, `mkv`, `gif`): select a variable in the **Anim Target** dropdown (e.g. `t`), type `my_video.mp4` and click Export. The studio locks the camera and records the target's whole slider range (duration and frame rate: `animation_time` and `animation_FPS` in *Files → Settings ›*).
*   **Anything else** is part of the name: `run_dt0.5` exports `run_dt0.5.png` (and the other listed formats).

> **Note:** All exports are pristine. The studio renders a fresh copy of the plot for the export, so UI artifacts (slider handles, unapplied states) never appear in your files.

### 🎨 Presets vs. Full Exports

| Button | Saves | Typical use |
| :--- | :--- | :--- |
| **Export** | The figure/animation **and** a CSV with the entire state: physics, sweep, look, git commits, Julia versions, and copies of the configuration's source files. | Reproducing a figure months later. |
| **Look → Save** | The look only: layout, axes, slider positions, camera, labels, exploration options, UI styles. | Applying a house style to any simulation. |
| **Simulation → Save** | The physics only: shared and method parameters, active methods, sweep, reference/post-processing functions. | Switching between setups (coarse/fine grid, test cases) without touching the look. |

Presets are listed under **Presets ›** in the Files tab, with **Apply** and **Edit ›** (the rows of the preset file). **Look → Reset** restores the default look, **Simulation → Reset** the configuration you bound with `set_sim_config!` (or loaded from a CSV). See [Presets](presets.md) for the file format and the API.

## Data buttons, number tables and data from outside

*   **Data row of the Files tab:** *Resolution ›* (the display resolutions), *Compute: on/off* (the session setting
    `set_compute!`: off, *Run Simulation* and loaded files only show what is stored and list the missing runs) and
    *u − u_ref: on/off* (`set_error_field!`: the pointwise difference to the reference as a field, added when data is
    loaded, so *Run Simulation* after switching).
*   **Number tables:** a name ending in `.md` or `.txt` makes **Export** write the plotted numbers of the 1D subplots
    (`studio_export_data`: the points with the local log-log slopes, a Markdown table per subplot or CSV text) instead
    of a figure; `md` or `txt` among the export formats (*Settings ›*) writes them next to the figure.
*   **Data from outside:** **Load** (or a drop) of a plain CSV file with two numeric columns draws it in the 1D and 2D
    plots as an *External Series* named after the file (`studio_add_series!`), in the plotted x variable and the
    vertical one (the dependent field of a 1D plot, the y variable of a 2D plot, e.g. a curve separating regions of
    a heatmap): it is hidden while the plot shows other axes. The format: one point per line, its first two numbers, separated by a
    comma, a semicolon, a tab or spaces (a decimal comma is read with a semicolon or tab, `0,25;2e-3`); quotes and a
    header line are skipped. A file that is neither this nor a studio CSV is reported in the status line. The series are an option page, *UI →
    External Series* (points per label, line style, width, marker size; colours and markers continue the methods'
    lists), get legend entries and are saved with the look (presets, exports). Loading the same file again replaces
    it; `studio_clear_series!()` removes them.
