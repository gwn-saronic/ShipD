# Stability Analysis and Form Coefficients

Complete guide to stability analysis and form coefficient calculations in the Julia hydrostatics system.

## Overview

The Ship-D Julia hydrostatics system now includes:
1. **Form Coefficients** - Cb, Cp, Cwp, Cm, Cvp
2. **Metacentric Properties** - KB, BM, KM, GM
3. **Stability Analysis** - GZ curves, stability criteria
4. **IMO Compliance Checks** - Basic stability requirements

## Quick Start

### Complete Analysis from Offsets

```julia
include("Hydrostatics.jl")
include("StabilityAnalysis.jl")
include("FormCoefficients.jl")

using .Hydrostatics, .StabilityAnalysis, .FormCoefficients

# 1. Calculate hydrostatics
results = calculate_hydrostatics(x, y_offsets, z)
props = results[end]

# 2. Calculate form coefficients
coeffs = calculate_form_coefficients(
    props.volume, props.waterplane_area,
    LOA, LPP, Beam, Draft, props.lcb,
    y_offsets, z
)

# 3. Calculate metacentric properties
kg = estimate_kg_from_coefficients(Draft, coeffs.cb)
meta = calculate_metacentric_properties(
    props.volume, props.vcb, Draft,
    props.ixx, props.iyy, kg=kg
)

# 4. Generate GZ curve
angles, gz_values = calculate_gz_curve(meta)

# 5. Check stability criteria
criteria = check_stability_criteria(angles, gz_values, meta.gm_t)

println("GM: $(meta.gm_t) m")
println("Meets IMO criteria: $(criteria.meets_imo_criteria)")
```

### Quick Analysis from STL

```julia
include("Hydrostatics.jl")
include("StabilityAnalysis.jl")
include("FormCoefficients.jl")

using .Hydrostatics, .StabilityAnalysis, .FormCoefficients

# Single-line STL to stability
results = calculate_hydrostatics_from_file("hull.stl")
props = results[end]

# Estimate dimensions and calculate stability
# (see examples/stl_to_stability.jl for complete workflow)
```

## Form Coefficients

### Block Coefficient (Cb)

**Definition**: Ratio of displaced volume to a rectangular block

```
Cb = ∇ / (L × B × T)
```

**Typical Values:**
- Tankers, bulk carriers: 0.70-0.85
- Cargo ships: 0.55-0.70
- Passenger ships: 0.55-0.65
- Destroyers: 0.45-0.55
- High-speed craft: 0.30-0.45

**Julia API:**
```julia
cb = calculate_block_coefficient(volume, loa, beam, draft)
```

### Prismatic Coefficient (Cp)

**Definition**: Ratio of displaced volume to a prism of midship section area

```
Cp = ∇ / (Am × L)
```

**Typical Values:**
- Fine-ended vessels: 0.55-0.65
- Normal cargo ships: 0.65-0.75
- Full-ended vessels: 0.75-0.85

**Julia API:**
```julia
cp = calculate_prismatic_coefficient(volume, midship_area, loa)
```

### Waterplane Coefficient (Cwp)

**Definition**: Ratio of waterplane area to circumscribing rectangle

```
Cwp = Awp / (L × B)
```

**Typical Values:** 0.70-0.90

**Julia API:**
```julia
cwp = calculate_waterplane_coefficient(waterplane_area, loa, beam)
```

### Midship Coefficient (Cm)

**Definition**: Ratio of midship area to circumscribing rectangle

```
Cm = Am / (B × T)
```

**Typical Values:**
- V-shaped sections: 0.70-0.85
- U-shaped sections: 0.85-0.99

**Julia API:**
```julia
cm = calculate_midship_coefficient(midship_area, beam, draft)
```

### Vertical Prismatic Coefficient (Cvp)

**Definition**: Vertical distribution of volume

```
Cvp = ∇ / (Awp × T)
```

**Typical Values:** 0.70-0.85

**Julia API:**
```julia
cvp = calculate_vertical_prismatic_coefficient(volume, waterplane_area, draft)
```

### Relationships Between Coefficients

```
Cb = Cp × Cm
```

This relationship is checked by the `validate_coefficients()` function.

## Metacentric Properties

### Center of Buoyancy Height (KB)

Height of center of buoyancy above keel:

```
KB = Draft + VCB
```

Where VCB is from waterline (negative below).

