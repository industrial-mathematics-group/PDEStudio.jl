## Deep Dive: Rendering Configuration

The two red-titled sections of the **Plot** tab—**Layout options** and **Plot options**—are the visual engine room of PDEStudio. These panels define exactly how your high-dimensional simulation tensors are sliced, projected, and compared on the screen. 

### 🏗️ Layout Options (Structural Geometry)

The Layout Options section dictates the physical structure of the Makie grid. Because changes here require destroying and rebuilding plot axes and legends, modifying these settings will turn the **Apply Layout** button yellow, signaling that a structural rebuild is required.

#### 1. Plot Style
*   **Plot Style:** the button shows the current plot type and opens a page with every supported style, grouped by geometry (*Lines*, *Scatter*, *Contour*, *Heatmap*, *Volume*); the current one is highlighted, a click chooses another (◀ Back keeps it). The page adapts to the mode: Lagrangian (particle) data offers the scatter styles matching the dimension of the particles.
*   **Plot Width / Plot Height:** the size of each subplot in pixels, any whole number from 50 to 5000 (type it and press Enter; other input is refused with a message in the status line).

#### 2. The Comparison Engine
Instead of constantly tweaking sliders to compare states, you can unroll your dimensions across a multi-column grid.
*   **Compare Target:** You can compare *almost anything* side-by-side. You can unroll different **Methods** (e.g., comparing an Upwind solver vs. a WENO solver), split vector **Components** into separate plots, compare **Time** steps, or compare across any **Varied Parameter** (e.g., different grid resolutions `N`, or text-valued sweeps such as scheme names; each subplot is titled with its value).
*   **Grid Columns:** the number of subplots per row of a comparison, any whole number from 1 to 12.
*   **At most 12 subplots:** comparisons over time or over long sweeps show up to 12 evenly spaced values (always including the first and the last), so a run with hundreds of time steps does not create hundreds of axes. The compared variable's slider is disabled while the comparison is active.
*   **Compare Link (Coupling):** When comparing multiple plots, this dropdown dictates how they share visual limits:
    *   *Fully Coupled:* All subplots share the exact same X/Y/Z axis limits and a single global Colorbar. Perfect for 1-to-1 visual comparisons.
    *   *Axes Only:* Limits are locked together, but each plot gets its own local color range.
    *   *Colorbar Only:* Axes can zoom independently, but the color mapping is universally locked.
    *   *Decoupled:* Every plot scales completely independently.

### 🔀 Grid and Particle Styles

The style page groups the styles by geometry; the last group, **Particles**, draws the data as particles at their
positions (Lagrangian, as computed, nothing is resampled), every other style draws it on a grid (Eulerian).
PDEStudioCore converts data of the other kind (particle data is interpolated onto a grid, grid data becomes
particles), so every style shows every dataset:

| | Grid styles | Particle styles (`particles_1d`, `particles_lines`, `particles_colors`, `particles_2d`, `particles_surface`, `particles_3d`) |
| :--- | :--- | :--- |
| **Shows** | fields on a grid | the particles; the page offers those of the particles' dimension |
| **Axes** | any variable, statistic or swept parameter | the particle positions |
| **Statistics** | over time, swept parameters and space | — (use a grid style) |

Switching between a grid and a particle style redraws right away (within a group *Apply Layout* as usual): the
window, the bound configuration, the look and the editors stay, the data is reloaded for the other kind (the results
are cached). Presets and CSV files store the style name, so they restore the particles; `@launch particles
test_particles_2d()` opens them directly, and `@launch` without a style picks a particle style for particle data.
With a particle style, *Files → Resolution ›* lists only the references (evaluated on a grid).

**References and the drawn time:** a reference solution (a method recognised as one, e.g. `analytical_solution`) is
evaluated for every sweep point on the domain of that point's numerical data (a sweep over the final time or the
domain size moves it) and at the times of that data, so at every position of the time slider the numerical curve and
the reference show the same time; *Files → Resolution ›* sets the reference's points in space. Data drawn with a
grid style (grid data, and particle data scattered to the grid) is not interpolated in time: it shows its stored
snapshots at their own times, all of them up to the time resolution of *Resolution ›* (default 50), otherwise that
many, evenly spread over the stored ones. A time resolution of 1 shows the last snapshot: curves over time are a
single point then (lines draw nothing), and animations are refused. (Data with more snapshots than the time
resolution is read in full on every reload; with `enable_cache!(true)` the cached conversion is used only up to the
time resolution, so raise it to the number of snapshots to reload large data from the cache.) The title shows the
time (and other grid values on sliders) of the drawn data, the snapshot nearest to the slider position, not the
slider position itself. Particle styles show every stored time. A reference is evaluated at up to the reference time
resolution (default 100) of the drawn times, so when the data shows more times than that (particle styles, or a
reference time resolution below the data's), the reference shows the nearest of those.

### 📐 Plot Options (Data Projection)

While Layout dictates *how* things are drawn, Plot Options dictate *what* is drawn. Changes made here are instantly resolved via the **Update Plot** button without needing to rebuild the layout.

#### 1. The X $\rightarrow$ Y $\rightarrow$ Z Hierarchy
The independent axes cascade strictly from top to bottom (X, then Y, then Z). This prevents mathematically impossible plots (like plotting X versus X).
*   When you select an **X-Axis**, that variable is removed from the available options for Y and Z.
*   Selecting a **Y-Axis** further restricts the available options for Z.
*   *Auto-Correction:* If you change your Plot Style from a 3D volume down to a 1D line plot, the studio will automatically detect the incompatibility, disable the Y and Z axis selectors, and reset the plot to prevent the engine from crashing.

#### 2. The Dependent Field (U-Axis)
The **U-Axis** selector is highly intelligent and reacts to your choices in the X/Y/Z dropdowns. It analyzes the backend statistical registry and automatically hides metrics that do not mathematically fit your chosen axes.
*   **Dimensional Filtering:** If you set your axes to `Position (X)` and `Position (Y)`, the U-Axis will only allow you to plot 2D spatial fields or profiles. It will automatically hide purely temporal statistics (like a time-series of Total Energy) because they lack the required spatial dimensions.
*   **The `Solution` Guarantee:** The raw, un-integrated physical state vector of your simulation is labeled `Solution`. Because it natively spans the entire mathematical domain (all space and time), it will *always* be available in the U-Axis dropdown, regardless of your axis configuration.

#### 3. Statistics as Axes
Statistics that keep a single dimension (e.g. an error per time step) or no dimension at all (e.g. a total error, plotted over a swept parameter such as `cfl`) also appear as **X-Axis** options, listed as `<Statistic> (<dimension>)`. Selecting one gives error-history and convergence plots without leaving the studio.

#### 4. Vector Components
If the variable selected in the U-Axis is a multi-dimensional state vector (e.g., a fluid momentum vector $[\ \rho u, \ \rho v]$), the **Component** dropdown will automatically activate, allowing you to quickly scrub through the individual scalar layers of that vector.