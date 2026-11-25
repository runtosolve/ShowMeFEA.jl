# ShowMeFEA.jl

Interactive 3D viewer for shell finite element results. One Julia call turns a mesh, the step-by-step
displacements and the element or nodal fields into

* a **standalone HTML page** (`export_viewer`) that runs without Julia or an internet connection: step slider and
  play, contour selector with banded legend, deformation scale, mesh edges, undeformed outline, part and overlay
  toggles, buckling modes, charts that follow the step, preset views, box zoom, orbit/tilt buttons,
  orthographic toggle and PNG export;
* a **live page** served by Bonito/WGLMakie (`serve_viewer`);
* **still images** rendered with GLMakie (`render_image`): ambient occlusion, anti-aliasing, colour bar, charts.

Shells are drawn with their thickness (two surfaces offset by half the thickness along the nodal normals, free
edges closed), so the "top" and "bottom" surface values of a shell can be shown on their own faces. All per-step
data are precomputed and quantized once; the page is one file and every control runs in the browser.

## Install

```julia
] dev /path/to/ShowMeFEA        # or ] add https://github.com/runtosolve/ShowMeFEA.jl
```

## Use

```julia
using ShowMeFEA

# mesh: node coordinates (nn × 3) and one or more parts of triangles / quadrilaterals
plate = ShellPart("Plate", conn_plate; thickness = 0.5, fy = 50.0, toggle = true)
wall  = ShellPart("Wall",  conn_wall;  thickness = t_per_element, fy = 36.0, normals = n_per_element)
model = ShellModel(x, [plate, wall]; up = :z)         # up: vertical axis of the camera (:y or :z)

# results: one Frame per step, displacements 3 × nn, fields per element (all parts in order) or per node
frames = [Frame(disp[k]; fields = Dict(:vm_top => ..., :vm_bot => ..., :peeq => ...),
                label = "Step $k", info = "<b>M</b> $(M[k]) kip-in") for k in 1:nsteps]
fields = [FieldDef(:vm, "von Mises stress"; unit = "ksi", top = :vm_top, bot = :vm_bot, yield = true),
          FieldDef(:peeq, "Equivalent plastic strain"),
          FieldDef(:uz, "Vertical displacement"; unit = "in", kind = :div)]

# optional: overlays anchored to nodes (loads, bolts), charts, buckling modes, legend notes
load  = Overlay("Load", :segments, anchors, offsets; notes = per_step_html)   # offsets 3 × npts (× nsteps)
chart = Chart("Moment – rotation"; xlabel = "θ (rad)", ylabel = "M (kip-in)",
              curves = [curve(θ, M; label = "Model")], hlines = [hline(Mtest; label = "test")],
              marker = (x = θ, y = M))                                        # the current step's point
modes = [Mode("Mode 1: Mcr = 70.4 kip-in", φ1; info = "<b>Mcr</b> 70.4 kip-in")]

v = VizData(model, frames; fields, overlays = [load], charts = [chart], modes, max_frames = 40, keep = [i_peak])
export_viewer("model.html", v; title = "My model", view_labels = Dict(:pz => "Top"))
render_image("model_peak.png", v, 12; field = :vm, charts = true)
serve_viewer(v; port = 8642)
```

`arrow_points` and `arc_points` build the point lists of force arrows and moment arcs for overlays. The page
accepts an initial state in the URL hash (`#frame=12&field=peeq&scale=5&view=mz&persp=0`, `#model=m1` for a mode).

### Ferrite

With `using Ferrite`, `ShellModel(grid; thickness, fy, parts = ["Plate" => "plate_cells", ...])` builds the model
from a `Grid` of `Triangle`/`Quadrilateral` cells and `nodal_displacements(dh, u, :u)` extracts the translations of a
nodal vector field from a `DofHandler` solution.

## Notes

* Fields are quantized to 16 bits per value and step; `NaN` marks "no value" (drawn grey).
* `max_frames` thins the frames kept for the page (the charts use every step); pass the indices that must stay
  (peak, end of a load stage) in `keep`.
* The export writes to a temporary file first and then copies it, which avoids time-outs on cloud-synced folders.

## Checking an exported page without a browser window

`dev/devtools_shot.py` drives headless Chrome over the DevTools protocol (needs the `websockets` Python package): it
loads an exported page, waits until the model has rendered, optionally runs JavaScript against `window.__smf`
(the page's state: `el` controls, `D` data, `cam` camera helpers) and saves a screenshot.

```sh
python3 dev/devtools_shot.py model.html shot.png "window.__smf.cam.view(...window.__smf.cam.presets.mz)"
```