### Metacentric Radius (BM)

Distance from center of buoyancy to metacenter:

```
BM_t = Ixx / ∇    (transverse)
BM_l = Iyy / ∇    (longitudinal)
```

Where Ixx, Iyy are second moments of waterplane area.

### Metacentric Height (KM)

Height of metacenter above keel:

```
KM = KB + BM
```

### Metacentric Height (GM)

**Most important stability parameter:**

```
GM = KM - KG
```

Where KG is height of center of gravity above keel.

**Interpretation:**
- GM > 1.0 m: Stiff (fast rolling, uncomfortable)
- GM 0.5-1.0 m: Normal (good stability and comfort)
- GM 0.15-0.5 m: Tender (slow rolling, comfortable but less stable)
- GM < 0.15 m: Low (inadequate stability)
- GM < 0: **Unstable** (will capsize)

**Julia API:**
```julia
meta = calculate_metacentric_properties(
    volume, vcb, draft, ixx, iyy, kg=kg
)

# Access properties
kb = meta.kb
bm_t = meta.bm_t
gm_t = meta.gm_t  # Returns nothing if KG not provided
```

## Righting Arm (GZ) Curves

The righting arm GZ represents the transverse distance between the lines of action of buoyancy and gravity at a given heel angle.

### Small Angle Approximation

For heel angles up to ~10-15°:

```
GZ = GM × sin(θ)
```

### Julia API

```julia
# Generate GZ curve
angles, gz_values = calculate_gz_curve(
    meta_props,
    max_angle=90.0,  # degrees
    n_points=19
)

# Plot or analyze
for (angle, gz) in zip(angles, gz_values)
    println("$angle°: $gz m")
end
```

**Note:** Current implementation uses small-angle approximation with corrections. For precise large-angle calculations, iterative methods to find heeled waterlines are needed.

## Stability Criteria

### IMO Basic Stability Criteria

For vessels less than 70m (simplified):

1. **GM ≥ 0.15 m** (or 0.35 m for passenger vessels)
2. **Maximum GZ ≥ 0.20 m**
3. **Angle of maximum GZ ≥ 25°**
4. **Range of positive stability ≥ 60°**
5. **Area under GZ curve to 30° ≥ 0.055 m·rad**
6. **Area under GZ curve to 40° ≥ 0.090 m·rad**
7. **Area between 30° and 40° ≥ 0.030 m·rad**

### Julia API

```julia
criteria = check_stability_criteria(
    angles,
    gz_values,
    gm,
    min_gm=0.15  # Minimum required GM
)

# Check results
if criteria.meets_imo_criteria
    println("✓ Passes basic IMO criteria")
else
    println("✗ Does not meet IMO criteria")
end

# Access specific checks
println("GM adequate: $(criteria.gm_adequate)")
println("Max GZ: $(criteria.max_gz) m")
println("Angle of max GZ: $(criteria.angle_of_max_gz)°")
println("Vanishing angle: $(criteria.angle_of_vanishing_stability)°")
println("Area under curve: $(criteria.area_under_curve) m·rad")
```

## Complete Workflow Examples

### Example 1: From Offset Table

```julia
using Hydrostatics, StabilityAnalysis, FormCoefficients

# Given: offset table (x, y_offsets, z) and dimensions
LOA, Beam, Draft = 100.0, 15.0, 6.0

# Step 1: Hydrostatics
results = calculate_hydrostatics(x, y_offsets, z)
props = results[end]

# Step 2: Form coefficients
coeffs = calculate_form_coefficients(
    props.volume, props.waterplane_area,
    LOA, LOA*0.95, Beam, Draft, props.lcb,
    y_offsets, z
)

# Step 3: Estimate KG
kg = estimate_kg_from_coefficients(Draft, coeffs.cb, vessel_type=:cargo)

# Step 4: Metacentric properties
meta = calculate_metacentric_properties(
    props.volume, props.vcb, Draft,
    props.ixx, props.iyy, kg=kg
)

# Step 5: GZ curve
angles, gz_values = calculate_gz_curve(meta)

# Step 6: Check criteria
criteria = check_stability_criteria(angles, gz_values, meta.gm_t)

# Report
println("Analysis Results:")
println("  Cb:  $(coeffs.cb)")
println("  GM:  $(meta.gm_t) m")
println("  IMO: $(criteria.meets_imo_criteria ? "PASS" : "FAIL")")
```

