"""
    Hydrostatics.jl

Hydrostatic calculations for ship hulls based on offset data.
This module provides functions to calculate:
- Displaced volume
- Waterplane area
- Centers of buoyancy (LCB, VCB)
- Longitudinal center of flotation (LCF)
- Second moments of area (Ixx, Iyy)
- Wetted surface area
- Waterline length

Compatible with the Ship-D hull parameterization system.

Author: Generated for Ship-D project
Date: 2026-01-28
"""

module Hydrostatics

export HydrostaticProperties, calculate_hydrostatics, calculate_hydrostatics_at_draft
export displaced_volume, waterplane_area, center_of_buoyancy, center_of_flotation
export second_moments, wetted_surface_area, waterline_length
export calculate_hydrostatics_from_file, HullInput

using LinearAlgebra

# Conditionally include STLReader
const STL_AVAILABLE = Ref(false)
function __init__()
    # Try to load STLReader module
    try
        stl_path = joinpath(dirname(@__FILE__), "STLReader.jl")
        if isfile(stl_path)
            include(stl_path)
            STL_AVAILABLE[] = true
        end
    catch e
        @warn "STLReader not available. STL file input will not work." exception=e
    end
end

"""
    HydrostaticProperties

Structure to hold hydrostatic properties at a given draft.

# Fields
- `draft::Float64`: Draft (vertical depth below waterline)
- `volume::Float64`: Displaced volume
- `waterplane_area::Float64`: Waterplane area at the waterline
- `lcb::Float64`: Longitudinal center of buoyancy
- `vcb::Float64`: Vertical center of buoyancy
- `lcf::Float64`: Longitudinal center of flotation
- `ixx::Float64`: Second moment of waterplane area about longitudinal axis
- `iyy::Float64`: Second moment of waterplane area about transverse axis
- `wetted_surface::Float64`: Wetted surface area
- `waterline_length::Float64`: Length of the waterline
"""
struct HydrostaticProperties
    draft::Float64
    volume::Float64
    waterplane_area::Float64
    lcb::Float64
    vcb::Float64
    lcf::Float64
    ixx::Float64 # wrong
    iyy::Float64 # wrong
    wetted_surface::Float64 # wrong
    waterline_length::Float64
end

"""
    calculate_waterplane_area(x::Vector, y::Vector)

Calculate waterplane area using trapezoidal integration.

# Arguments
- `x::Vector`: Longitudinal positions along waterline
- `y::Vector`: Half-breadth offsets at each x position

# Returns
- `Float64`: Waterplane area (accounts for both port and starboard sides)

# Notes
Uses trapezoidal rule: A = 2 * ∫ y dx (factor of 2 for full breadth)
"""
function calculate_waterplane_area(x::Vector, y::Vector)
    @assert length(x) == length(y) "x and y must have same length"
    @assert length(x) >= 2 "Need at least 2 points"

    area = 0.0
    for i in 1:(length(x)-1)
        dx = x[i+1] - x[i]
        area += 0.5 * (y[i] + y[i+1]) * dx
    end

    # Multiply by 2 for full breadth (port and starboard)
    return 2.0 * area
end

"""
    calculate_waterplane_center(x::Vector, y::Vector)

Calculate longitudinal center of flotation (LCF) using first moment.

# Arguments
- `x::Vector`: Longitudinal positions along waterline
- `y::Vector`: Half-breadth offsets at each x position

# Returns
- `Float64`: Longitudinal center of flotation

# Notes
LCF = ∫ x·y dx / ∫ y dx
"""
function calculate_waterplane_center(x::Vector, y::Vector)
    @assert length(x) == length(y) "x and y must have same length"
    @assert length(x) >= 2 "Need at least 2 points"

    moment = 0.0
    area = 0.0

    for i in 1:(length(x)-1)
        dx = x[i+1] - x[i]
        avg_y = 0.5 * (y[i] + y[i+1])
        avg_x = 0.5 * (x[i] + x[i+1])

        area += avg_y * dx
        moment += avg_x * avg_y * dx
    end

    return area > 1e-10 ? moment / area : 0.0
end

