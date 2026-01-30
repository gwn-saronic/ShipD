"""
    FormCoefficients.jl

Form coefficient calculations for ship hulls.
Provides functions to calculate:
- Block coefficient (Cb)
- Prismatic coefficient (Cp)
- Waterplane coefficient (Cwp)
- Midship coefficient (Cm)
- Vertical prismatic coefficient (Cvp)
- And other hull form parameters

Author: Generated for Ship-D project
Date: 2026-01-28
"""

module FormCoefficients

export HullFormCoefficients, calculate_form_coefficients
export block_coefficient, prismatic_coefficient, waterplane_coefficient
export midship_coefficient, vertical_prismatic_coefficient
export calculate_midship_area, estimate_kg_from_coefficients
export validate_coefficients

"""
    HullFormCoefficients

Structure containing hull form coefficients.

# Fields
- `loa::Float64`: Length overall
- `lpp::Float64`: Length between perpendiculars (waterline length)
- `beam::Float64`: Maximum beam
- `draft::Float64`: Draft
- `volume::Float64`: Displaced volume
- `waterplane_area::Float64`: Waterplane area
- `midship_area::Float64`: Midship section area
- `cb::Float64`: Block coefficient
- `cp::Float64`: Prismatic coefficient
- `cwp::Float64`: Waterplane coefficient
- `cm::Float64`: Midship coefficient
- `cvp::Float64`: Vertical prismatic coefficient
- `lcb_percent::Float64`: LCB as percentage of LOA from FP
"""
struct HullFormCoefficients
    loa::Float64
    lpp::Float64
    beam::Float64
    draft::Float64
    volume::Float64
    waterplane_area::Float64
    midship_area::Float64
    cb::Float64
    cp::Float64
    cwp::Float64
    cm::Float64
    cvp::Float64
    lcb_percent::Float64
end

"""
    calculate_block_coefficient(volume, loa, beam, draft)

Calculate block coefficient (Cb).

# Arguments
- `volume::Float64`: Displaced volume
- `loa::Float64`: Length overall (or Lpp)
- `beam::Float64`: Maximum beam
- `draft::Float64`: Draft

# Returns
- `Float64`: Block coefficient Cb = ∇ / (L × B × T)

# Notes
Typical values:
- Tankers, bulk carriers: 0.70-0.85
- Cargo ships: 0.55-0.70
- Passenger ships: 0.55-0.65
- Destroyers: 0.45-0.55
- High-speed craft: 0.30-0.45
"""
function calculate_block_coefficient(volume::Float64,
                                    loa::Float64,
                                    beam::Float64,
                                    draft::Float64)
    if loa <= 0 || beam <= 0 || draft <= 0
        return 0.0
    end
    return volume / (loa * beam * draft)
end

"""
    calculate_prismatic_coefficient(volume, midship_area, loa)

Calculate longitudinal prismatic coefficient (Cp).

# Arguments
- `volume::Float64`: Displaced volume
- `midship_area::Float64`: Area of midship section
- `loa::Float64`: Length overall (or Lpp)

# Returns
- `Float64`: Prismatic coefficient Cp = ∇ / (Am × L)

# Notes
Typical values:
- Fine-ended vessels: 0.55-0.65
- Normal cargo ships: 0.65-0.75
- Full-ended vessels: 0.75-0.85
"""
function calculate_prismatic_coefficient(volume::Float64,
                                        midship_area::Float64,
                                        loa::Float64)
    if midship_area <= 0 || loa <= 0
        return 0.0
    end
    return volume / (midship_area * loa)
end

"""
    calculate_waterplane_coefficient(waterplane_area, loa, beam)

Calculate waterplane coefficient (Cwp).

# Arguments
- `waterplane_area::Float64`: Waterplane area
- `loa::Float64`: Length overall (or Lpp)
- `beam::Float64`: Maximum beam

# Returns
- `Float64`: Waterplane coefficient Cwp = Awp / (L × B)

# Notes
Typical values: 0.70-0.90
Higher values indicate fuller waterlines
"""
function calculate_waterplane_coefficient(waterplane_area::Float64,
                                         loa::Float64,
                                         beam::Float64)
    if loa <= 0 || beam <= 0
        return 0.0
    end
    return waterplane_area / (loa * beam)
end

"""
    calculate_midship_coefficient(midship_area, beam, draft)

Calculate midship section coefficient (Cm).

# Arguments
- `midship_area::Float64`: Area of midship section
- `beam::Float64`: Maximum beam
- `draft::Float64`: Draft

# Returns
- `Float64`: Midship coefficient Cm = Am / (B × T)

# Notes
Typical values:
- V-shaped sections: 0.70-0.85
- U-shaped sections: 0.85-0.99
"""
function calculate_midship_coefficient(midship_area::Float64,
                                      beam::Float64,
                                      draft::Float64)
    if beam <= 0 || draft <= 0
        return 0.0
    end
    return midship_area / (beam * draft)
