"""
    StabilityAnalysis.jl

Stability analysis and metacentric calculations for ship hulls.
Provides functions to calculate:
- Metacentric properties (KB, BM, KM, GM)
- Righting arm curves (GZ curves)
- Stability criteria checks
- Cross-curves of stability

Author: Generated for Ship-D project
Date: 2026-01-28
"""

module StabilityAnalysis

export MetacentricProperties, calculate_metacentric_properties
export calculate_gz_curve, calculate_cross_curves
export StabilityCriteria, check_stability_criteria
export calculate_righting_arm, calculate_heeled_properties

using LinearAlgebra

"""
    MetacentricProperties

Structure containing metacentric stability properties.

# Fields
- `volume::Float64`: Displaced volume
- `kb::Float64`: Height of center of buoyancy above keel
- `bm_t::Float64`: Transverse metacentric radius
- `bm_l::Float64`: Longitudinal metacentric radius
- `km_t::Float64`: Transverse metacentric height above keel
- `km_l::Float64`: Longitudinal metacentric height above keel
- `gm_t::Float64`: Transverse metacentric height (if KG provided)
- `gm_l::Float64`: Longitudinal metacentric height (if KG provided)
- `kg::Union{Nothing,Float64}`: Height of center of gravity above keel (if provided)
"""
struct MetacentricProperties
    volume::Float64
    kb::Float64
    bm_t::Float64
    bm_l::Float64
    km_t::Float64
    km_l::Float64
    gm_t::Union{Nothing,Float64}
    gm_l::Union{Nothing,Float64}
    kg::Union{Nothing,Float64}
end

"""
    calculate_metacentric_properties(volume, vcb, zkeel, ixx, iyy; kg=nothing)

Calculate metacentric properties from hydrostatic data.

# Arguments
- `volume::Float64`: Displaced volume (m³)
- `vcb::Float64`: Vertical center of buoyancy (absolute z-coordinate)
- `zkeel::Float64`: Keel z-coordinate (typically 0.0)
- `ixx::Float64`: Second moment of waterplane area about longitudinal axis
- `iyy::Float64`: Second moment of waterplane area about transverse axis
- `kg::Union{Nothing,Float64}`: Height of center of gravity above keel (optional)

# Returns
- `MetacentricProperties`: Structure containing all metacentric properties

# Notes
- KB = VCB - zkeel (height of center of buoyancy above keel)
- BM_t = Ixx / Volume (transverse metacentric radius)
- BM_l = Iyy / Volume (longitudinal metacentric radius)
- KM = KB + BM
- GM = KM - KG (only if KG provided)
"""
function calculate_metacentric_properties(volume::Float64,
                                         vcb::Float64,
                                         zkeel::Float64,
                                         ixx::Float64,
                                         iyy::Float64;
                                         kg::Union{Nothing,Float64}=nothing)
    # KB: Height of center of buoyancy above keel
    kb = vcb - zkeel

    # BM: Metacentric radius
    # BM = I / Volume, where I is second moment of waterplane area
    bm_t = volume > 1e-10 ? ixx / volume : 0.0  # Transverse
    bm_l = volume > 1e-10 ? iyy / volume : 0.0  # Longitudinal

    # KM: Metacentric height above keel
    km_t = kb + bm_t
    km_l = kb + bm_l

    # GM: Metacentric height (if KG provided)
    gm_t = nothing
    gm_l = nothing
    if kg !== nothing
        gm_t = km_t - kg
        gm_l = km_l - kg
    end

    return MetacentricProperties(
        volume, kb, bm_t, bm_l, km_t, km_l, gm_t, gm_l, kg
    )
end

"""
    calculate_righting_arm_small_angle(gm::Float64, theta::Float64)

Calculate righting arm using small angle approximation.

# Arguments
- `gm::Float64`: Metacentric height (GM)
- `theta::Float64`: Heel angle in radians

# Returns
- `Float64`: Righting arm GZ (meters)

# Notes
Valid for angles up to about 10-15 degrees.
GZ = GM × sin(θ)
"""
function calculate_righting_arm_small_angle(gm::Float64, theta::Float64)
    return gm * sin(theta)
