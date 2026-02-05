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
export FloatEquilibrium, solve_equilibrium_float, interpolate_hydrostatics

using LinearAlgebra

# Try to load FormCoefficients module
const FORM_COEFFS_AVAILABLE = Ref(false)
function __init_form_coefficients__()
    try
        form_coeffs_path = joinpath(dirname(@__FILE__), "FormCoefficients.jl")
        if isfile(form_coeffs_path)
            include(form_coeffs_path)
            FORM_COEFFS_AVAILABLE[] = true
        end
    catch e
        @warn "FormCoefficients not available. Form coefficient calculations will be limited." exception=e
    end
end

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
        @warn "STLReader not available. STL file input will not work." exception = e
    end

    # Try to load FormCoefficients module
    __init_form_coefficients__()
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
    ixx::Float64
    iyy::Float64
    wsa::Float64
    waterline_length::Float64
end

"""
    FloatEquilibrium

Structure to hold float equilibrium solution results.

# Fields
- `mass::Float64`: Ship mass (kg or tonnes)
- `water_density::Float64`: Water density (kg/m³ or tonnes/m³)
- `cog::Tuple{Float64,Float64,Float64}`: Center of gravity (LCG, TCG, VCG) from origin
- `equilibrium_draft::Float64`: Solved equilibrium draft
- `trim_angle::Float64`: Trim angle in radians (positive = bow up)
- `displacement::Float64`: Displaced volume at equilibrium
- `hydrostatics::HydrostaticProperties`: Hydrostatic properties at equilibrium
- `form_coefficients::Union{Nothing,Any}`: Form coefficients (if available)
- `iterations::Int`: Number of Newton-Raphson iterations
- `converged::Bool`: Whether solver converged
- `residual::Float64`: Final residual error
"""
struct FloatEquilibrium
    mass::Float64
    water_density::Float64
    cog::Tuple{Float64,Float64,Float64}
    equilibrium_draft::Float64
    trim_angle::Float64
    displacement::Float64
    hydrostatics::HydrostaticProperties
    form_coefficients::Union{Nothing,Any}
    iterations::Int
    converged::Bool
    residual::Float64
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
    calculate_second_moments(x::Vector, y::Vector, waterplane_area::Number, LCF::Number)

Calculate second moments of waterplane area (Ixx, Iyy).

# Arguments
- `x::Vector`: Longitudinal positions along waterline
- `y::Vector`: Half-breadth offsets at each x position
- `waterplane_area::Number`: Waterplane area at this draft
- `LCF::Number`: Longitudinal center of flotation

# Returns
- `(Float64, Float64)`: Tuple of (Ixx, Iyy)

# Notes
- Ixx: Second moment about longitudinal axis (transverse stability)
- IL: Second moment about transverse axis going through the LCF (longitudinal stability)
- Both calculated about the centerline/amidships
"""
function calculate_second_moments(x::Vector, y::Vector, waterplane_area::Number, LCF::Number)
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

    # Calculate second moment about LCF (longitudinal stability)
    iL = iyy - waterplane_area * LCF^2

    return (ixx, iL)
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
    calculate_waterline_arc_length(x::Vector, y::Vector)

Calculate the arc length along a waterline contour.

# Arguments
- `x::Vector`: Longitudinal positions along waterline
- `y::Vector`: Half-breadth offsets at each x position

# Returns
- `Float64`: Arc length for one side of the hull

# Notes
Uses arc length calculation: L = ∫ √((dx)² + (dy)²)
This calculates the arc length along the waterline in the x-y plane.
Result should be multiplied by 2 for both sides, plus transom width if applicable.
"""
function calculate_waterline_arc_length(x::Vector, y::Vector)
    @assert length(x) == length(y) "x and y must have same length"
    @assert length(x) >= 2 "Need at least 2 points"

    arc_length = 0.0

    for i in 1:(length(x)-1)
        dx = x[i+1] - x[i]
        dy = y[i+1] - y[i]
        ds = √(dx^2 + dy^2)
        arc_length += ds
    end

    # Add bow closure (from centerline to first point)
    if y[1] > 1e-6
        arc_length += y[1]
    end

    # Add stern closure (from last point to centerline)
    if y[end] > 1e-6
        arc_length += y[end]
    end

    return arc_length
end