end

"""
    calculate_vertical_prismatic_coefficient(volume, waterplane_area, draft)

Calculate vertical prismatic coefficient (Cvp).

# Arguments
- `volume::Float64`: Displaced volume
- `waterplane_area::Float64`: Waterplane area
- `draft::Float64`: Draft

# Returns
- `Float64`: Vertical prismatic coefficient Cvp = ∇ / (Awp × T)

# Notes
Cvp describes the vertical distribution of volume.
Typical values: 0.70-0.85
"""
function calculate_vertical_prismatic_coefficient(volume::Float64,
                                                 waterplane_area::Float64,
                                                 draft::Float64)
    if waterplane_area <= 0 || draft <= 0
        return 0.0
    end
    return volume / (waterplane_area * draft)
end

"""
    calculate_midship_area(y_offsets, z, midship_idx)

Calculate midship section area from offset table.

# Arguments
- `y_offsets::Matrix`: Half-breadth offsets [x_idx, z_idx]
- `z::Vector`: Vertical positions
- `midship_idx::Int`: Index of midship station

# Returns
- `Float64`: Midship section area

# Notes
Uses trapezoidal integration over the vertical extent.
Multiplies by 2 for both sides of the hull.
"""
function calculate_midship_area(y_offsets::Matrix,
                               z::Vector,
                               midship_idx::Int)
    if midship_idx < 1 || midship_idx > size(y_offsets, 1)
        return 0.0
    end

    y_section = y_offsets[midship_idx, :]
    area = 0.0

    # Trapezoidal integration
    for i in 1:(length(z)-1)
        dz = z[i+1] - z[i]
        area += 0.5 * (y_section[i] + y_section[i+1]) * dz
    end

    # Multiply by 2 for both sides
    return 2.0 * area
end

"""
    calculate_form_coefficients(volume, waterplane_area, loa, lpp, beam, draft,
                               lcb, y_offsets=nothing, z=nothing)

Calculate all form coefficients for a hull.

# Arguments
- `volume::Float64`: Displaced volume
- `waterplane_area::Float64`: Waterplane area at design draft
- `loa::Float64`: Length overall
- `lpp::Float64`: Length between perpendiculars (waterline length)
- `beam::Float64`: Maximum beam (full breadth)
- `draft::Float64`: Design draft
- `lcb::Float64`: Longitudinal center of buoyancy from forward perpendicular
- `y_offsets::Union{Nothing,Matrix}`: Half-breadth offsets (optional, for midship area)
- `z::Union{Nothing,Vector}`: Vertical positions (optional, for midship area)

# Returns
- `HullFormCoefficients`: Structure containing all coefficients

# Notes
If y_offsets and z are not provided, midship area is estimated as:
Am ≈ ∇ / (Cp × L)
where Cp is estimated from Cb
"""
function calculate_form_coefficients(volume::Float64,
                                    waterplane_area::Float64,
                                    loa::Float64,
                                    lpp::Float64,
                                    beam::Float64,
                                    draft::Float64,
                                    lcb::Float64,
                                    y_offsets::Union{Nothing,Matrix}=nothing,
                                    z::Union{Nothing,Vector}=nothing)
    # Calculate block coefficient
    cb = calculate_block_coefficient(volume, lpp, beam, draft)

    # Calculate waterplane coefficient
    cwp = calculate_waterplane_coefficient(waterplane_area, lpp, beam)

    # Calculate vertical prismatic coefficient
    cvp = calculate_vertical_prismatic_coefficient(volume, waterplane_area, draft)

    # Calculate or estimate midship area
    midship_area = 0.0
    if y_offsets !== nothing && z !== nothing
        # Calculate from actual offsets
        midship_idx = div(size(y_offsets, 1) + 1, 2)  # Middle station
        midship_area = calculate_midship_area(y_offsets, z, midship_idx)
    else
        # Estimate from Cb and Cp relationship
        # Cb = Cp × Cm, so Cm ≈ Cb / Cp
        # Typical Cp for merchant ships ≈ 0.75
        cp_est = 0.75
        cm_est = cb / cp_est
        midship_area = cm_est * beam * draft
    end

    # Calculate prismatic coefficient
    cp = calculate_prismatic_coefficient(volume, midship_area, lpp)

    # Calculate midship coefficient
    cm = calculate_midship_coefficient(midship_area, beam, draft)

    # LCB as percentage from FP
    lcb_percent = (lcb / lpp) * 100.0

    return HullFormCoefficients(
        loa, lpp, beam, draft,
        volume, waterplane_area, midship_area,
        cb, cp, cwp, cm, cvp, lcb_percent
    )
