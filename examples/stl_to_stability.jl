"""
    stl_to_stability.jl

Complete workflow from STL file to stability analysis.
Demonstrates:
1. Loading hull from STL file
2. Calculating hydrostatic properties
3. Computing form coefficients
4. Performing stability analysis
5. Generating comprehensive report

Usage:
    julia stl_to_stability.jl [path_to_stl_file]

Requirements:
    - Julia 1.11+
    - STL file of ship hull
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
    analyze_hull_from_stl(stl_file; kg=nothing, n_stations=51, n_waterlines=11)

Complete hull analysis from STL file.

# Arguments
- `stl_file::String`: Path to STL file
- `kg::Union{Nothing,Float64}`: Center of gravity height (optional, will estimate if not provided)
- `n_stations::Int`: Number of longitudinal stations
- `n_waterlines::Int`: Number of vertical waterlines

# Returns
- `(hydro_props, form_coeffs, meta_props, stability_crit)`: Complete analysis results
"""
function analyze_hull_from_stl(stl_file::String;
                               kg::Union{Nothing,Float64}=nothing,
                               n_stations::Int=51,
                               n_waterlines::Int=11,
                               vessel_type::Symbol=:cargo)
    println("\n" * "═" ^ 70)
    println("HULL ANALYSIS FROM STL FILE")
    println("═" ^ 70)
    println("File: $stl_file")

    # Step 1: Load STL and calculate hydrostatics
    println("\n[1/5] Loading STL and calculating hydrostatics...")
    results = calculate_hydrostatics_from_file(
        stl_file,
        n_stations=n_stations,
        n_waterlines=n_waterlines
    )
    println("  ✓ Hydrostatics calculated at $(length(results)) drafts")

    # Get design draft properties
    props = results[end]

    # Extract dimensions from results
    # Note: For real analysis, you'd want to provide actual LOA and Beam
    # Here we estimate from the offsets
    waterline_length = props.waterline_length
    # Estimate beam from waterplane area and length
    beam_estimated = 2.0 * sqrt(props.waterplane_area / waterline_length)
    draft = props.draft

    println("  ✓ Estimated dimensions:")
    @printf("      L:     %.2f m\n", waterline_length)
    @printf("      B:     %.2f m (estimated)\n", beam_estimated)
    @printf("      T:     %.2f m\n", draft)
    @printf("      ∇:     %.2f m³\n", props.volume)

    # Step 2: Calculate form coefficients
    println("\n[2/5] Calculating form coefficients...")

    # For STL-based analysis, we don't have y_offsets readily available
    # So we calculate without midship area
    form_coeffs = calculate_form_coefficients(
        props.volume,
        props.waterplane_area,
        waterline_length * 1.1,  # Estimate LOA as 110% of LWL
        waterline_length,
        beam_estimated,
        draft,
        props.lcb
    )

    println("  ✓ Form coefficients calculated")
    @printf("      Cb:    %.3f\n", form_coeffs.cb)
    @printf("      Cp:    %.3f\n", form_coeffs.cp)
    @printf("      Cwp:   %.3f\n", form_coeffs.cwp)

    # Step 3: Estimate or use provided KG
    println("\n[3/5] Determining center of gravity...")

    if kg === nothing
        kg = estimate_kg_from_coefficients(draft, form_coeffs.cb, vessel_type=vessel_type)
        println("  ℹ KG not provided, estimated from coefficients")
        @printf("  ✓ Estimated KG: %.3f m (for %s vessel)\n", kg, vessel_type)
    else
        @printf("  ✓ Using provided KG: %.3f m\n", kg)
    end

    # Step 4: Calculate metacentric properties
    println("\n[4/5] Calculating metacentric properties...")

    meta_props = calculate_metacentric_properties(
        props.volume,
        props.vcb,
        draft,
        props.ixx,
        props.iyy,
        kg=kg
    )

    println("  ✓ Metacentric properties calculated")
    @printf("      KB:    %.3f m\n", meta_props.kb)
    @printf("      GM_t:  %.3f m\n", meta_props.gm_t)

    # Step 5: Generate GZ curve and check stability
    println("\n[5/5] Analyzing stability...")

    angles, gz_values = calculate_gz_curve(meta_props, max_angle=90.0)
    stability_crit = check_stability_criteria(angles, gz_values, meta_props.gm_t)

    println("  ✓ GZ curve generated")
    println("  ✓ Stability criteria checked")

    if stability_crit.meets_imo_criteria
        println("  ✓ Vessel PASSES basic IMO criteria")
    else
        println("  ⚠ Vessel does NOT meet all IMO criteria")
    end

    return props, form_coeffs, meta_props, stability_crit, angles, gz_values
end