"""
    calculate_station_arc_length(y_station::Vector, z::Vector)

Calculate the arc length along a station (constant x) in the y-z plane.

# Arguments
- `y_station::Vector`: Half-breadth offsets at each waterline for this station
- `z::Vector`: Vertical positions (waterlines)

# Returns
- `Float64`: Arc length along the station from keel to highest waterline

# Notes
Uses arc length calculation: L = ∫ √((dy)² + (dz)²)
This properly accounts for hull slope in the vertical direction.
Result should be multiplied by 2 for both sides (port and starboard).
"""
function calculate_station_arc_length(y_station::Vector, z::Vector)
    @assert length(y_station) == length(z) "y_station and z must have same length"

    # Handle single waterline case (at keel)
    if length(z) == 1
        # Just return the half-breadth at keel
        return y_station[1] > 1e-6 ? y_station[1] : 0.0
    end

    arc_length = 0.0

    for i in 1:(length(z)-1)
        dy = y_station[i+1] - y_station[i]
        dz = z[i+1] - z[i]
        ds = √(dy^2 + dz^2)
        arc_length += ds
    end

    # Add closure at keel (from centerline to keel point)
    if y_station[1] > 1e-6
        arc_length += y_station[1]
    end

    return arc_length
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
    ixx, iyy = calculate_second_moments(x, y_wl, area_wp, lcf)
    wl_length = calculate_waterline_length(x, y_wl)

    # For volume, integrate area over depth (set to 0 for single draft)
    # For wetted surface, integrate arc length over depth (set to 0 for single draft)
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
WSA calculation uses station-based integration which properly accounts for hull slope.

The coordinate system assumes:
- x: longitudinal (positive aft, bow at x=0 after normalization)
- y: transverse (half-breadth, positive to port or starboard)
- z: vertical (absolute coordinates from keel upward)
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

    # Calculate waterplane properties at each draft
    for i in 1:num_drafts
        y_wl = y_offsets[:, i]
        areas_wp[i] = calculate_waterplane_area(x, y_wl)
        lcfs[i] = calculate_waterplane_center(x, y_wl)
    end

    # Integrate to get volumes, centers of buoyancy, and wetted surface
    volumes = zeros(num_drafts)
    lcbs = zeros(num_drafts)
    vcbs = zeros(num_drafts)
    wetted_surfaces = zeros(num_drafts)

    # Calculate wetted surface area using station-based approach
    # This properly accounts for hull slope by integrating arc length in y-z plane over x
    num_stations = length(x)

    for i in 1:num_drafts
        # Calculate wetted surface up to this draft
        wsa = 0.0

        # For each station, calculate arc length in y-z plane up to current draft
        station_arcs = zeros(num_stations)
        for j in 1:num_stations
            # Extract y values at this station up to current draft
            y_station = y_offsets[j, 1:i]
            z_station = z[1:i]
            station_arcs[j] = calculate_station_arc_length(y_station, z_station)
        end

        # Integrate station arc lengths over x using trapezoidal rule
        # Factor of 2 accounts for both port and starboard sides
        for j in 1:(num_stations-1)
            dx = x[j+1] - x[j]
            avg_arc = 0.5 * (station_arcs[j] + station_arcs[j+1])
            wsa += 2.0 * avg_arc * dx
        end

        wetted_surfaces[i] = wsa
    end

    # Volume integration
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
    end

    # Build results array
    for i in 1:num_drafts
        y_wl = y_offsets[:, i]
        ixx, iyy = calculate_second_moments(x, y_wl, areas_wp[i], lcfs[i])
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
wetted_surface_area(props::HydrostaticProperties) = props.wsa

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
        zstop=draft)

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

# ============================================================================
# Float Equilibrium Solving
# ============================================================================

"""
    get_max_beam(y_offsets::Matrix, draft_idx::Int)

Get the maximum beam (full breadth) at a given waterline.

# Arguments
- `y_offsets::Matrix`: Half-breadth offsets [x_idx, z_idx]
- `draft_idx::Int`: Index of the waterline

# Returns
- `Float64`: Maximum beam (2 × max half-breadth)
"""
function get_max_beam(y_offsets::Matrix, draft_idx::Int)
    return 2.0 * maximum(y_offsets[:, draft_idx])
end

