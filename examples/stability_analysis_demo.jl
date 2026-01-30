"""
    stability_analysis_demo.jl

Comprehensive demonstration of stability analysis and form coefficients.
Shows how to:
1. Calculate hydrostatic properties
2. Compute form coefficients (Cb, Cp, Cwp, Cm, Cvp)
3. Calculate metacentric properties (KB, BM, KM, GM)
4. Generate GZ curves
5. Check stability criteria

Usage:
    julia stability_analysis_demo.jl

Requirements:
    - Julia 1.11+
"""

# Load modules
include(joinpath(dirname(@__DIR__), "Hydrostatics.jl"))
include(joinpath(dirname(@__DIR__), "StabilityAnalysis.jl"))
include(joinpath(dirname(@__DIR__), "FormCoefficients.jl"))

using .Hydrostatics
using .StabilityAnalysis
using .FormCoefficients
using Printf

"""
    create_sample_hull()

Create a sample hull for demonstration.
"""
function create_sample_hull()
    # Hull dimensions
    LOA = 100.0  # meters
    Beam = 15.0  # meters (full breadth)
    Draft = 6.0  # meters

    # Create offset table
    n_stations = 21
    n_waterlines = 11

    x = collect(range(0.0, LOA, length=n_stations))
    z = collect(range(-Draft, 0.0, length=n_waterlines))

    y_offsets = zeros(n_stations, n_waterlines)

    # Generate hull form (cargo ship-like)
    for (i, xi) in enumerate(x)
        for (j, zj) in enumerate(z)
            x_norm = xi / LOA
            z_norm = (zj + Draft) / Draft

            # Longitudinal distribution
            if x_norm < 0.05
                # Extreme bow
                beam_factor = 0.0
            elseif x_norm < 0.2
                # Bow
                beam_factor = ((x_norm - 0.05) / 0.15)^1.5
            elseif x_norm < 0.75
                # Parallel midbody
                beam_factor = 1.0
            elseif x_norm < 0.95
                # Stern
                stern_norm = (x_norm - 0.75) / 0.20
                beam_factor = 1.0 - stern_norm^1.3
            else
                # Extreme stern
                beam_factor = 0.0
            end

            # Vertical distribution (U-shaped sections)
            if z_norm < 0.1
                # Bottom (flat)
                vertical_factor = z_norm / 0.1 * 0.3
            else
                # Sides (nearly vertical)
                vertical_factor = 0.3 + (z_norm - 0.1) / 0.9 * 0.7
            end

            y_offsets[i, j] = 0.5 * Beam * beam_factor * vertical_factor
        end
    end

    return x, y_offsets, z, LOA, Beam, Draft
end

"""
    print_form_coefficients(coeffs::HullFormCoefficients)

Pretty-print form coefficients.
"""
function print_form_coefficients(coeffs::HullFormCoefficients)
    println("\n" * "═" ^ 70)
    println("FORM COEFFICIENTS")
    println("═" ^ 70)

    println("\nPrincipal Dimensions:")
    println("─" ^ 70)
    @printf("  LOA (Length Overall):        %10.2f m\n", coeffs.loa)
    @printf("  LPP (Length between PP):     %10.2f m\n", coeffs.lpp)
    @printf("  Beam (Maximum):              %10.2f m\n", coeffs.beam)
    @printf("  Draft (Design):              %10.2f m\n", coeffs.draft)
    @printf("  Displacement Volume:         %10.2f m³\n", coeffs.volume)

    println("\nForm Coefficients:")
    println("─" ^ 70)
    @printf("  Cb  (Block coefficient):           %.4f\n", coeffs.cb)
    @printf("  Cp  (Prismatic coefficient):       %.4f\n", coeffs.cp)
    @printf("  Cwp (Waterplane coefficient):      %.4f\n", coeffs.cwp)
    @printf("  Cm  (Midship coefficient):         %.4f\n", coeffs.cm)
    @printf("  Cvp (Vertical prismatic coeff):    %.4f\n", coeffs.cvp)

    println("\nPositions:")
    println("─" ^ 70)
    @printf("  LCB (from FP):               %10.2f m (%.1f%% LOA)\n",
            coeffs.lcb_percent / 100.0 * coeffs.lpp, coeffs.lcb_percent)
    @printf("  Midship Area:                %10.2f m²\n", coeffs.midship_area)
    @printf("  Waterplane Area:             %10.2f m²\n", coeffs.waterplane_area)

    # Validate and show warnings
    is_valid, warnings = validate_coefficients(coeffs)
    if !isempty(warnings)
        println("\nValidation Warnings:")
        println("─" ^ 70)
        for warning in warnings
            println("  ⚠ $warning")
        end
    else
        println("\n✓ All coefficients within normal ranges")
    end

    println("═" ^ 70)
