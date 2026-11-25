module ShowMeFEAFerriteExt

using ShowMeFEA, Ferrite

_cellnodes(grid, ids) = [Int32.(collect(grid.cells[c].nodes)) for c in ids]

"""
    ShellModel(grid::Ferrite.Grid; thickness, fy = Inf, parts = nothing, name = "shell", normals = nothing, up = :z, toggle = false)

Shell model from a Ferrite grid of `Triangle` or `Quadrilateral` cells (2D grids are placed in the plane z = 0).
`parts` is an optional vector of `name => cellset` pairs (one [`ShellPart`](@ref) per cellset, with `thickness`,
`fy` and `toggle` given per part as vectors or shared scalars); without it the whole grid is one part. `thickness`
is one value or one per cell of the part; `normals` optional unit normals per cell.
"""
function ShowMeFEA.ShellModel(grid::Ferrite.Grid; thickness, fy = Inf, parts = nothing, name::AbstractString = "shell", normals = nothing,
                              up::Symbol = :z, toggle = false)
    nn = getnnodes(grid); dim = length(grid.nodes[1].x)
    x = zeros(nn, 3)
    for n in 1:nn, i in 1:dim
        x[n, i] = grid.nodes[n].x[i]
    end
    if parts === nothing
        ps = [ShellPart(name, _cellnodes(grid, 1:getncells(grid)); thickness, fy, normals, toggle = toggle isa Bool ? toggle : toggle[1])]
    else
        ps = ShellPart[]
        for (i, (nm, set)) in enumerate(parts)
            ids = sort!(collect(set isa AbstractString || set isa Symbol ? getcellset(grid, String(set)) : set))
            th = thickness isa AbstractVector{<:AbstractVector} ? thickness[i] : thickness isa AbstractVector && length(thickness) == length(parts) ? thickness[i] : thickness
            push!(ps, ShellPart(String(nm), _cellnodes(grid, ids); thickness = th, fy = fy isa AbstractVector ? fy[i] : fy,
                                normals = normals isa AbstractVector{<:AbstractVector} ? normals[i] : normals,
                                toggle = toggle isa AbstractVector ? toggle[i] : toggle))
        end
    end
    return ShellModel(x, ps; up)
end

"""
    nodal_displacements(dh::Ferrite.DofHandler, u, field = :u) -> 3 × nnodes Matrix{Float32}

Translations of the vector-valued `field` (a `Lagrange` order-1 interpolation with 2 or 3 components, dofs ordered
node by node within each cell) at the nodes of the grid, taken from the first cell that touches each node.
"""
function ShowMeFEA.nodal_displacements(dh::Ferrite.DofHandler, u::AbstractVector, field::Symbol = :u)
    grid = dh.grid; nn = getnnodes(grid)
    out = zeros(Float32, 3, nn); seen = falses(nn)
    for sdh in dh.subdofhandlers
        field in sdh.field_names || continue
        rng = dof_range(sdh, field)
        fi = findfirst(==(field), sdh.field_names)
        ncomp = Ferrite.n_components(sdh.field_interpolations[fi])
        for c in sdh.cellset
            nodes = grid.cells[c].nodes
            cd = celldofs(dh, c)[rng]
            length(cd) == ncomp * length(nodes) || error("nodal_displacements: field $field is not a nodal (order-1) vector field")
            for (i, n) in enumerate(nodes)
                seen[n] && continue
                for j in 1:ncomp
                    out[j, n] = u[cd[ncomp * (i - 1) + j]]
                end
                seen[n] = true
            end
        end
    end
    return out
end

end # module
