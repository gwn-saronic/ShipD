"""
    hydrostatics_multi_input.jl

Demonstration of hydrostatic calculations with multiple input types:
1. Direct offset tables
2. STL files
3. Ship-D hull parameters (via Python)

Usage:
    julia hydrostatics_multi_input.jl

Requirements:
    - Julia 1.11+
    - STLReader.jl (for STL support)
    - PyCall (optional, for Ship-D integration)
"""

# Load modules
include(joinpath(dirname(@__DIR__), "Hydrostatics.jl"))
using .Hydrostatics
using .Hydrostatics: OffsetInput, STLInput  # Import input types
using Printf

"""
    demo_offset_input()

Demonstrate hydrostatics calculation from direct offset input.
"""
function demo_offset_input()
    println("\n" * "═" ^ 80)
    println("Method 1: Direct Offset Input")
    println("═" ^ 80)

    # Create simple hull offsets
    println("\n[1] Creating offset table...")
    x = collect(range(0.0, 10.0, length=21))
    z = collect(range(-1.0, 0.0, length=11))

    # Simple hull form
    y_offsets = zeros(length(x), length(z))
    for (i, xi) in enumerate(x)
        for (j, zj) in enumerate(z)
            # Parabolic bow, parallel midbody, tapered stern
            x_norm = xi / 10.0
            z_norm = (zj + 1.0) / 1.0

            if x_norm < 0.2
                beam_factor = (x_norm / 0.2)^1.5
            elseif x_norm < 0.7
                beam_factor = 1.0
            else
                beam_factor = 1.0 - ((x_norm - 0.7) / 0.3)^1.2
            end

            vertical_factor = z_norm^0.7

            y_offsets[i, j] = 0.88 * beam_factor * vertical_factor
        end
    end

    println("  ✓ Offset table created: $(length(x)) stations × $(length(z)) waterlines")

    # Calculate hydrostatics
    println("\n[2] Calculating hydrostatics...")
    results = calculate_hydrostatics(x, y_offsets, z)
    println("  ✓ Complete")

    # Display results
    println("\n[3] Results at design draft:")
    props = results[end]
    @printf("    Volume:          %.4f m³\n", props.volume)
    @printf("    Waterplane area: %.4f m²\n", props.waterplane_area)
    @printf("    LCB:             %.4f m\n", props.lcb)
    @printf("    VCB:             %.4f m\n", props.vcb)
    @printf("    Wetted surface:  %.4f m²\n", props.wetted_surface)

    return results
end

"""
    demo_stl_input(stl_file::String)

Demonstrate hydrostatics calculation from STL file.
"""
function demo_stl_input(stl_file::String)
    println("\n" * "═" ^ 80)
    println("Method 2: STL File Input")
    println("═" ^ 80)

    if !isfile(stl_file)
        println("\n⚠ STL file not found: $stl_file")
        println("  Skipping STL demo. To run this demo, provide a valid STL file path.")
        return nothing
    end

    # Calculate hydrostatics from STL
    println("\n[1] Loading and processing STL file...")
    println("    File: $stl_file")

    try
        results = calculate_hydrostatics_from_file(
            stl_file,
            input_type=:stl,
            n_stations=51,
            n_waterlines=11
        )

        println("  ✓ STL processed and hydrostatics calculated")

        # Display results
        println("\n[2] Results at design draft:")
        props = results[end]
        @printf("    Volume:          %.4f m³\n", props.volume)
        @printf("    Waterplane area: %.4f m²\n", props.waterplane_area)
        @printf("    LCB:             %.4f m\n", props.lcb)
        @printf("    VCB:             %.4f m\n", props.vcb)
        @printf("    Wetted surface:  %.4f m²\n", props.wetted_surface)

        return results
    catch e
        println("\n✗ Error processing STL file:")
        println("  $e")
        return nothing
    end
end

"""
    demo_hull_input_types()

Demonstrate the HullInput abstract type interface.
"""
function demo_hull_input_types()
    println("\n" * "═" ^ 80)
    println("Method 3: Using HullInput Types")
    println("═" ^ 80)

    # Method 3a: OffsetInput
    println("\n[3a] Using OffsetInput type...")
    x = collect(range(0.0, 8.0, length=17))
    z = collect(range(-0.8, 0.0, length=9))
    y_offsets = ones(length(x), length(z)) .* 0.7
    y_offsets[1, :] .= 0.0  # Bow
    y_offsets[end, :] .= 0.0  # Stern

    input = OffsetInput(x, y_offsets, z)
    results = calculate_hydrostatics(input)

    println("  ✓ Calculated from OffsetInput")
    @printf("    Volume: %.4f m³\n", results[end].volume)

    # Method 3b: STLInput (if STL file available)
    println("\n[3b] Using STLInput type...")
    stl_file = joinpath(dirname(@__DIR__), "sample_Hull_Mesh.stl")

    if isfile(stl_file)
        try
            input = STLInput(stl_file, 51, 11, nothing)
            results = calculate_hydrostatics(input)

            println("  ✓ Calculated from STLInput")
            @printf("    Volume: %.4f m³\n", results[end].volume)
        catch e
            println("  ⚠ Could not process STL: $e")
        end
    else
        println("  ⚠ Sample STL not found, skipping STLInput demo")
    end

    return nothing