"""
    calculate_second_moments(x::Vector, y::Vector)

Calculate second moments of waterplane area (Ixx, Iyy).

# Arguments
- `x::Vector`: Longitudinal positions along waterline
- `y::Vector`: Half-breadth offsets at each x position

# Returns
- `(Float64, Float64)`: Tuple of (Ixx, Iyy)

# Notes
- Ixx: Second moment about longitudinal axis (transverse stability)
- Iyy: Second moment about transverse axis (longitudinal stability)
- Both calculated about the centerline/amidships
"""
function calculate_second_moments(x::Vector, y::Vector)
    @assert length(x) == length(y) "x and y must have same length"
    @assert length(x) >= 2 "Need at least 2 points"

    ixx = 0.0
    iyy = 0.0

    for i in 1:(length(x)-1)
        dx = x[i+1] - x[i]
        a = y[i]
        b = y[i+1]

        # Ixx: moment about longitudinal axis
        # Using trapezoidal section formula: I = (h/48) * (a+b) * (a² + b²)
        # Multiplied by 2 for both sides, and by 4/3 for full breadth effect
        ixx += (dx / 48.0) * (a + b) * (a^2 + b^2) * 8.0

        # Iyy: moment about transverse axis
        # Using parallel axis theorem and section centroids
        x_mid = 0.5 * (x[i] + x[i+1])
        avg_y = 0.5 * (a + b)
        iyy += avg_y * dx * x_mid^2 + (dx^3 / 36.0) * (a + b)
    end

    # Account for both sides (port and starboard)
    iyy *= 2.0

    return (ixx, iyy)
end

"""
    calculate_waterline_length(x::Vector, y::Vector; threshold::Float64=1e-6)

Calculate the waterline length.

# Arguments
- `x::Vector`: Longitudinal positions along waterline
- `y::Vector`: Half-breadth offsets at each x position
- `threshold::Float64`: Minimum half-breadth to consider as part of waterline

# Returns
- `Float64`: Waterline length

# Notes
Waterline length is calculated as the distance between the foremost and aftmost
points where the half-breadth exceeds the threshold.
"""
function calculate_waterline_length(x::Vector, y::Vector; threshold::Float64=1e-6)
    @assert length(x) == length(y) "x and y must have same length"

    # Find indices where y exceeds threshold
    valid_indices = findall(y .> threshold)

    if isempty(valid_indices)
        return 0.0
    end

    return x[valid_indices[end]] - x[valid_indices[1]]
end

"""
    calculate_wetted_perimeter(y::Vector, z::Vector)

Calculate the wetted perimeter of a cross-section.

# Arguments
- `y::Vector`: Half-breadth offsets at different vertical positions
- `z::Vector`: Vertical positions (depths)

# Returns
- `Float64`: Wetted perimeter for one side

# Notes
Uses arc length calculation: L = ∫ √(1 + (dy/dz)²) dz
Result should be multiplied by 2 for both sides plus keel length.
"""
function calculate_wetted_perimeter(y::Vector, z::Vector)
    @assert length(y) == length(z) "y and z must have same length"
    @assert length(y) >= 2 "Need at least 2 points"

    perimeter = 0.0

    for i in 1:(length(z)-1)
        dy = y[i+1] - y[i]
        dz = z[i+1] - z[i]
        ds = sqrt(dy^2 + dz^2)
        perimeter += ds
    end

    return perimeter
end