end

"""
    print_metacentric_properties(meta::MetacentricProperties)

Pretty-print metacentric properties.
"""
function print_metacentric_properties(meta::MetacentricProperties)
    println("\n" * "═" ^ 70)
    println("METACENTRIC PROPERTIES")
    println("═" ^ 70)

    println("\nVertical Centers:")
    println("─" ^ 70)
    @printf("  Draft:                       %10.3f m\n", meta.draft)
    @printf("  KB (Center of Buoyancy):     %10.3f m above keel\n", meta.kb)
    if meta.kg !== nothing
        @printf("  KG (Center of Gravity):      %10.3f m above keel\n", meta.kg)
    end

    println("\nMetacentric Radii:")
    println("─" ^ 70)
    @printf("  BM_t (Transverse):           %10.3f m\n", meta.bm_t)
    @printf("  BM_l (Longitudinal):         %10.3f m\n", meta.bm_l)

    println("\nMetacentric Heights:")
    println("─" ^ 70)
    @printf("  KM_t (Transverse):           %10.3f m\n", meta.km_t)
    @printf("  KM_l (Longitudinal):         %10.3f m\n", meta.km_l)

    if meta.gm_t !== nothing && meta.gm_l !== nothing
        @printf("  GM_t (Transverse):           %10.3f m ", meta.gm_t)
        if meta.gm_t > 0.15
            println("✓ (Adequate)")
        elseif meta.gm_t > 0
            println("⚠ (Low)")
        else
            println("✗ (Negative - Unstable)")
        end

        @printf("  GM_l (Longitudinal):         %10.3f m\n", meta.gm_l)
    else
        println("  (GM not calculated - KG not provided)")
    end

    println("═" ^ 70)
end

"""
    print_gz_curve(angles, gz_values)

Print GZ curve data and plot ASCII representation.
"""
function print_gz_curve(angles, gz_values)
    println("\n" * "═" ^ 70)
    println("GZ CURVE (Righting Arm)")
    println("═" ^ 70)

    # Find key points
    max_gz_idx = argmax(gz_values)
    max_gz = gz_values[max_gz_idx]
    angle_max_gz = angles[max_gz_idx]

    # Find angle of vanishing stability
    angle_vanish = 0.0
    for i in 2:length(angles)
        if gz_values[i] <= 0.0 && gz_values[i-1] > 0.0
            t = -gz_values[i-1] / (gz_values[i] - gz_values[i-1])
            angle_vanish = angles[i-1] + t * (angles[i] - angles[i-1])
            break
        end
    end
    if angle_vanish == 0.0
        angle_vanish = angles[end]
    end

    println("\nKey Points:")
    println("─" ^ 70)
    @printf("  Maximum GZ:                  %10.3f m at %.1f°\n", max_gz, angle_max_gz)
    @printf("  Angle of Vanishing Stability: %10.1f°\n", angle_vanish)

    # ASCII plot
    println("\nGZ vs Heel Angle:")
    println("─" ^ 70)
    @printf("%-10s %10s   %s\n", "Angle(°)", "GZ(m)", "Graph")
    println("─" ^ 70)

    scale = 40.0 / maximum(abs.(gz_values))
    for (i, (angle, gz)) in enumerate(zip(angles, gz_values))
        if i % 2 == 1  # Print every other line for readability
            bar_length = round(Int, abs(gz) * scale)
            bar = "█" ^ bar_length
            @printf("%8.1f   %10.3f   %s\n", angle, gz, bar)
        end
    end

    println("═" ^ 70)
end

