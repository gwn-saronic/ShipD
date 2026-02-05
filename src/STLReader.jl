"""
    STLReader.jl

STL file reader for Julia with offset extraction for hydrostatic calculations.
Supports both ASCII and binary STL formats.

Author: Generated for Ship-D project
Date: 2026-01-28
"""

module STLReader

export read_stl, STLMesh, extract_offsets_from_stl

using LinearAlgebra

"""
    STLTriangle

Structure representing a single triangle in an STL mesh.

# Fields
- `normal::Vector{Float64}`: Normal vector (3 elements)
- `vertices::Matrix{Float64}`: Vertex coordinates (3×3 matrix, each column is a vertex)
"""
struct STLTriangle
    normal::Vector{Float64}
    vertices::Matrix{Float64}  # 3×3 matrix: [x1 x2 x3; y1 y2 y3; z1 z2 z3]
end

"""
    STLMesh

Structure representing an STL mesh.

# Fields
- `triangles::Vector{STLTriangle}`: Array of triangles
- `bounds::Matrix{Float64}`: Bounding box [min max; x y z]
"""
struct STLMesh
    triangles::Vector{STLTriangle}
    bounds::Matrix{Float64}
end

"""
    read_stl(filename::String)

Read an STL file (ASCII or binary format).

# Arguments
- `filename::String`: Path to STL file

# Returns
- `STLMesh`: Mesh structure containing triangles and bounds

# Notes
Automatically detects ASCII vs binary format.
"""
function read_stl(filename::String)
    if !isfile(filename)
        error("File not found: $filename")
    end

    # Try to detect format by reading first few bytes
    is_ascii = open(filename, "r") do f
        header = read(f, 80)
        header_str = String(header)

        # Check if it's ASCII (starts with "solid")
        if occursin(r"^solid"i, header_str)
            # Could be ASCII, but binary files can also have "solid" in header
            # Read a bit more to be sure
            seekstart(f)
            sample = String(read(f, min(1000, filesize(filename))))
            if occursin(r"facet|vertex|endloop", sample)
                return true
            end
        end
        return false
    end

    # Call appropriate reader based on detected format
    if is_ascii
        return read_stl_ascii(filename)
    else
        return read_stl_binary(filename)
    end
end

"""
    read_stl_ascii(filename::String)

Read an ASCII STL file.

# Format
```
solid name
  facet normal nx ny nz
    outer loop
      vertex x1 y1 z1
      vertex x2 y2 z2
      vertex x3 y3 z3
    endloop
  endfacet
  ...
endsolid name
```
"""
function read_stl_ascii(filename::String)
    triangles = STLTriangle[]

    open(filename, "r") do f
        current_normal = nothing
        vertices = Matrix{Float64}(undef, 3, 3)
        vertex_count = 0

        for line in eachline(f)
            line = strip(line)

            if startswith(line, "facet normal")
                # Parse normal vector
                parts = split(line)
                current_normal = [parse(Float64, parts[3]),
                                parse(Float64, parts[4]),
                                parse(Float64, parts[5])]
                vertex_count = 0

            elseif startswith(line, "vertex")
                # Parse vertex
                parts = split(line)
                vertex_count += 1
                vertices[:, vertex_count] = [parse(Float64, parts[2]),
                                            parse(Float64, parts[3]),
                                            parse(Float64, parts[4])]

            elseif startswith(line, "endfacet")
                # Create triangle
                if current_normal !== nothing && vertex_count == 3
                    push!(triangles, STLTriangle(current_normal, copy(vertices)))
                end
                current_normal = nothing
                vertex_count = 0
            end
        end
    end

    # Calculate bounds
    bounds = calculate_bounds(triangles)

    return STLMesh(triangles, bounds)
end

"""
    read_stl_binary(filename::String)

Read a binary STL file.

# Binary Format
- 80 bytes: header
- 4 bytes: number of triangles (uint32)
- For each triangle:
  - 12 bytes: normal vector (3 × float32)
  - 36 bytes: vertices (9 × float32)
  - 2 bytes: attribute byte count (uint16)
"""
function read_stl_binary(filename::String)
    triangles = STLTriangle[]

    open(filename, "r") do f
        # Skip 80-byte header
        skip(f, 80)

        # Read number of triangles
        n_triangles = read(f, UInt32)

        # Read each triangle
        for i in 1:n_triangles
            # Read normal (3 × Float32)
            normal = Float64[read(f, Float32) for _ in 1:3]

            # Read vertices (3 vertices × 3 coordinates)
            vertices = Matrix{Float64}(undef, 3, 3)
            for v in 1:3
                for c in 1:3
                    vertices[c, v] = read(f, Float32)
                end
            end

            # Skip attribute byte count
            skip(f, 2)

            push!(triangles, STLTriangle(normal, vertices))
        end
    end

    # Calculate bounds
    bounds = calculate_bounds(triangles)

    return STLMesh(triangles, bounds)
end

"""
    calculate_bounds(triangles::Vector{STLTriangle})

Calculate bounding box for a set of triangles.

# Returns
- `Matrix{Float64}`: 3×2 matrix [x_min x_max; y_min y_max; z_min z_max]
"""
function calculate_bounds(triangles::Vector{STLTriangle})
    if isempty(triangles)
        return zeros(3, 2)
    end

    # Initialize with first vertex
    mins = vec(triangles[1].vertices[:, 1])
    maxs = vec(triangles[1].vertices[:, 1])

    # Find min/max for each coordinate
    for tri in triangles
        for v in 1:3
            for c in 1:3
                val = tri.vertices[c, v]
                mins[c] = min(mins[c], val)
                maxs[c] = max(maxs[c], val)
            end
        end
    end

    return hcat(mins, maxs)
