using Test, ShowMeFEA, Ferrite

# a flat 2 × 2 quad plate (part 1, toggle) with a triangle wall standing on its edge (part 2)
x = [0.0 0 0; 1 0 0; 2 0 0; 0 1 0; 1 1 0; 2 1 0; 0 2 0; 1 2 0; 2 2 0;   # plate nodes 1–9
     0 0 1; 1 0 1; 2 0 1]                                               # wall top nodes 10–12
plate = ShellPart("Plate", [(1, 2, 5, 4), (2, 3, 6, 5), (4, 5, 8, 7), (5, 6, 9, 8)]; thickness = 0.1, fy = 50.0, toggle = true)
wall = ShellPart("Wall", [(1, 2, 11), (1, 11, 10), (2, 3, 12), (2, 12, 11)]; thickness = [0.05, 0.05, 0.05, 0.05], fy = 36.0)
model = ShellModel(x, [plate, wall]; up = :z)
@test ShowMeFEA.nnodes(model) == 12 && ShowMeFEA.nelements(model) == 8

nf = 6
frames = [Frame(0.01k .* [zeros(12)'; zeros(12)'; (x[:, 3] .+ x[:, 1] ./ 2)'];
                fields = Dict(:vm => 10k .* (1:8), :peeq => vcat(fill(NaN, 4), 1e-3k .* (1:4)), :uz => 0.01k .* x[:, 3]),
                label = "Step $(k - 1)", info = "<b>load</b> $(k) kip") for k in 1:nf]
fields = [FieldDef(:vm, "von Mises"; unit = "ksi", yield = true), FieldDef(:peeq, "Plastic strain"), FieldDef(:uz, "Vertical displacement"; unit = "in", kind = :div)]
# an arrow anchored at the loaded node (12) whose length grows with the frame, and markers at the plate corners
off = zeros(3, 10, nf)
for k in 1:nf
    pts = arrow_points((0, 0, 0.3k / nf), (0, 0, 0), (1, 0, 0), (0, 1, 0))
    for (i, p) in enumerate(pts); off[:, i, k] .= p; end
end
load = Overlay("Load", :segments, fill(12, 10), off; requires = 2, notes = ["F = $k kip" for k in 1:nf])
bolts = Overlay("Bolts", :markers, [1, 3, 7, 9], zeros(3, 4); color = :gray, marker = (0.15, 0.05))
chart = Chart("Load – displacement"; xlabel = "w (in)", ylabel = "F (kip)", curves = [curve(0.01 .* (1:nf), 1:nf; label = "Model")],
              hlines = [hline(4.5; label = "test")], marker = (x = 0.01 .* (1:nf), y = collect(1.0:nf)))
mode = Mode("Mode 1: λ = 2.5", [zeros(12)'; zeros(12)'; (x[:, 1] ./ 2)']; info = "<b>λ</b> 2.5")
v = VizData(model, frames; fields, overlays = [load, bolts], charts = [chart], modes = [mode], notes = ["reference 4.5 kip"], max_frames = 4, keep = [3])

@test nframes(v) == 4 && v.keep == [1, 3, 4, 6]           # first, keep, evenly spaced, last
@test length(v.pv_node) == 12 + 3                           # nodes 1–3 belong to both parts
@test any(f -> f.key == :vm && f.max == 50.0, v.fields)      # yield field: contour limit = largest fy
@test length(v.faces) > 2 * 12 && !isempty(v.feature)
@test size(v.overlays[1].offset, 3) == 4 && v.overlays[1].notes == ["F = 1 kip", "F = 3 kip", "F = 4 kip", "F = 6 kip"]
@test v.charts[1].marker.y == [1, 3, 4, 6]
pos = ShowMeFEA.surface_positions(v, 2, 2.0)
@test length(pos) == length(v.sv_pv)
@test ShowMeFEA.surface_colors(v, 1, v.fields[2], 1e-3)[1] |> isnan     # plate has no plastic strain
@test length(ShowMeFEA.overlay_points(v, v.overlays[1], 3, 1.0)) == 10

path = export_viewer(joinpath(mktempdir(), "test.html"), v; title = "ShowMeFEA test", view_labels = Dict(:pz => "Top"))
@test isfile(path) && filesize(path) > 100_000
html = read(path, String)
@test occursin("Mode 1: λ", html) && occursin("Top", html) && occursin("ShowMeFEA test", html)

# Ferrite extension
grid = generate_grid(Quadrilateral, (2, 2))
m2 = ShellModel(grid; thickness = 0.1, fy = 50.0)
@test ShowMeFEA.nnodes(m2) == 9 && length(m2.parts) == 1 && all(iszero, m2.x[:, 3])
addcellset!(grid, "left", x -> x[1] <= 0)
m3 = ShellModel(grid; thickness = [0.1, 0.2], parts = ["left" => "left", "all" => 1:4])
@test length(m3.parts) == 2 && m3.parts[1].thickness == [0.1, 0.1]
dh = DofHandler(grid); add!(dh, :u, Lagrange{RefQuadrilateral,1}()^2); close!(dh)
u = zeros(ndofs(dh)); u[1:2] .= (0.5, -0.5)
d = nodal_displacements(dh, u, :u)
@test size(d) == (3, 9) && d[1, grid.cells[1].nodes[1]] == 0.5f0 && d[2, grid.cells[1].nodes[1]] == -0.5f0