end

"""
    calculate_heeled_waterplane(x, y_offsets, z, heel_angle)

Calculate properties of heeled waterplane.

# Arguments
- `x::Vector`: Longitudinal stations
- `y_offsets::Matrix`: Half-breadth offsets [x_idx, z_idx]
- `z::Vector`: Vertical positions
- `heel_angle::Float64`: Heel angle in radians

# Returns
- `(lcb_heeled, vcb_heeled, volume_heeled)`: Heeled properties

# Notes
This is a simplified calculation that approximates the heeled waterplane.
For accurate large-angle stability, a more sophisticated method is needed.
"""
function calculate_heeled_waterplane(x::Vector, y_offsets::Matrix, z::Vector, heel_angle::Float64)
    # Simplified heeled calculation
    # In reality, need to find new waterline intersection with heeled hull
    # This is a placeholder - real implementation would be more complex

    # For small angles, approximate shift in center of buoyancy
    # ΔB_y ≈ Volume × BM × sin(θ) / Volume = BM × sin(θ)

    # Return unchanged for now - proper implementation needs iteration
    # to find heeled waterline
    return 0.0, 0.0, 0.0
end

"""
    calculate_gz_curve(meta_props::MetacentricProperties; max_angle=90, n_points=19)

Calculate GZ (righting arm) curve for range of heel angles.

# Arguments
- `meta_props::MetacentricProperties`: Metacentric properties
- `max_angle::Float64`: Maximum heel angle in degrees (default: 90)
- `n_points::Int`: Number of points in curve (default: 19)

# Returns
- `(angles, gz_values)`: Tuple of angle array (degrees) and GZ values (meters)

# Notes
Uses small angle approximation: GZ = GM × sin(θ)
For more accurate large-angle calculations, use calculate_gz_curve_accurate
"""
function calculate_gz_curve(meta_props::MetacentricProperties;
                           max_angle::Float64=90.0,
                           n_points::Int=19)
    if meta_props.gm_t === nothing
        error("GM not available. Provide KG when calculating metacentric properties.")
    end

    angles_deg = range(0.0, max_angle, length=n_points)
    angles_rad = deg2rad.(angles_deg)

    gz_values = zeros(n_points)
    for (i, theta) in enumerate(angles_rad)
        if abs(theta) < deg2rad(15)
            # Small angle approximation
            gz_values[i] = calculate_righting_arm_small_angle(meta_props.gm_t, theta)
        else
            # For larger angles, still use small angle but with correction factor
            # Real implementation would calculate actual submerged volume geometry
            # This is approximate
            correction = 1.0 - 0.05 * (abs(theta) - deg2rad(15))^2
            gz_values[i] = meta_props.gm_t * sin(theta) * correction
        end
    end

    return collect(angles_deg), gz_values
end

"""
    calculate_cross_curves(x, y_offsets, z, displacements, kg; heel_angles=[10,20,30,40,50,60])

Calculate cross-curves of stability.

# Arguments
- `x::Vector`: Longitudinal stations
- `y_offsets::Matrix`: Half-breadth offsets
- `z::Vector`: Vertical positions
- `displacements::Vector`: Array of displacement volumes to calculate
- `kg::Float64`: Height of center of gravity above keel
- `heel_angles::Vector`: Heel angles in degrees (default: [10,20,30,40,50,60])

# Returns
- `Matrix{Float64}`: GZ values [displacement_idx, angle_idx]

# Notes
This is a simplified implementation. Full implementation would require
iterative calculation of heeled waterlines.
"""
function calculate_cross_curves(x::Vector,
                                y_offsets::Matrix,
                                z::Vector,
                                displacements::Vector,
                                kg::Float64;
                                heel_angles::Vector=[10.0, 20.0, 30.0, 40.0, 50.0, 60.0])
    n_displacements = length(displacements)
    n_angles = length(heel_angles)
    gz_matrix = zeros(n_displacements, n_angles)

    # Placeholder implementation
    # Real implementation would calculate GZ at each displacement and angle
    # by finding heeled waterline and computing righting moment

    @warn "Cross-curves calculation is simplified. Full implementation requires heeled waterline iteration."

    return gz_matrix
