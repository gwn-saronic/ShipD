"""
    hydrostatics_with_shipd.jl

Complete example showing hydrostatic calculations using real Ship-D hull data.
This script:
1. Loads hull parameter vectors from Ship-D CSV files
2. Interfaces with Python Ship-D code to generate offsets
3. Calculates hydrostatic properties using Julia
4. Compares results with Python implementation

Usage:
    julia hydrostatics_with_shipd.jl

Requirements:
    - Julia 1.11+
    - PyCall configured with Ship-D Python environment
    - Ship-D Python package installed
"""

# Load modules from parent directory
include(joinpath(dirname(@__DIR__), "Hydrostatics.jl"))
include(joinpath(dirname(@__DIR__), "ShipDPy2Jl.jl"))
using .Hydrostatics
using .ShipDPy2Jl
using Printf

"""
    compare_with_python(hull::PyObject, offsets::HullOffsets)

Compare Julia hydrostatic calculations with Python implementation.

# Arguments
- `hull::PyObject`: Python Hull_Parameterization object
- `offsets::HullOffsets`: Julia offset data structure

# Returns
- `Dict`: Dictionary with comparison results
"""
function compare_with_python(hull::PyObject, offsets::HullOffsets)
    # Calculate using Julia
    println("\n[Calculating with Julia...]")
    @time results_julia = calculate_hydrostatics(offsets.x, offsets.y_offsets, offsets.z)

    # Calculate using Python
    println("\n[Calculating with Python...]")
    @time begin
        Z_py = hull.Calc_VolumeProperties(NUM_WL=length(offsets.z), PointsPerWL=length(offsets.x))
    end

    # Extract Python results at design draft (last index)
    idx = length(Z_py)
    volume_py = hull.Volumes[idx]
    area_wp_py = hull.Areas_WP[idx]
    lcb_py = hull.VolumeCentroids[idx, 1]
    vcb_py = hull.VolumeCentroids[idx, 2]
    lcf_py = hull.LCFs[idx]
    ixx_py = hull.I_WP[idx, 1]
    iyy_py = hull.I_WP[idx, 2]
    wsa_py = hull.Area_WS[idx]
    wl_py = hull.WL_Lengths[idx]

    # Julia results at design draft
    props_julia = results_julia[end]

    # Calculate relative differences
    println("\n" * "═" ^ 80)
    println("Comparison: Julia vs Python Hydrostatics")
    println("═" ^ 80)
    @printf("%-25s %15s %15s %15s\n", "Property", "Julia", "Python", "Rel. Diff (%)")
    println("─" ^ 80)

    function print_comparison(name, val_jl, val_py)
        rel_diff = abs(val_jl - val_py) / (abs(val_py) + 1e-10) * 100.0
        @printf("%-25s %15.6f %15.6f %15.4f\n", name, val_jl, val_py, rel_diff)
    end

    print_comparison("Volume", props_julia.volume, volume_py)
    print_comparison("Waterplane Area", props_julia.waterplane_area, area_wp_py)
    print_comparison("LCB", props_julia.lcb, lcb_py)
    print_comparison("VCB", props_julia.vcb, vcb_py)
    print_comparison("LCF", props_julia.lcf, lcf_py)
    print_comparison("Ixx", props_julia.ixx, ixx_py)
    print_comparison("Iyy", props_julia.iyy, iyy_py)
    print_comparison("Wetted Surface", props_julia.wetted_surface, wsa_py)
    print_comparison("Waterline Length", props_julia.waterline_length, wl_py)

    println("═" ^ 80)

    return Dict(
        "julia" => props_julia,
        "python_volume" => volume_py,
        "python_area" => area_wp_py,
        "python_lcb" => lcb_py,
        "python_vcb" => vcb_py
    )
end