"""
    print_stability_criteria(criteria::StabilityCriteria)

Print stability criteria check results.
"""
function print_stability_criteria(criteria::StabilityCriteria)
    println("\n" * "═" ^ 70)
    println("STABILITY CRITERIA")
    println("═" ^ 70)

    println("\nBasic Checks:")
    println("─" ^ 70)

    function print_check(name, passed, detail="")
        status = passed ? "✓ PASS" : "✗ FAIL"
        println("  $status  $name $detail")
    end

    print_check("Positive GM", criteria.gm_positive)
    print_check("Adequate GM (≥ 0.15m)", criteria.gm_adequate)
    print_check("Max GZ ≥ 0.20m",
                criteria.max_gz >= 0.20,
                @sprintf("(%.3f m)", criteria.max_gz))
    print_check("Angle of max GZ ≥ 25°",
                criteria.angle_of_max_gz >= 25.0,
                @sprintf("(%.1f°)", criteria.angle_of_max_gz))
    print_check("Range of stability ≥ 60°",
                criteria.angle_of_vanishing_stability >= 60.0,
                @sprintf("(%.1f°)", criteria.angle_of_vanishing_stability))

    println("\nEnergy Criterion:")
    println("─" ^ 70)
    @printf("  Area under GZ curve:         %10.3f m·rad\n", criteria.area_under_curve)

    println("\nOverall Assessment:")
    println("─" ^ 70)
    if criteria.meets_imo_criteria
        println("  ✓ PASSES basic IMO stability criteria")
    else
        println("  ✗ DOES NOT MEET basic IMO stability criteria")
        println("  ⚠ Further analysis required")
    end

    println("═" ^ 70)
end

"""
    main()

Main demonstration function.
"""
function main()
    println("\n" * "╔" * "═" ^ 68 * "╗")
    println("║" * " " ^ 15 * "Stability Analysis Demonstration" * " " ^ 21 * "║")
    println("╚" * "═" ^ 68 * "╝")

    # Step 1: Create hull and calculate hydrostatics
    println("\n[1/5] Creating hull and calculating hydrostatics...")
    x, y_offsets, z, LOA, Beam, Draft = create_sample_hull()

    results = calculate_hydrostatics(x, y_offsets, z)
    props = results[end]  # Design draft properties

    println("  ✓ Hull created: $(LOA)m × $(Beam)m × $(Draft)m")
    println("  ✓ Hydrostatics calculated")

    # Step 2: Calculate form coefficients
    println("\n[2/5] Calculating form coefficients...")

    # Waterline length (approximate as LOA for this demo)
    lpp = props.waterline_length

    coeffs = calculate_form_coefficients(
        props.volume,
        props.waterplane_area,
        LOA,
        lpp,
        Beam,
        Draft,
        props.lcb,
        y_offsets,
        z
    )

    print_form_coefficients(coeffs)

    # Step 3: Calculate metacentric properties
    println("\n[3/5] Calculating metacentric properties...")

    # Estimate KG (center of gravity)
    kg_estimated = estimate_kg_from_coefficients(Draft, coeffs.cb, vessel_type=:cargo)
    println("  Estimated KG: $(round(kg_estimated, digits=3)) m (for cargo vessel)")

    meta = calculate_metacentric_properties(
        props.volume,
        props.vcb,
        Draft,
        props.ixx,
        props.iyy,
        kg=kg_estimated
    )

    print_metacentric_properties(meta)

    # Step 4: Generate GZ curve
    println("\n[4/5] Generating GZ (righting arm) curve...")

    angles, gz_values = calculate_gz_curve(meta, max_angle=90.0, n_points=19)

    print_gz_curve(angles, gz_values)

    # Step 5: Check stability criteria
    println("\n[5/5] Checking stability criteria...")

    criteria = check_stability_criteria(angles, gz_values, meta.gm_t)

    print_stability_criteria(criteria)

    # Summary
    println("\n" * "╔" * "═" ^ 68 * "╗")
    println("║" * " " ^ 25 * "SUMMARY" * " " ^ 36 * "║")
    println("╚" * "═" ^ 68 * "╝")

    println("\nVessel Characteristics:")
    @printf("  • Type:              Cargo vessel (estimated)\n")
    @printf("  • Cb:                %.3f (%s)\n", coeffs.cb,
            coeffs.cb > 0.7 ? "Full form" : coeffs.cb > 0.55 ? "Normal" : "Fine form")
    @printf("  • GM:                %.3f m (%s)\n", meta.gm_t,
            meta.gm_t > 1.0 ? "Stiff" : meta.gm_t > 0.5 ? "Normal" : "Tender")
    @printf("  • Stability Range:   %.1f° (%s)\n",
            criteria.angle_of_vanishing_stability,
            criteria.angle_of_vanishing_stability > 60 ? "Good" : "Limited")

    println("\nStability Assessment:")
    if criteria.meets_imo_criteria
        println("  ✓ Vessel meets basic stability requirements")
        println("  ✓ Suitable for preliminary design")
    else
        println("  ⚠ Stability requirements not fully met")
        println("  ⚠ Design modifications or detailed analysis required")
    end

    println("\n" * "═" ^ 70)
    println("Analysis complete!")
    println("═" ^ 70 * "\n")

    return coeffs, meta, criteria
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    coeffs, meta, criteria = main()
end