"""
    calculate_hydrostatics_at_draft(x::Vector, y_offsets::Matrix, z::Vector, draft_idx::Int)

Calculate hydrostatic properties at a specific draft.

# Arguments
- `x::Vector`: Longitudinal positions (station locations)
- `y_offsets::Matrix`: Half-breadth offsets, indexed as [x_idx, z_idx]
- `z::Vector`: Vertical positions (depths, negative below waterline)
- `draft_idx::Int`: Index of draft to calculate properties at

# Returns
- `HydrostaticProperties`: Struct containing all hydrostatic properties

# Notes
This function calculates properties for a single waterline/draft.
For complete hydrostatic curves, use `calculate_hydrostatics`.
"""
function calculate_hydrostatics_at_draft(x::Vector, y_offsets::Matrix, z::Vector, draft_idx::Int)
    # Extract waterline at this draft
    y_wl = y_offsets[:, draft_idx]
    draft = z[draft_idx]

    # Calculate waterplane properties
    area_wp = calculate_waterplane_area(x, y_wl)
    lcf = calculate_waterplane_center(x, y_wl)
    ixx, iyy = calculate_second_moments(x, y_wl)
    wl_length = calculate_waterline_length(x, y_wl)

    # For volume, integrate area over depth (set to 0 for single draft)
    # For wetted surface, integrate perimeter over depth (set to 0 for single draft)
    # These require multiple drafts - see calculate_hydrostatics

    return HydrostaticProperties(
        draft,
        0.0,  # Volume requires integration over drafts
        area_wp,
        0.0,  # LCB requires integration over drafts
        0.0,  # VCB requires integration over drafts
        lcf,
        ixx,
        iyy,
        0.0,  # Wetted surface requires integration over drafts
        wl_length
    )
end

"""
    calculate_hydrostatics(x::Vector, y_offsets::Matrix, z::Vector)

Calculate complete hydrostatic properties over a range of drafts.

# Arguments
- `x::Vector`: Longitudinal positions (station locations, length N)
- `y_offsets::Matrix`: Half-breadth offsets, indexed as [x_idx, z_idx] (N × M)
- `z::Vector`: Vertical positions (depths, negative below waterline, length M)

# Returns
- `Vector{HydrostaticProperties}`: Array of hydrostatic properties at each draft

# Notes
This is the main function for comprehensive hydrostatic analysis.
It calculates all properties by integrating over the hull form from keel to waterline.

The coordinate system assumes:
- x: longitudinal (positive aft, bow at x=0 after normalization)
- y: transverse (half-breadth, positive to port or starboard)
- z: vertical (negative below waterline, z=0 at waterline)
"""
function calculate_hydrostatics(x::Vector, y_offsets::Matrix, z::Vector)
    @assert size(y_offsets, 1) == length(x) "First dimension of y_offsets must match x"
    @assert size(y_offsets, 2) == length(z) "Second dimension of y_offsets must match z"
    @assert length(z) >= 2 "Need at least 2 vertical stations"
    @assert issorted(z) "z must be sorted in ascending order"

    num_drafts = length(z)
    results = Vector{HydrostaticProperties}(undef, num_drafts)

    # Arrays to store intermediate values for volume integration
    areas_wp = zeros(num_drafts)
    lcfs = zeros(num_drafts)
    perimeters = zeros(length(x))  # Perimeter at each x-station

    # Calculate waterplane properties at each draft
    for i in 1:num_drafts
        y_wl = y_offsets[:, i]
        areas_wp[i] = calculate_waterplane_area(x, y_wl)
        lcfs[i] = calculate_waterplane_center(x, y_wl)
    end

    # Calculate wetted perimeters at each x-station
    for i in 1:length(x)
        y_section = y_offsets[i, :]
        perimeters[i] = calculate_wetted_perimeter(y_section, z)
    end

    # Integrate to get volumes, centers of buoyancy, and wetted surface
    volumes = zeros(num_drafts)
    lcbs = zeros(num_drafts)
    vcbs = zeros(num_drafts)
    wetted_surfaces = zeros(num_drafts)

    for i in 2:num_drafts
        # Volume: trapezoidal integration of waterplane areas
        dz = z[i] - z[i-1]
        volumes[i] = volumes[i-1] + 0.5 * (areas_wp[i] + areas_wp[i-1]) * dz

        # LCB: first moment of volume
        if volumes[i] > 1e-10
            # Integrate LCF * Area over depth
            moment_x = 0.0
            for j in 2:i
                dz_j = z[j] - z[j-1]
                moment_x += 0.5 * (lcfs[j] * areas_wp[j] + lcfs[j-1] * areas_wp[j-1]) * dz_j
            end
            lcbs[i] = moment_x / volumes[i]
        end

        # VCB: vertical center of buoyancy
        if volumes[i] > 1e-10
            # Integrate z * Area over depth
            moment_z = 0.0
            for j in 2:i
                dz_j = z[j] - z[j-1]
                z_mid = 0.5 * (z[j] + z[j-1])
                moment_z += 0.5 * (areas_wp[j] + areas_wp[j-1]) * dz_j * z_mid
            end
            vcbs[i] = moment_z / volumes[i]
        end

        # Wetted surface: integrate perimeter over x and z
        # For each station, integrate perimeter over depth
        wsa = 0.0
        for k in 1:(length(x)-1)
            dx = x[k+1] - x[k]
            # Average perimeter between two stations, both sides
            avg_perim = 0.5 * (perimeters[k] + perimeters[k+1])
            wsa += 2.0 * avg_perim * dx  # Factor of 2 for both sides

            # Add bottom (keel) area
            if i == num_drafts  # Only at full draft
                # Keel width contribution
                wsa += (y_offsets[k, 1] + y_offsets[k+1, 1]) * dx
            end
        end
        wetted_surfaces[i] = wsa
    end

    # Build results array
    for i in 1:num_drafts
        y_wl = y_offsets[:, i]
        ixx, iyy = calculate_second_moments(x, y_wl)
        wl_length = calculate_waterline_length(x, y_wl)
        lcf = lcfs[i]

        results[i] = HydrostaticProperties(
            z[i],
            volumes[i],
            areas_wp[i],
            lcbs[i],
            vcbs[i],
            lcf,
            ixx,
            iyy,
            wetted_surfaces[i],
            wl_length
        )
    end

    return results