"""
    analyze_hull(params::Vector{Float64}; compare::Bool=true)

Complete analysis of a single hull.

# Arguments
- `params::Vector{Float64}`: 45-parameter hull design vector
- `compare::Bool`: Whether to compare with Python implementation

# Returns
- `Vector{HydrostaticProperties}`: Hydrostatic properties at all drafts
"""
function analyze_hull(params::Vector{Float64}; compare::Bool=true)
    println("\n" * "═" ^ 80)
    println("Hull Analysis")
    println("═" ^ 80)

    # Load hull from Python
    println("\n[1/4] Loading hull from parameters...")
    hull = load_hull_from_python(params)

    # Check constraints
    constraints = check_hull_constraints(hull)
    n_violations = sum(constraints .> 0)

    println("  ✓ Hull loaded")
    @printf("    - LOA: %.4f m\n", hull.LOA)
    @printf("    - Beam: %.4f m\n", 2.0 * hull.Bd * hull.LOA)
    @printf("    - Draft: %.4f m\n", hull.Dd * hull.WL)
    @printf("    - Constraint violations: %d / %d\n", n_violations, length(constraints))

    if n_violations > 0
        @warn "Hull has constraint violations - design may not be physically feasible"
        println("    Violated constraints: ", findall(constraints .> 0))
    end

    # Generate offsets
    println("\n[2/4] Generating hull offsets...")
    offsets = generate_offsets_for_hydrostatics(
        hull,
        draft_fraction=1.0,
        num_stations=51
    )
    println("  ✓ Offsets generated")
    @printf("    - Stations: %d\n", length(offsets.x))
    @printf("    - Waterlines: %d\n", length(offsets.z))
    @printf("    - Waterline length: %.4f m\n", offsets.waterline_length)

    # Calculate hydrostatics
    println("\n[3/4] Calculating hydrostatic properties...")
    results = calculate_hydrostatics(offsets.x, offsets.y_offsets, offsets.z)
    println("  ✓ Calculations complete")

    # Display results
    println("\n[4/4] Results:")
    print_hydrostatic_properties(results[end], offsets.LOA)

    # Compare with Python if requested
    if compare
        println("\n[Bonus] Comparing with Python implementation...")
        compare_with_python(hull, offsets)
    end

    return results
end

"""
    batch_analyze_hulls(filename::String; max_hulls::Int=5)

Analyze multiple hulls from a parameter file.

# Arguments
- `filename::String`: Path to CSV file with hull parameters
- `max_hulls::Int`: Maximum number of hulls to analyze

# Returns
- `Vector`: Array of results for each hull
"""
function batch_analyze_hulls(filename::String; max_hulls::Int=5)
    println("\n" * "═" ^ 80)
    println("Batch Hull Analysis")
    println("═" ^ 80)

    # Load hull vectors
    println("\n[Loading hull parameters from: $filename]")
    vectors = load_hull_vectors(filename)
    n_hulls = min(size(vectors, 1), max_hulls)

    println("  ✓ Loaded $(size(vectors, 1)) hull designs")
    println("  → Analyzing first $n_hulls hulls\n")

    results = []
    for i in 1:n_hulls
        println("\n" * "─" ^ 80)
        println("Hull $i of $n_hulls")
        println("─" ^ 80)

        try
            params = vectors[i, :]
            props = analyze_hull(params, compare=false)
            push!(results, props)
        catch e
            @warn "Failed to analyze hull $i: $e"
            push!(results, nothing)
        end
    end

    # Summary statistics
    println("\n" * "═" ^ 80)
    println("Batch Analysis Summary")
    println("═" ^ 80)

    successful = sum(results .!== nothing)
    println("Successfully analyzed: $successful / $n_hulls hulls")

    if successful > 0
        # Calculate statistics across hulls
        volumes = [r[end].volume for r in results if r !== nothing]
        areas = [r[end].waterplane_area for r in results if r !== nothing]

        @printf("\nVolume Statistics:\n")
        @printf("  Mean:   %.4f m³\n", sum(volumes) / length(volumes))
        @printf("  Min:    %.4f m³\n", minimum(volumes))
        @printf("  Max:    %.4f m³\n", maximum(volumes))

        @printf("\nWaterplane Area Statistics:\n")
        @printf("  Mean:   %.4f m²\n", sum(areas) / length(areas))
        @printf("  Min:    %.4f m²\n", minimum(areas))
        @printf("  Max:    %.4f m²\n", maximum(areas))
    end

    println("═" ^ 80)

    return results
end

"""
    main()

Main demonstration function.
"""
function main()
    println("\n" * "╔" * "═" ^ 78 * "╗")
    println("║" * " " ^ 20 * "Ship-D Hydrostatics with Julia" * " " ^ 28 * "║")
    println("╚" * "═" ^ 78 * "╝")

    # Check if sample hulls file exists
    sample_file = joinpath(dirname(@__DIR__), "Input_Vectors_SampleHulls.csv")

    if !isfile(sample_file)
        @warn "Sample hulls file not found at: $sample_file"
        println("\nPlease ensure you're running from the Ship-D directory.")
        println("Expected file: Input_Vectors_SampleHulls.csv")
        return nothing
    end

    # Analyze a single hull in detail
    println("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("PART 1: Single Hull Analysis with Python Comparison")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    vectors = load_hull_vectors(sample_file)
    results = analyze_hull(vectors[1, :], compare=true)

    # Batch analysis
    println("\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("PART 2: Batch Analysis of Multiple Hulls")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    batch_results = batch_analyze_hulls(sample_file, max_hulls=3)

    println("\n✓ All demonstrations complete!\n")

    return results, batch_results
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results, batch_results = main()
end