end

"""
    demo_auto_detection()

Demonstrate automatic file type detection.
"""
function demo_auto_detection()
    println("\n" * "═" ^ 80)
    println("Method 4: Automatic File Type Detection")
    println("═" ^ 80)

    stl_file = joinpath(dirname(@__DIR__), "sample_Hull_Mesh.stl")

    if !isfile(stl_file)
        println("\n⚠ Sample STL file not found, skipping auto-detection demo")
        return nothing
    end

    println("\n[1] Using automatic detection (no input_type specified)...")
    println("    File: $stl_file")

    try
        # Just pass the filename - it will auto-detect STL format
        results = calculate_hydrostatics_from_file(stl_file)

        println("  ✓ Automatically detected as STL format")
        println("  ✓ Hydrostatics calculated")

        props = results[end]
        @printf("\n[2] Results:\n")
        @printf("    Volume:          %.4f m³\n", props.volume)
        @printf("    Waterplane area: %.4f m²\n", props.waterplane_area)

        return results
    catch e
        println("\n✗ Error: $e")
        return nothing
    end
end

"""
    compare_inputs(stl_file::String)

Compare results from offset table vs STL file for the same hull.
"""
function compare_inputs(stl_file::String)
    println("\n" * "═" ^ 80)
    println("Comparison: Offset Input vs STL Input")
    println("═" ^ 80)

    if !isfile(stl_file)
        println("\n⚠ STL file not available for comparison")
        return nothing
    end

    try
        # Calculate from STL
        println("\n[1] Calculating from STL...")
        results_stl = calculate_hydrostatics_from_file(stl_file, n_stations=51, n_waterlines=11)
        props_stl = results_stl[end]

        # For comparison, we'd need the corresponding offset table
        # This is just a placeholder showing the comparison structure

        println("\n[2] Results:")
        println("─" ^ 80)
        @printf("%-25s %15s\n", "Property", "STL Input")
        println("─" ^ 80)
        @printf("%-25s %15.4f m³\n", "Volume", props_stl.volume)
        @printf("%-25s %15.4f m²\n", "Waterplane Area", props_stl.waterplane_area)
        @printf("%-25s %15.4f m\n", "LCB", props_stl.lcb)
        @printf("%-25s %15.4f m\n", "VCB", props_stl.vcb)
        @printf("%-25s %15.4f m²\n", "Wetted Surface", props_stl.wetted_surface)
        println("═" ^ 80)

        return results_stl
    catch e
        println("\n✗ Error in comparison: $e")
        return nothing
    end
end

"""
    main()

Main demonstration function.
"""
function main()
    println("\n" * "╔" * "═" ^ 78 * "╗")
    println("║" * " " ^ 15 * "Ship-D Hydrostatics: Multiple Input Methods" * " " ^ 20 * "║")
    println("╚" * "═" ^ 78 * "╝")

    # Demo 1: Direct offset input (always works)
    results_offset = demo_offset_input()

    # Demo 2: STL file input
    stl_file = joinpath(dirname(@__DIR__), "sample_Hull_Mesh.stl")
    results_stl = demo_stl_input(stl_file)

    # Demo 3: HullInput types
    demo_hull_input_types()

    # Demo 4: Auto-detection
    demo_auto_detection()

    # Demo 5: Comparison (if STL available)
    if isfile(stl_file)
        compare_inputs(stl_file)
    end

    # Summary
    println("\n" * "═" ^ 80)
    println("Summary of Input Methods")
    println("═" ^ 80)
    println("""
    ✓ Method 1: Direct Offset Input
      Use when you have pre-computed offset tables
      Example: calculate_hydrostatics(x, y_offsets, z)

    ✓ Method 2: STL File Input
      Use when you have a 3D mesh file
      Example: calculate_hydrostatics_from_file("hull.stl")

    ✓ Method 3: HullInput Types
      Use for type-safe abstractions
      Example: calculate_hydrostatics(OffsetInput(x, y, z))

    ✓ Method 4: Automatic Detection
      Use for convenience with file-based inputs
      Example: calculate_hydrostatics_from_file("hull.stl")  # Auto-detects STL

    ✓ Method 5: Ship-D Parameters (see hydrostatics_with_shipd.jl)
      Use with Ship-D hull parameter vectors
      Example: generate_offsets_for_hydrostatics(params)
    """)
    println("═" ^ 80)

    println("\n✓ All demonstrations complete!\n")

    return results_offset, results_stl
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results_offset, results_stl = main()
end