"""
    interpolate_hydrostatics(results::Vector{HydrostaticProperties}, target_draft::Float64)

Interpolate hydrostatic properties at a target draft between calculated values.

# Arguments
- `results::Vector{HydrostaticProperties}`: Hydrostatic properties at discrete drafts
- `target_draft::Float64`: Target draft for interpolation

# Returns
- `HydrostaticProperties`: Interpolated properties at target_draft

# Notes
Uses linear interpolation between adjacent draft values.
If target is outside the range, returns the nearest boundary value.
"""
function interpolate_hydrostatics(results::Vector{HydrostaticProperties}, target_draft::Float64)
    @assert !isempty(results) "Results vector cannot be empty"

    # Handle edge cases
    if target_draft <= results[1].draft
        return results[1]
    end
    if target_draft >= results[end].draft
        return results[end]
    end

    # Find surrounding indices
    idx_upper = findfirst(r -> r.draft >= target_draft, results)
    if idx_upper === nothing || idx_upper == 1
        return results[end]
    end

    idx_lower = idx_upper - 1
    r_lower = results[idx_lower]
    r_upper = results[idx_upper]

    # Linear interpolation factor
    α = (target_draft - r_lower.draft) / (r_upper.draft - r_lower.draft)

    # Interpolate all properties
    volume = r_lower.volume + α * (r_upper.volume - r_lower.volume)
    waterplane_area = r_lower.waterplane_area + α * (r_upper.waterplane_area - r_lower.waterplane_area)
    lcb = r_lower.lcb + α * (r_upper.lcb - r_lower.lcb)
    vcb = r_lower.vcb + α * (r_upper.vcb - r_lower.vcb)
    lcf = r_lower.lcf + α * (r_upper.lcf - r_lower.lcf)
    ixx = r_lower.ixx + α * (r_upper.ixx - r_lower.ixx)
    iyy = r_lower.iyy + α * (r_upper.iyy - r_lower.iyy)
    wsa = r_lower.wsa + α * (r_upper.wsa - r_lower.wsa)
    waterline_length = r_lower.waterline_length + α * (r_upper.waterline_length - r_lower.waterline_length)

    return HydrostaticProperties(
        target_draft, volume, waterplane_area,
        lcb, vcb, lcf, ixx, iyy, wsa, waterline_length
    )
end

"""
    adjust_for_trim(x::Vector, y_offsets::Matrix, z::Vector, mean_draft::Float64,
                    trim_angle::Float64, lcg::Float64)

Calculate hydrostatics with trim angle applied.

# Arguments
- `x::Vector`: Longitudinal positions
- `y_offsets::Matrix`: Half-breadth offsets
- `z::Vector`: Vertical positions
- `mean_draft::Float64`: Mean draft
- `trim_angle::Float64`: Trim angle in radians (positive = bow up)
- `lcg::Float64`: Longitudinal center of gravity

# Returns
- `HydrostaticProperties`: Hydrostatics accounting for trim

# Notes
Adjusts draft at each station: draft(x_i) = mean_draft + (x_i - lcg) * sin(trim_angle)
For small angles, sin(θ) ≈ tan(θ) ≈ θ
"""
function adjust_for_trim(x::Vector, y_offsets::Matrix, z::Vector,
                        mean_draft::Float64, trim_angle::Float64, lcg::Float64)
    n_stations = length(x)
    n_waterlines = length(z)

    # Create adjusted offset matrix
    y_adjusted = zeros(n_stations, n_waterlines)

    # For each station, find the waterline at the adjusted draft
    for i in 1:n_stations
        # Draft at this station due to trim
        local_draft = mean_draft + (x[i] - lcg) * sin(trim_angle)

        # Find waterline index for this draft
        z_idx = findfirst(z_val -> z_val >= local_draft, z)

        if z_idx === nothing
            # Draft exceeds available data
            y_adjusted[i, :] = y_offsets[i, :]
        elseif z_idx == 1
            # Below minimum draft
            y_adjusted[i, :] .= 0.0
        else
            # Interpolate half-breadths at this draft
            α = (local_draft - z[z_idx-1]) / (z[z_idx] - z[z_idx-1])
            for j in 1:n_waterlines
                if z[j] <= local_draft
                    y_adjusted[i, j] = y_offsets[i, z_idx-1] + α * (y_offsets[i, z_idx] - y_offsets[i, z_idx-1])
                else
                    y_adjusted[i, j] = 0.0
                end
            end
        end
    end

    # Calculate hydrostatics with adjusted offsets
    results = calculate_hydrostatics(x, y_adjusted, z)

    # Return properties at mean draft
    draft_idx = findfirst(z_val -> z_val >= mean_draft, z)
    if draft_idx === nothing
        draft_idx = length(z)
    end

    return results[draft_idx]
end

