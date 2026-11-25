"""
    ShowMeFEA

Interactive 3D viewer for shell finite element results: thick-shell rendering (two surfaces offset by half the
thickness along the nodal normals, free edges closed), banded contours of nodal or element fields, a step slider,
elastic buckling modes, anchored overlays (load arrows, bolts, actuators …) and charts, as

  * a standalone HTML page (`export_viewer`), viewable without Julia or an internet connection,
  * a live page served by Bonito (`serve_viewer`),
  * high-quality still images rendered with GLMakie (`render_image`).

The model is described by [`ShellModel`](@ref) (node coordinates and one or more [`ShellPart`](@ref)s of triangles
or quadrilaterals with their thickness), the results by a vector of [`Frame`](@ref)s (displacements and fields),
and everything the page draws is precomputed once into a [`VizData`](@ref). With Ferrite loaded, `ShellModel`
also accepts a `Ferrite.Grid` and [`nodal_displacements`](@ref) extracts the translations of a `DofHandler` field.
"""
module ShowMeFEA

using Makie, Bonito, GeometryBasics, Colors, Printf, LinearAlgebra, Statistics
import WGLMakie, GLMakie

export ShellPart, ShellModel, FieldDef, Frame, Overlay, Chart, Mode, VizData
export curve, hline, vline, arrow_points, arc_points
export viewer_app, serve_viewer, export_viewer, render_image, nframes, nodal_displacements

const NBANDS = 12
const QNAN = typemax(UInt16)                  # quantized "no value"
const YIELD_GRAY = RGBf(0.62, 0.62, 0.62)     # values at or above the yield stress of the part
const YIELD_TOL = 0.995                       # nodal averages of yielded elements sit just below fy

include("palettes.jl")
include("model.jl")
include("geometry.jl")
include("scene.jl")
include("app.jl")

"""
    nodal_displacements(dh, u, field = :u) -> 3 × nnodes Matrix{Float32}

Translations of the vector `field` of a Ferrite `DofHandler` at the grid nodes (defined by the `ShowMeFEA`
Ferrite extension; `using Ferrite` first).
"""
function nodal_displacements end

end # module