end

"""
    displaced_volume(props::HydrostaticProperties)

Extract displaced volume from HydrostaticProperties.
"""
displaced_volume(props::HydrostaticProperties) = props.volume

"""
    waterplane_area(props::HydrostaticProperties)

Extract waterplane area from HydrostaticProperties.
"""
waterplane_area(props::HydrostaticProperties) = props.waterplane_area

"""
    center_of_buoyancy(props::HydrostaticProperties)

Extract center of buoyancy (LCB, VCB) from HydrostaticProperties.

# Returns
- `(Float64, Float64)`: Tuple of (LCB, VCB)
"""
center_of_buoyancy(props::HydrostaticProperties) = (props.lcb, props.vcb)

"""
    center_of_flotation(props::HydrostaticProperties)

Extract longitudinal center of flotation from HydrostaticProperties.
"""
center_of_flotation(props::HydrostaticProperties) = props.lcf

"""
    second_moments(props::HydrostaticProperties)

Extract second moments (Ixx, Iyy) from HydrostaticProperties.

# Returns
- `(Float64, Float64)`: Tuple of (Ixx, Iyy)
"""
second_moments(props::HydrostaticProperties) = (props.ixx, props.iyy)

"""
    wetted_surface_area(props::HydrostaticProperties)

Extract wetted surface area from HydrostaticProperties.
"""
wetted_surface_area(props::HydrostaticProperties) = props.wetted_surface

"""
    waterline_length(props::HydrostaticProperties)

Extract waterline length from HydrostaticProperties.
"""
waterline_length(props::HydrostaticProperties) = props.waterline_length

# ============================================================================
# Unified Interface for Multiple Input Types
# ============================================================================

"""
    HullInput

Abstract type for hull input sources.
"""
abstract type HullInput end

"""
    OffsetInput <: HullInput

Hull input from offset tables.

# Fields
- `x::Vector{Float64}`: Longitudinal positions
- `y_offsets::Matrix{Float64}`: Half-breadth offsets [x_idx, z_idx]
- `z::Vector{Float64}`: Vertical positions
"""
struct OffsetInput <: HullInput
    x::Vector{Float64}
    y_offsets::Matrix{Float64}
    z::Vector{Float64}
end

"""
    STLInput <: HullInput

Hull input from STL file.

# Fields
- `filename::String`: Path to STL file
- `n_stations::Int`: Number of longitudinal stations
- `n_waterlines::Int`: Number of vertical waterlines
- `draft::Union{Nothing,Float64}`: Draft to use (nothing = full depth)
"""
struct STLInput <: HullInput
    filename::String
    n_stations::Int
    n_waterlines::Int
    draft::Union{Nothing,Float64}
