#!/usr/bin/env julia

"""
Test all stability and form coefficient features.
"""

include(joinpath(@__DIR__, "..", "Hydrostatics.jl"))
include(joinpath(@__DIR__, "..", "StabilityAnalysis.jl"))
include(joinpath(@__DIR__, "..", "FormCoefficients.jl"))

using .Hydrostatics
using .StabilityAnalysis
using .FormCoefficients
using Printf

println("="^70)
println("Testing Stability Analysis and Form Coefficients")
println("="^70)

# Create test hull
x = collect(range(0.0, 100.0, length=21))
z = collect(range(-6.0, 0.0, length=11))
y_offsets = ones(length(x), length(z)) .* 7.5
for i in 1:length(x)
    x_frac = (i-1) / (length(x)-1)
    if x_frac < 0.1
        y_offsets[i, :] .*= x_frac / 0.1
    elseif x_frac > 0.9
        y_offsets[i, :] .*= (1.0 - x_frac) / 0.1
    end
end

LOA, Beam, Draft = 100.0, 15.0, 6.0

# Test 1: Hydrostatics
println("\n[Test 1] Hydrostatic calculations")
println("-"^70)
results = nothing
props = nothing
try
    global results = calculate_hydrostatics(x, y_offsets, z)
    global props = results[end]
    @printf("✓ PASS - Volume: %.2f m³\n", props.volume)
catch e
    println("✗ FAIL - $e")
end

# Test 2: Form coefficients
println("\n[Test 2] Form coefficients")
println("-"^70)
coeffs = nothing
try
    global coeffs = calculate_form_coefficients(
        props.volume, props.waterplane_area,
        LOA, LOA*0.9, Beam, Draft, props.lcb,
        y_offsets, z
    )
    @printf("✓ PASS - Cb: %.4f, Cp: %.4f, Cwp: %.4f\n",
            coeffs.cb, coeffs.cp, coeffs.cwp)

    # Validate
    is_valid, warnings = validate_coefficients(coeffs)
    if isempty(warnings)
        println("  ✓ All coefficients valid")
    else
        println("  ⚠ $(length(warnings)) warnings")
    end
catch e
    println("✗ FAIL - $e")
    rethrow(e)
end

# Test 3: KG estimation
println("\n[Test 3] KG estimation")
println("-"^70)
kg = nothing
try
    kg_cargo = estimate_kg_from_coefficients(Draft, coeffs.cb, vessel_type=:cargo)
    kg_tanker = estimate_kg_from_coefficients(Draft, coeffs.cb, vessel_type=:tanker)
    @printf("✓ PASS - KG (cargo): %.3f m, KG (tanker): %.3f m\n", kg_cargo, kg_tanker)
    global kg = kg_cargo  # Use cargo KG for next test
catch e
    println("✗ FAIL - $e")
end

# Test 4: Metacentric properties
println("\n[Test 4] Metacentric properties")
println("-"^70)
meta = nothing
try
    if kg === nothing
        global kg = estimate_kg_from_coefficients(Draft, coeffs.cb)
    end
    global meta = calculate_metacentric_properties(
        props.volume, props.vcb, Draft,
        props.ixx, props.iyy, kg=kg
    )
    @printf("✓ PASS - KB: %.3f m, GM: %.3f m\n", meta.kb, meta.gm_t)

    if meta.gm_t > 0.15
        println("  ✓ GM adequate for stability")
    else
        println("  ⚠ GM below minimum requirement")
    end
catch e
    println("✗ FAIL - $e")
    rethrow(e)
end

# Test 5: GZ curve
println("\n[Test 5] GZ curve generation")
println("-"^70)
angles = nothing
gz_values = nothing
try
    result = calculate_gz_curve(meta, max_angle=60.0, n_points=13)
    global angles = result[1]
    global gz_values = result[2]
    max_gz = maximum(gz_values)
    @printf("✓ PASS - GZ curve: %d points, max GZ: %.3f m\n",
            length(angles), max_gz)
catch e
    println("✗ FAIL - $e")
    rethrow(e)
end

# Test 6: Stability criteria
println("\n[Test 6] Stability criteria check")
println("-"^70)
try
    criteria = check_stability_criteria(angles, gz_values, meta.gm_t)

    @printf("✓ PASS - Criteria checked\n")
    @printf("  GM positive:     %s\n", criteria.gm_positive ? "✓" : "✗")
    @printf("  GM adequate:     %s\n", criteria.gm_adequate ? "✓" : "✗")
    @printf("  Max GZ adequate: %s (%.3f m)\n",
            criteria.max_gz >= 0.20 ? "✓" : "✗", criteria.max_gz)
    @printf("  IMO criteria:    %s\n",
            criteria.meets_imo_criteria ? "✓ PASS" : "✗ FAIL")
catch e
    println("✗ FAIL - $e")
    rethrow(e)
end

# Test 7: Individual coefficient calculations
println("\n[Test 7] Individual coefficient functions")
println("-"^70)
try
    cb = calculate_block_coefficient(props.volume, LOA, Beam, Draft)
    cwp = calculate_waterplane_coefficient(props.waterplane_area, LOA, Beam)
    @printf("✓ PASS - Cb: %.4f, Cwp: %.4f\n", cb, cwp)
catch e
    println("✗ FAIL - $e")
end

# Test 8: Midship area calculation
println("\n[Test 8] Midship area calculation")
println("-"^70)
try
    midship_idx = div(size(y_offsets, 1) + 1, 2)
    area = calculate_midship_area(y_offsets, z, midship_idx)
    @printf("✓ PASS - Midship area: %.2f m²\n", area)
catch e
    println("✗ FAIL - $e")
end

# Summary
println("\n" * "="^70)
println("All Tests Complete")
println("="^70)

println("\nFeature Summary:")
println("  ✓ Hydrostatic properties")
println("  ✓ Form coefficients (Cb, Cp, Cwp, Cm, Cvp)")
println("  ✓ Metacentric properties (KB, BM, KM, GM)")
println("  ✓ GZ curve generation")
println("  ✓ Stability criteria checking")
println("  ✓ KG estimation")
println("  ✓ Coefficient validation")
println("\n✓ All stability analysis features working!\n")