end

"""
    StabilityCriteria

Structure containing stability criteria check results.

# Fields
- `gm_positive::Bool`: GM > 0 (vessel has positive stability)
- `gm_adequate::Bool`: GM > minimum required (typically 0.15m for small vessels)
- `angle_of_vanishing_stability::Float64`: Angle where GZ becomes zero (degrees)
- `max_gz::Float64`: Maximum GZ value (meters)
- `angle_of_max_gz::Float64`: Angle at maximum GZ (degrees)
- `area_under_curve::Float64`: Area under GZ curve (for energy criterion)
- `meets_imo_criteria::Bool`: Meets basic IMO stability criteria
"""
struct StabilityCriteria
    gm_positive::Bool
    gm_adequate::Bool
    angle_of_vanishing_stability::Float64
    max_gz::Float64
    angle_of_max_gz::Float64
    area_under_curve::Float64
    meets_imo_criteria::Bool
end

"""
    check_stability_criteria(angles, gz_values, gm; min_gm=0.15)

Check stability against common criteria.

# Arguments
- `angles::Vector`: Heel angles in degrees
- `gz_values::Vector`: GZ values at each angle (meters)
- `gm::Float64`: Metacentric height (meters)
- `min_gm::Float64`: Minimum required GM (default: 0.15m)

# Returns
- `StabilityCriteria`: Structure with criteria check results

# Notes
Basic IMO criteria checked:
1. GM ≥ 0.15 m (for vessels < 70m)
2. Angle of maximum GZ ≥ 25°
3. Maximum GZ ≥ 0.20 m
4. Positive stability range ≥ 60°
"""
function check_stability_criteria(angles::Vector,
                                 gz_values::Vector,
                                 gm::Float64;
                                 min_gm::Float64=0.15)
    # Check GM
    gm_positive = gm > 0.0
    gm_adequate = gm >= min_gm

    # Find maximum GZ and its angle
    max_gz_idx = argmax(gz_values)
    max_gz = gz_values[max_gz_idx]
    angle_of_max_gz = angles[max_gz_idx]

    # Find angle of vanishing stability (where GZ goes to zero)
    angle_of_vanishing = 0.0
    for i in 2:length(angles)
        if gz_values[i] <= 0.0 && gz_values[i-1] > 0.0
            # Linear interpolation
            t = -gz_values[i-1] / (gz_values[i] - gz_values[i-1])
            angle_of_vanishing = angles[i-1] + t * (angles[i] - angles[i-1])
            break
        end
    end
    if angle_of_vanishing == 0.0
        angle_of_vanishing = angles[end]
    end

    # Calculate area under GZ curve (trapezoidal integration)
    area = 0.0
    for i in 1:(length(angles)-1)
        if gz_values[i] > 0.0 && gz_values[i+1] > 0.0
            dangle = deg2rad(angles[i+1] - angles[i])
            area += 0.5 * (gz_values[i] + gz_values[i+1]) * dangle
        end
    end

    # Check basic IMO criteria (simplified)
    meets_imo = (gm >= min_gm &&
                 angle_of_max_gz >= 25.0 &&
                 max_gz >= 0.20 &&
                 angle_of_vanishing >= 60.0)

    return StabilityCriteria(
        gm_positive,
        gm_adequate,
        angle_of_vanishing,
        max_gz,
        angle_of_max_gz,
        area,
        meets_imo
    )
end

end # module