end

"""
    calculate_hydrostatics_from_file(filename::String; input_type::Symbol=:auto, kwargs...)

Calculate hydrostatics from a file with automatic format detection.

# Arguments
- `filename::String`: Path to input file (STL, CSV, or other formats)
- `input_type::Symbol`: Input type (:auto, :stl, :offsets)
- `kwargs...`: Additional arguments for STL processing
  - `n_stations::Int`: Number of longitudinal stations (default: 51)
  - `n_waterlines::Int`: Number of vertical waterlines (default: 11)
  - `draft::Union{Nothing,Float64}`: Draft to use for STL (default: nothing)

# Returns
- `Vector{HydrostaticProperties}`: Hydrostatic properties at each draft

# Examples
```julia
# Automatic detection
results = calculate_hydrostatics_from_file("hull.stl")

# Explicit STL format
results = calculate_hydrostatics_from_file("hull.stl", input_type=:stl, n_stations=51)

# From offsets (not yet implemented - use calculate_hydrostatics directly)
x, y, z = load_offsets("offsets.csv")
results = calculate_hydrostatics(x, y, z)
```
"""
function calculate_hydrostatics_from_file(filename::String;
                                         input_type::Symbol=:auto,
                                         n_stations::Int=51,
                                         n_waterlines::Int=11,
                                         draft::Union{Nothing,Float64}=nothing)
    # Auto-detect input type
    if input_type == :auto
        ext = lowercase(splitext(filename)[2])
        if ext == ".stl"
            input_type = :stl
        else
            error("Cannot auto-detect input type for file: $filename. Please specify input_type.")
        end
    end

    # Process based on input type
    if input_type == :stl
        return calculate_hydrostatics_from_stl(filename,
                                               n_stations=n_stations,
                                               n_waterlines=n_waterlines,
                                               draft=draft)
    else
        error("Unsupported input type: $input_type")
    end
end

"""
    calculate_hydrostatics_from_stl(filename::String; kwargs...)

Calculate hydrostatics from an STL file.

# Arguments
- `filename::String`: Path to STL file
- `n_stations::Int`: Number of longitudinal stations (default: 51)
- `n_waterlines::Int`: Number of vertical waterlines (default: 11)
- `draft::Union{Nothing,Float64}`: Draft to use (default: nothing, uses full depth)

# Returns
- `Vector{HydrostaticProperties}`: Hydrostatic properties at each draft

# Example
```julia
results = calculate_hydrostatics_from_stl("hull.stl", n_stations=51, n_waterlines=11)
```
"""
function calculate_hydrostatics_from_stl(filename::String;
                                        n_stations::Int=51,
                                        n_waterlines::Int=11,
                                        draft::Union{Nothing,Float64}=nothing)
    if !STL_AVAILABLE[]
        error("STL support not available. Make sure STLReader.jl is in the same directory as Hydrostatics.jl")
    end

    # Extract offsets from STL
    x, y_offsets, z = STLReader.extract_offsets_from_stl(filename,
                                                         n_stations=n_stations,
                                                         n_waterlines=n_waterlines,
                                                         draft=draft)

    # Calculate hydrostatics
    return calculate_hydrostatics(x, y_offsets, z)
end

"""
    calculate_hydrostatics(input::HullInput)

Calculate hydrostatics from a HullInput object.

# Arguments
- `input::HullInput`: Hull input (OffsetInput or STLInput)

# Returns
- `Vector{HydrostaticProperties}`: Hydrostatic properties at each draft

# Example
```julia
# From offsets
input = OffsetInput(x, y_offsets, z)
results = calculate_hydrostatics(input)

# From STL
input = STLInput("hull.stl", 51, 11, nothing)
results = calculate_hydrostatics(input)
```
"""
function calculate_hydrostatics(input::OffsetInput)
    return calculate_hydrostatics(input.x, input.y_offsets, input.z)
end

function calculate_hydrostatics(input::STLInput)
    return calculate_hydrostatics_from_stl(input.filename,
                                          n_stations=input.n_stations,
                                          n_waterlines=input.n_waterlines,
                                          draft=input.draft)
end

end # module
