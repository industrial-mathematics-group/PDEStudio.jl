# Plot Styles: Lines

*The Lines styles are chosen with **Plot Style** in the Plot tab; their options are on the page of each style under
**UI → Plot styles**. Options such as the colormap are shared by all styles that use them.*

The *Lines* family is the fundamental rendering class for continuous, connected data. It is highly optimized for Eulerian meshes and is the default starting point for 1D visualizations. Instead of plotting discrete dots, it traces the continuous mathematical shape of your data over the physical domain.

## Shared Options
Regardless of the dimensionality of the line plot, the following styling option is universally supported:
*   **Line Width (`:line_width`):** Controls the thickness of the rendered strokes globally.

---

## 1D Lines (`:lines_1d`)
The standard, classical two-axis line plot. It maps a single independent variable (X) to a dependent mathematical field (U). Because multiple numerical methods can easily be overlaid in 1D without visual obstruction, this style supports categorical coloring and automatic legend generation.

**Supported Style Dependencies:**
*   **Colors (`:colors`):** Assigns distinct categorical colors to each active numerical method.
*   **Line Styles (`:line_styles`):** Differentiates methods using stroke patterns (e.g., `:solid`, `:dash`, `:dot`).
*   **Dashed Lines (`:dashed_lines`):** A boolean toggle to enable or disable the application of `line_styles`.
*   **Reference Lines (`:reference`):** Reference slopes `C xᵖ` for the exponents given (e.g., `[-1, -2]` for convergence rates over `N`), labelled `slope −2`. Each slope runs just below the curve whose slope on the log-log plot is closest to it, over that curve's range; the labels are placed clear of each other, of the other slopes and of the curves where the plot leaves room.

For lines with markers at the data points (e.g., a convergence plot over a swept parameter), use **Scatter Lines**
(`:scatter_lines`, in the [Scatter](scatter.md) family): the same options plus markers.

---

## 2D Lines (`:lines_2d`)
A highly specialized plot style that renders a 2D mesh as a series of dense, parallel 1D line slices. Instead of using categorical colors for different methods, it applies a continuous scalar colormap based on the value of the dependent field. It automatically supports Colorbar integration.

**Supported Style Dependencies:**
*   **Color Map (`:color_map`):** The continuous gradient used to color the line segments (e.g., `:viridis`, `:inferno`).
*   **Color Range (`:color_range`):** The mathematical limits `[min, max]` mapping the field values to the colormap.
*   **Line Direction (`:line_direction`):** Determines the slicing axis, allowing you to sweep the parallel lines either horizontally or vertically across the grid.
*   **Method Index (`:method_index`):** Selects which specific numerical method acts as the base layer, since multiple dense 2D line grids cannot easily be overlaid.
*   **Bottom Margin (`:bottom_margin`):** Adjusts padding at the base of the plot.

---

## 3D Lines (`:lines_3d`)
The three-dimensional extension of the parallel slicing technique. It projects the continuous grid lines into an `Axis3` bounding box, colored dynamically by the dependent scalar field. Like its 2D counterpart, it supports global Colorbar integration.

**Supported Style Dependencies:**
*   **Color Map (`:color_map`):** The continuous gradient applied to the 3D strokes.
*   **Color Range (`:color_range`):** The strict bounds `[min, max]` for the color scaling.
*   **Line Direction (`:line_direction`):** Controls the primary orientation of the 3D slicing projection.
*   **Method Index (`:method_index`):** Isolates a single method to project into the 3D volume.
*   **Bottom Margin (`:bottom_margin`):** Customizes structural padding.