end

"""
    extract_waterline_at_z(mesh::STLMesh, z::Float64; n_stations::Int=51)

Extract a waterline (intersection of mesh with horizontal plane at height z).

# Arguments
- `mesh::STLMesh`: STL mesh
- `z::Float64`: Vertical position of waterline
- `n_stations::Int`: Number of longitudinal stations to sample

# Returns
- `(x, y)`: Vectors of x-positions and corresponding half-breadths

# Notes
- Finds intersection of each triangle with plane z = constant
- Groups points by x-position
- Returns average half-breadth at each station
"""
function extract_waterline_at_z(mesh::STLMesh, z::Float64; n_stations::Int=51)
    # Collect all intersection points
    intersection_points = Vector{Tuple{Float64, Float64}}()  # (x, y) pairs

    for tri in mesh.triangles
        # Check if triangle intersects the plane
        z_coords = tri.vertices[3, :]  # z-coordinates of vertices

        z_min = minimum(z_coords)
        z_max = maximum(z_coords)

        if z_min <= z <= z_max
            # Triangle intersects the plane
            # Find edge intersections
            for i in 1:3
                j = mod1(i + 1, 3)  # Next vertex

                z1 = z_coords[i]
                z2 = z_coords[j]

                # Check if edge crosses the plane
                if (z1 <= z <= z2) || (z2 <= z <= z1)
                    if abs(z2 - z1) > 1e-10
                        # Interpolate to find intersection point
                        t = (z - z1) / (z2 - z1)

                        x1, y1 = tri.vertices[1, i], tri.vertices[2, i]
                        x2, y2 = tri.vertices[1, j], tri.vertices[2, j]

                        x = x1 + t * (x2 - x1)
                        y = y1 + t * (y2 - y1)

                        push!(intersection_points, (x, abs(y)))  # Use absolute value for half-breadth
                    end
                end
            end
        end
    end

    if isempty(intersection_points)
        # No intersection - return zeros
        x_range = range(mesh.bounds[1, 1], mesh.bounds[1, 2], length=n_stations)
        return collect(x_range), zeros(n_stations)
    end

    # Sort by x-coordinate
    sort!(intersection_points, by = p -> p[1])

    # Group by x-position bins and average y-values
    x_min = mesh.bounds[1, 1]
    x_max = mesh.bounds[1, 2]
    x_stations = range(x_min, x_max, length=n_stations)
    y_half_breadths = zeros(n_stations)

    bin_width = (x_max - x_min) / (n_stations - 1)

    for (x, y) in intersection_points
        # Find nearest station
        idx = round(Int, (x - x_min) / bin_width) + 1
        idx = clamp(idx, 1, n_stations)

        # Take maximum y in each bin (outermost point)
        y_half_breadths[idx] = max(y_half_breadths[idx], y)
    end

    # Smooth the curve by interpolating gaps
    for i in 2:(n_stations-1)
        if y_half_breadths[i] == 0.0 && y_half_breadths[i-1] > 0.0 && y_half_breadths[i+1] > 0.0
            y_half_breadths[i] = 0.5 * (y_half_breadths[i-1] + y_half_breadths[i+1])
        end
    end

    return collect(x_stations), y_half_breadths
end

"""
    extract_offsets_from_stl(filename::String; n_stations::Int=51, n_waterlines::Int=11, draft::Union{Nothing,Float64}=nothing)

Extract offset table from STL file for hydrostatic calculations.

# Arguments
- `filename::String`: Path to STL file
- `n_stations::Int`: Number of longitudinal stations
- `n_waterlines::Int`: Number of vertical waterlines
- `zstop::Union{Nothing,Float64}`: Draft to use (if nothing, uses full depth of mesh)

# Returns
- `(x, y_offsets, z)`: Tuple of offset data arrays
  - `x::Vector{Float64}`: Longitudinal positions (N stations)
  - `y_offsets::Matrix{Float64}`: Half-breadth offsets [x_idx, z_idx] (N × M)
  - `z::Vector{Float64}`: Vertical positions (M waterlines)

# Example
```julia
x, y_offsets, z = extract_offsets_from_stl("hull.stl", n_stations=51, n_waterlines=11)
```
"""
function extract_offsets_from_stl(filename::String;
                                 n_stations::Int=51,
                                 n_waterlines::Int=11,
                                 zstop::Union{Nothing,Float64}=nothing)
    # Read STL file
    println("Reading STL file: $filename")
    mesh = read_stl(filename)
    println("  ✓ Loaded $(length(mesh.triangles)) triangles")

    # Determine vertical range
    z_min = mesh.bounds[3, 1]
    z_max = mesh.bounds[3, 2]

    if zstop !== nothing
        # Use specified draft and shift z_max accordingly
        z_max = zstop
        # z_min = z_max - draft
    end

    println("  Vertical range: z = [$z_min, $z_max]")

    # Generate vertical stations (waterlines)
    z_stations = collect(range(z_min, z_max, length=n_waterlines))

    # Extract waterline at each z-level
    println("  Extracting waterlines...")
    y_offsets = Matrix{Float64}(undef, n_stations, n_waterlines)
    x_ref = nothing

    for (j, z) in enumerate(z_stations)
        x, y = extract_waterline_at_z(mesh, z, n_stations=n_stations)

        if x_ref === nothing
            x_ref = x
        end

        y_offsets[:, j] = y
    end

    println("  ✓ Extracted offsets at $n_waterlines waterlines")

    # Normalize x to start at 0 (consistent with Ship-D convention)
    x_normalized = x_ref .- x_ref[1]

    # Use absolute z coordinates from STL file (no normalization)
    # Draft will be the absolute z value from the STL
    return x_normalized, y_offsets, z_stations
end

end # module