end

"""
    block_coefficient(coeffs::HullFormCoefficients)

Extract block coefficient from HullFormCoefficients.
"""
block_coefficient(coeffs::HullFormCoefficients) = coeffs.cb

"""
    prismatic_coefficient(coeffs::HullFormCoefficients)

Extract prismatic coefficient from HullFormCoefficients.
"""
prismatic_coefficient(coeffs::HullFormCoefficients) = coeffs.cp

"""
    waterplane_coefficient(coeffs::HullFormCoefficients)

Extract waterplane coefficient from HullFormCoefficients.
"""
waterplane_coefficient(coeffs::HullFormCoefficients) = coeffs.cwp

"""
    midship_coefficient(coeffs::HullFormCoefficients)

Extract midship coefficient from HullFormCoefficients.
"""
midship_coefficient(coeffs::HullFormCoefficients) = coeffs.cm

"""
    vertical_prismatic_coefficient(coeffs::HullFormCoefficients)

Extract vertical prismatic coefficient from HullFormCoefficients.
"""
vertical_prismatic_coefficient(coeffs::HullFormCoefficients) = coeffs.cvp

"""
    estimate_kg_from_coefficients(draft, cb; vessel_type=:cargo)

Estimate KG (center of gravity height) from form coefficients.

# Arguments
- `draft::Float64`: Design draft
- `cb::Float64`: Block coefficient
- `vessel_type::Symbol`: Type of vessel (:cargo, :tanker, :container, :passenger)

# Returns
- `Float64`: Estimated KG above keel

# Notes
This is a rough estimate based on typical proportions.
Actual KG should be calculated from weight distribution.

Typical KG/T ratios:
- Cargo ships: 0.55-0.65
- Tankers: 0.45-0.55
- Container ships: 0.75-0.95
- Passenger ships: 0.80-1.20
"""
function estimate_kg_from_coefficients(draft::Float64,
                                      cb::Float64;
                                      vessel_type::Symbol=:cargo)
    # These are very rough estimates
    kg_ratio = if vessel_type == :tanker
        0.50
    elseif vessel_type == :container
        0.85
    elseif vessel_type == :passenger
        1.00
    else  # cargo
        0.60
    end

    # Adjust for fullness (higher Cb typically means lower KG/T)
    kg_ratio *= (0.95 + 0.15 * (0.65 - cb))

    return kg_ratio * draft
end

"""
    validate_coefficients(coeffs::HullFormCoefficients)

Validate that form coefficients are within reasonable ranges.

# Arguments
- `coeffs::HullFormCoefficients`: Coefficients to validate

# Returns
- `(Bool, Vector{String})`: Tuple of (is_valid, warnings)

# Notes
Checks typical ranges for each coefficient and relationships between them.
"""
function validate_coefficients(coeffs::HullFormCoefficients)
    warnings = String[]
    is_valid = true

    # Check individual coefficients
    if coeffs.cb < 0.3 || coeffs.cb > 0.9
        push!(warnings, "Block coefficient ($(coeffs.cb)) outside typical range [0.3, 0.9]")
        is_valid = false
    end

    if coeffs.cp < 0.5 || coeffs.cp > 0.9
        push!(warnings, "Prismatic coefficient ($(coeffs.cp)) outside typical range [0.5, 0.9]")
    end

    if coeffs.cwp < 0.6 || coeffs.cwp > 1.0
        push!(warnings, "Waterplane coefficient ($(coeffs.cwp)) outside typical range [0.6, 1.0]")
    end

    if coeffs.cm < 0.7 || coeffs.cm > 1.0
        push!(warnings, "Midship coefficient ($(coeffs.cm)) outside typical range [0.7, 1.0]")
    end

    # Check relationships
    # Cb should equal Cp × Cm (approximately)
    cb_calc = coeffs.cp * coeffs.cm
    if abs(cb_calc - coeffs.cb) / coeffs.cb > 0.1
        push!(warnings, "Cb ($(coeffs.cb)) ≠ Cp × Cm ($(cb_calc)) - difference > 10%")
    end

    # Cp should be less than 1.0
    if coeffs.cp > 1.0
        push!(warnings, "Prismatic coefficient > 1.0 - physically impossible")
        is_valid = false
    end

    return is_valid, warnings
end

end # module