"""
    solve_equilibrium_float(x, y_offsets, z, mass, water_density, cog; kwargs...)

Solve for equilibrium draft and trim using Newton-Raphson method.

# Arguments
- `x::Vector`: Longitudinal positions (stations)
- `y_offsets::Matrix`: Half-breadth offsets [x_idx, z_idx]
- `z::Vector`: Vertical positions (drafts)
- `mass::Float64`: Ship mass (kg or tonnes)
- `water_density::Float64`: Water density (kg/m³ or tonnes/m³)
- `cog::Tuple{Float64,Float64,Float64}`: Center of gravity (LCG, TCG, VCG)

# Keyword Arguments
- `draft_guess::Union{Nothing,Float64}`: Initial draft guess (default: 10% of max draft)
- `trim_guess::Float64`: Initial trim angle guess in radians (default: 0.0)
- `max_iterations::Int`: Maximum Newton-Raphson iterations (default: 50)
- `tolerance::Float64`: Convergence tolerance (default: 1e-6)
- `verbose::Bool`: Print iteration details (default: false)

# Returns
- `FloatEquilibrium`: Struct containing equilibrium solution

# Notes
Solves two equations:
1. Force balance: ρ × ∇ = m
2. Moment balance: (LCB - LCG) × ρ × ∇ = 0

Uses Newton-Raphson with numerical Jacobian.
"""
function solve_equilibrium_float(
    x::Vector,
    y_offsets::Matrix,
    z::Vector,
    mass::Float64,
    water_density::Float64,
    cog::Tuple{Float64,Float64,Float64};
    draft_guess::Union{Nothing,Float64}=nothing,
    trim_guess::Float64=0.0,
    max_iterations::Int=50,
    tolerance::Float64=1e-6,
    verbose::Bool=false
)
    # Extract CoG components
    lcg, tcg, vcg = cog

    # Pre-calculate full hydrostatics for interpolation
    results_full = calculate_hydrostatics(x, y_offsets, z)

    # Set initial draft guess
    if draft_guess === nothing
        # Use bisection to find a draft with volume close to target
        target_volume = mass / water_density

        # Find draft range where volume brackets the target
        draft_min = z[1]
        draft_max = z[end]

        # Check if target is achievable
        vol_max = results_full[end].volume
        if target_volume > vol_max
            if verbose
                @warn "Target volume ($target_volume m³) exceeds max volume ($vol_max m³)"
            end
            draft_guess = draft_max
        else
            # Bisection to find draft with target volume
            for _ in 1:20
                draft_mid = 0.5 * (draft_min + draft_max)
                props_mid = interpolate_hydrostatics(results_full, draft_mid)

                if abs(props_mid.volume - target_volume) < 0.01 * target_volume
                    draft_guess = draft_mid
                    break
                end

                if props_mid.volume < target_volume
                    draft_min = draft_mid
                else
                    draft_max = draft_mid
                end
            end
            draft_guess = 0.5 * (draft_min + draft_max)
        end

        if verbose
            println("Initial draft guess from bisection: $(round(draft_guess, digits=4)) m")
        end
    end

    # Define residual function
    function residuals(draft::Float64, trim::Float64)
        # Get hydrostatics at current draft/trim
        if abs(trim) < 1e-8
            # No trim, use direct interpolation
            props = interpolate_hydrostatics(results_full, draft)
        else
            # With trim, need to adjust
            props = adjust_for_trim(x, y_offsets, z, draft, trim, lcg)
        end

        # Residual 1: Force balance (ρ × ∇ - m = 0)
        R1 = props.volume * water_density - mass

        # Residual 2: Moment balance ((LCB - LCG) × ρ × ∇ = 0)
        R2 = (props.lcb - lcg) * props.volume * water_density

        return [R1, R2], props
    end

    # Newton-Raphson iteration with damping
    draft = draft_guess
    trim = trim_guess
    converged = false
    iter = 0
    residual_norm = Inf
    final_props = nothing

    # Damping factor for step size control
    α_damp = 1.0  # Start with full Newton step

    for iter in 1:max_iterations
        # Evaluate residuals
        R, props = residuals(draft, trim)
        residual_norm = sqrt(R[1]^2 + R[2]^2)
        final_props = props

        if verbose
            println("Iteration $iter: draft=$(round(draft, digits=4)), trim=$(round(rad2deg(trim), digits=4))°, ||R||=$(round(residual_norm, digits=4))")
        end

        # Check convergence
        if residual_norm < tolerance
            converged = true
            if verbose
                println("Converged!")
            end
            break
        end

        # Calculate numerical Jacobian with forward differences
        δ_draft = max(1e-5, 0.001 * abs(draft))  # Adaptive delta
        δ_trim = 1e-5

        R_draft_plus, _ = residuals(draft + δ_draft, trim)
        R_trim_plus, _ = residuals(draft, trim + δ_trim)

        J = zeros(2, 2)
        J[:, 1] = (R_draft_plus - R) / δ_draft  # ∂R/∂draft
        J[:, 2] = (R_trim_plus - R) / δ_trim    # ∂R/∂trim

        # Check Jacobian condition number
        J_cond = cond(J)
        if J_cond > 1e10
            if verbose
                println("Jacobian ill-conditioned (cond=$J_cond), stopping iterations")
            end
            break
        end

        # Solve for update: J * Δx = -R
        try
            Δ = -J \ R

            # Apply damping with line search
            α = α_damp
            draft_new = draft
            trim_new = trim
            R_new_norm = residual_norm

            # Backtracking line search
            for ls_iter in 1:10
                draft_trial = draft + α * Δ[1]
                trim_trial = trim + α * Δ[2]

                # Limit to valid ranges
                draft_trial = clamp(draft_trial, z[1] + 0.01, z[end])
                trim_trial = clamp(trim_trial, deg2rad(-15), deg2rad(15))

                # Evaluate residual at trial point
                R_trial, _ = residuals(draft_trial, trim_trial)
                R_trial_norm = sqrt(R_trial[1]^2 + R_trial[2]^2)

                # Accept if residual decreased
                if R_trial_norm < residual_norm || ls_iter == 10
                    draft_new = draft_trial
                    trim_new = trim_trial
                    R_new_norm = R_trial_norm

                    # Adjust damping for next iteration
                    if R_trial_norm < residual_norm
                        α_damp = min(1.0, α_damp * 1.2)  # Increase damping
                    else
                        α_damp = max(0.1, α_damp * 0.5)  # Decrease damping
                    end
                    break
                end

                # Reduce step size
                α *= 0.5
            end

            draft = draft_new
            trim = trim_new

        catch e
            if verbose
                println("Jacobian singular, stopping iterations: $e")
            end
            break
        end
    end

    # Calculate form coefficients if FormCoefficients is available
    form_coeffs = nothing
    if FORM_COEFFS_AVAILABLE[] && final_props !== nothing
        try
            loa = x[end] - x[1]
            lwl = final_props.waterline_length
            draft_idx = findfirst(z_val -> z_val >= draft, z)
            if draft_idx === nothing
                draft_idx = length(z)
            end
            beam = get_max_beam(y_offsets, draft_idx)

            form_coeffs = FormCoefficients.calculate_form_coefficients(
                final_props.volume,
                final_props.waterplane_area,
                loa, lwl, beam, draft,
                final_props.lcb,
                y_offsets, z
            )
        catch e
            if verbose
                println("Warning: Could not calculate form coefficients: $e")
            end
        end
    end

    # Return equilibrium solution
    if final_props === nothing
        final_props = interpolate_hydrostatics(results_full, draft)
    end

    return FloatEquilibrium(
        mass,
        water_density,
        cog,
        draft,
        trim,
        final_props.volume,
        final_props,
        form_coeffs,
        iter,
        converged,
        residual_norm
    )