"""
    generate_report(stl_file, props, coeffs, meta, criteria, angles, gz_values)

Generate comprehensive analysis report.
"""
function generate_report(stl_file, props, coeffs, meta, criteria, angles, gz_values)
    println("\n\n")
    println("╔" * "═" ^ 68 * "╗")
    println("║" * " " ^ 20 * "STABILITY ANALYSIS REPORT" * " " ^ 23 * "║")
    println("╚" * "═" ^ 68 * "╝")

    println("\nInput File: $stl_file")
    println("Analysis Date: $(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))")

    # Section 1: Hydrostatic Properties
    println("\n" * "─" ^ 70)
    println("1. HYDROSTATIC PROPERTIES")
    println("─" ^ 70)
    @printf("  Volume (∇):                  %12.2f m³\n", props.volume)
    @printf("  Waterplane Area (Awp):       %12.2f m²\n", props.waterplane_area)
    @printf("  LCB (from FP):               %12.2f m\n", props.lcb)
    @printf("  VCB (from keel):             %12.2f m\n", props.vcb + props.draft)
    @printf("  LCF (from FP):               %12.2f m\n", props.lcf)
    @printf("  Wetted Surface (S):          %12.2f m²\n", props.wetted_surface)
    @printf("  Waterline Length (LWL):      %12.2f m\n", props.waterline_length)

    # Section 2: Form Coefficients
    println("\n" * "─" ^ 70)
    println("2. FORM COEFFICIENTS")
    println("─" ^ 70)
    @printf("  Block Coefficient (Cb):      %12.4f\n", coeffs.cb)
    @printf("  Prismatic Coefficient (Cp):  %12.4f\n", coeffs.cp)
    @printf("  Waterplane Coeff (Cwp):      %12.4f\n", coeffs.cwp)
    @printf("  Midship Coeff (Cm):          %12.4f\n", coeffs.cm)
    @printf("  Vert. Prismatic (Cvp):       %12.4f\n", coeffs.cvp)

    # Section 3: Stability Parameters
    println("\n" * "─" ^ 70)
    println("3. STABILITY PARAMETERS")
    println("─" ^ 70)
    @printf("  KB (Buoyancy above keel):    %12.3f m\n", meta.kb)
    @printf("  KG (Gravity above keel):     %12.3f m\n", meta.kg)
    @printf("  BM (Metacentric radius):     %12.3f m\n", meta.bm_t)
    @printf("  KM (Metacenter above keel):  %12.3f m\n", meta.km_t)
    @printf("  GM (Metacentric height):     %12.3f m ", meta.gm_t)

    if meta.gm_t > 1.0
        println(" [STIFF]")
    elseif meta.gm_t > 0.5
        println(" [NORMAL]")
    elseif meta.gm_t > 0.15
        println(" [TENDER]")
    else
        println(" [LOW]")
    end

    # Section 4: Stability Criteria
    println("\n" * "─" ^ 70)
    println("4. STABILITY CRITERIA (IMO)")
    println("─" ^ 70)

    function print_criterion(name, value, required, passed)
        status = passed ? "✓ PASS" : "✗ FAIL"
        @printf("  %s  %-35s %8.2f  (req: %s)\n", status, name, value, required)
    end

    print_criterion("GM ≥ 0.15 m",
                   meta.gm_t,
                   "0.15 m",
                   criteria.gm_adequate)
    print_criterion("Maximum GZ",
                   criteria.max_gz,
                   "≥0.20 m",
                   criteria.max_gz >= 0.20)
    print_criterion("Angle of max GZ",
                   criteria.angle_of_max_gz,
                   "≥25°",
                   criteria.angle_of_max_gz >= 25.0)
    print_criterion("Range of stability",
                   criteria.angle_of_vanishing_stability,
                   "≥60°",
                   criteria.angle_of_vanishing_stability >= 60.0)
    print_criterion("Area under GZ curve",
                   criteria.area_under_curve,
                   "adequate",
                   criteria.area_under_curve > 0.055)

    # Section 5: GZ Curve Summary
    println("\n" * "─" ^ 70)
    println("5. RIGHTING ARM (GZ) CURVE")
    println("─" ^ 70)
    @printf("  Maximum GZ:                  %12.3f m at %.1f°\n",
            criteria.max_gz, criteria.angle_of_max_gz)
    @printf("  Vanishing angle:             %12.1f°\n",
            criteria.angle_of_vanishing_stability)
    @printf("  Area to 30°:                 ")

    # Calculate area to 30 degrees
    idx_30 = findfirst(a -> a >= 30.0, angles)
    if idx_30 !== nothing
        area_30 = 0.0
        for i in 1:(idx_30-1)
            if gz_values[i] > 0.0 && gz_values[i+1] > 0.0
                dangle = deg2rad(angles[i+1] - angles[i])
                area_30 += 0.5 * (gz_values[i] + gz_values[i+1]) * dangle
            end
        end
        @printf("%12.4f m·rad\n", area_30)
    else
        println("         N/A")
    end

    # Section 6: Overall Assessment
    println("\n" * "─" ^ 70)
    println("6. OVERALL ASSESSMENT")
    println("─" ^ 70)

    if criteria.meets_imo_criteria
        println("  ✓ Vessel PASSES all basic IMO stability criteria")
        println("  ✓ Suitable for preliminary design approval")
    else
        println("  ⚠ Vessel DOES NOT meet all IMO stability criteria")
        println("  ⚠ Modifications required or detailed analysis needed")
    end

    println("\n" * "─" ^ 70)
    println("NOTES:")
    println("─" ^ 70)
    println("  • This analysis is based on simplified calculations")
    println("  • For final approval, detailed stability booklet required")
    println("  • KG estimated - verify actual lightship KG")
    println("  • Loading conditions and freesurface effects not included")
    println("  • Weather criterion and wind heeling moment not assessed")

    println("\n" * "═" ^ 70)
end

"""
    main(args)

Main function.
"""
function main(args)
    # Get STL file from command line or use default
    if length(args) >= 1
        stl_file = args[1]
    else
        stl_file = joinpath(dirname(@__DIR__), "sample_Hull_Mesh.stl")
    end

    if !isfile(stl_file)
        println("Error: STL file not found: $stl_file")
        println("\nUsage: julia stl_to_stability.jl [path_to_stl_file]")
        return nothing
    end

    # Perform complete analysis
    props, coeffs, meta, criteria, angles, gz_values = analyze_hull_from_stl(
        stl_file,
        kg=nothing,  # Will estimate
        n_stations=51,
        n_waterlines=11,
        vessel_type=:cargo
    )

    # Generate report
    generate_report(stl_file, props, coeffs, meta, criteria, angles, gz_values)

    return props, coeffs, meta, criteria
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    # Import Dates for timestamp
    using Dates

    result = main(ARGS)
end