### Example 2: From STL File

See `examples/stl_to_stability.jl` for complete workflow.

### Example 3: Batch Analysis

```julia
# Analyze multiple hulls
results_all = []

for hull_file in readdir("hulls/", join=true)
    if endswith(hull_file, ".stl")
        props, coeffs, meta, criteria = analyze_hull_from_stl(hull_file)
        push!(results_all, (hull_file, coeffs.cb, meta.gm_t, criteria.meets_imo_criteria))
    end
end

# Find best hull
best_hull = maximum(results_all, by=x->x[3])  # Maximum GM
println("Best stability: $(best_hull[1]) with GM = $(best_hull[3]) m")
```

## Estimation and Approximations

### KG Estimation

When actual KG is not known:

```julia
kg = estimate_kg_from_coefficients(draft, cb, vessel_type=:cargo)
```

**Typical KG/T ratios:**
- Cargo ships: 0.55-0.65
- Tankers: 0.45-0.55
- Container ships: 0.75-0.95
- Passenger ships: 0.80-1.20

**Warning:** This is a rough estimate. Always use actual lightship KG when available.

### Midship Area Estimation

When offset table not available:

```julia
# Estimated from Cb and Cp relationship
# Am ≈ ∇ / (Cp × L)
```

The `calculate_form_coefficients()` function does this automatically when y_offsets not provided.

## Validation and Quality Checks

### Validate Coefficients

```julia
is_valid, warnings = validate_coefficients(coeffs)

if !is_valid
    println("Validation failed!")
end

for warning in warnings
    println("⚠ $warning")
end
```

Checks:
- Coefficients within typical ranges
- Relationship Cb ≈ Cp × Cm
- Physical constraints (Cp ≤ 1.0, etc.)

## Limitations and Disclaimers

### Current Limitations

1. **GZ Curve**: Uses small-angle approximation with corrections. For precise large-angle stability, need iterative heeled waterline calculation.

2. **Loading Conditions**: Analysis is for single loading condition. Actual vessels need analysis at multiple loading conditions (loaded, ballast, etc.).

3. **Free Surface Effect**: Not included. Free surface of liquids in tanks reduces effective GM.

4. **Weather Criterion**: IMO weather criterion (wind heeling moment) not assessed.

5. **Damaged Stability**: No damage scenarios considered.

### When to Use

**Suitable for:**
- Preliminary design
- Comparative studies
- Design optimization
- Quick assessments
- Teaching/learning

**Not suitable for:**
- Final classification approval
- Official stability booklet
- Regulatory submission

For final approval, detailed analysis with:
- Multiple loading conditions
- Free surface corrections
- Grain heeling moment (cargo ships)
- Wind heeling moment
- Damage scenarios (passenger vessels)
- Classification society rules

## References

1. **IMO Criteria**: International Code on Intact Stability, 2008
2. **Form Coefficients**: Principles of Naval Architecture, SNAME
3. **Stability Analysis**: Ship Stability for Masters and Mates, Bryan Barrass

## API Summary

### FormCoefficients Module

```julia
calculate_form_coefficients(volume, awp, loa, lpp, beam, draft, lcb, [y_offsets, z])
calculate_block_coefficient(volume, loa, beam, draft)
calculate_prismatic_coefficient(volume, midship_area, loa)
calculate_waterplane_coefficient(waterplane_area, loa, beam)
calculate_midship_coefficient(midship_area, beam, draft)
calculate_vertical_prismatic_coefficient(volume, awp, draft)
calculate_midship_area(y_offsets, z, midship_idx)
estimate_kg_from_coefficients(draft, cb; vessel_type=:cargo)
validate_coefficients(coeffs)
```

### StabilityAnalysis Module

```julia
calculate_metacentric_properties(volume, vcb, draft, ixx, iyy; kg=nothing)
calculate_gz_curve(meta_props; max_angle=90, n_points=19)
calculate_righting_arm_small_angle(gm, theta)
check_stability_criteria(angles, gz_values, gm; min_gm=0.15)
```

## Examples Directory

- `stability_analysis_demo.jl` - Complete demonstration with synthetic hull
- `stl_to_stability.jl` - STL file to stability report workflow
- `hydrostatics_multi_input.jl` - Multiple input methods

---

**Last Updated**: 2026-01-28
**Version**: 1.0
**Status**: Production-ready for preliminary design