end

"""
    solve_equilibrium_float(filename::String, mass, water_density, cog; kwargs...)

Solve for equilibrium float from a hull geometry file.

# Arguments
- `filename::String`: Path to hull file (STL, etc.)
- `mass::Float64`: Ship mass
- `water_density::Float64`: Water density
- `cog::Tuple{Float64,Float64,Float64}`: Center of gravity (LCG, TCG, VCG)
- `kwargs...`: Additional arguments passed to solve_equilibrium_float

# Keyword Arguments (file loading)
- `n_stations::Int`: Number of longitudinal stations (default: 51)
- `n_waterlines::Int`: Number of vertical waterlines (default: 21)

# Returns
- `FloatEquilibrium`: Equilibrium solution
"""
function solve_equilibrium_float(
    filename::String,
    mass::Float64,
    water_density::Float64,
    cog::Tuple{Float64,Float64,Float64};
    n_stations::Int=51,
    n_waterlines::Int=21,
    kwargs...
)
    # Extract offsets from file
    if !STL_AVAILABLE[]
        error("STL support not available. Make sure STLReader.jl is in the same directory.")
    end

    x, y_offsets, z = STLReader.extract_offsets_from_stl(
        filename,
        n_stations=n_stations,
        n_waterlines=n_waterlines
    )

    # Solve equilibrium
    return solve_equilibrium_float(x, y_offsets, z, mass, water_density, cog; kwargs...)
end

end # module
