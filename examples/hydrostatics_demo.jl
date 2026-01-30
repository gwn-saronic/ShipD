"""
    hydrostatics_demo.jl

Demonstration of hydrostatic calculations using the Hydrostatics module.
Shows how to:
1. Load hull offset data from Ship-D hull parameterization
2. Calculate hydrostatic properties
3. Display and export results

Usage:
    julia hydrostatics_demo.jl

Requirements:
    - Julia 1.11+
    - PyCall (for interfacing with Python Ship-D code)
    - CSV, DataFrames (for exporting results)
"""

# Load Hydrostatics module from parent directory
include(joinpath(dirname(@__DIR__), "Hydrostatics.jl"))
using .Hydrostatics
using Printf

# Optional: For interfacing with Python Ship-D code
# using PyCall
# using CSV, DataFrames

"""
    load_offsets_from_python(hull_vector::Vector)

Interface with Python Ship-D code to generate hull offsets.

# Arguments
- `hull_vector::Vector`: 45-parameter hull design vector

# Returns
- `(x, y_offsets, z)`: Tuple of offset data arrays
"""
function load_offsets_from_python(hull_vector::Vector)
    # This would require PyCall to be set up
    # Example implementation:
    # py"""
    # import numpy as np
    # from shipd import Hull_Parameterization as HP
    #
    # def get_hull_offsets(params):
    #     hull = HP(params)
    #     X, Z, Y, WL = hull.gen_PC_for_Cw(draft=hull.Dd*hull.WL)
    #     return X, Y, Z
    # """
    #
    # x, y_offsets, z = py"get_hull_offsets"(hull_vector)
    # return x, y_offsets, z

    error("PyCall interface not implemented. Use load_sample_offsets() instead.")
end

"""
    load_sample_offsets()

Generate sample hull offset data for demonstration purposes.
This creates a simplified hull form similar to a Series 60 hull.

# Returns
- `(x, y_offsets, z)`: Tuple of offset data arrays
"""
function load_sample_offsets()
    # Create sample hull: 10m length, typical cargo ship proportions
    LOA = 10.0
    Beam = 1.76  # 17.6% of LOA
    Draft = 0.885  # 8.85% of LOA

    # Longitudinal stations (20 stations from bow to stern)
    n_stations = 21
    x = range(0.0, LOA, length=n_stations)

    # Vertical stations (11 waterlines from keel to deck)
    n_waterlines = 11
    z = range(-Draft, 0.0, length=n_waterlines)

    # Half-breadth offsets [x_idx, z_idx]
    y_offsets = zeros(n_stations, n_waterlines)

    # Generate offsets for a simple ship-like form
    # Using a combination of parabolic bow, parallel midbody, and tapered stern
    for (i, xi) in enumerate(x)
        for (j, zj) in enumerate(z)
            # Normalized position along length
            x_norm = xi / LOA

            # Vertical position (0 at keel, 1 at waterline)
            z_norm = (zj + Draft) / Draft

            # Sectional area curve (waterline half-breadth variation)
            if x_norm < 0.15
                # Bow: U-shaped sections, fine entry
                beam_factor = (x_norm / 0.15)^1.5
            elseif x_norm < 0.7
                # Parallel midbody: full beam
                beam_factor = 1.0
            else
                # Stern: tapered, slightly fuller than bow
                stern_norm = (x_norm - 0.7) / 0.3
                beam_factor = 1.0 - stern_norm^1.2
            end

            # Vertical shape: vary from keel (more V-shaped) to waterline (fuller)
            # Using a deadrise angle that decreases with height
            if z_norm < 0.5
                # Lower hull: more V-shaped (smaller half-breadth)
                vertical_factor = z_norm^0.7
            else
                # Upper hull: fuller sections
                vertical_factor = 0.5^0.7 + (z_norm - 0.5) * (1.0 - 0.5^0.7) / 0.5
            end

            # Combine factors
            y_offsets[i, j] = 0.5 * Beam * beam_factor * vertical_factor
        end
    end

    return collect(x), y_offsets, collect(z)
end

"""
    print_hydrostatic_properties(props::HydrostaticProperties, LOA::Float64=1.0)

Pretty-print hydrostatic properties.

# Arguments
- `props::HydrostaticProperties`: Properties to display
- `LOA::Float64`: Length overall for non-dimensionalization
"""
function print_hydrostatic_properties(props::HydrostaticProperties, LOA::Float64=1.0)
    println("═" ^ 70)
    println("Hydrostatic Properties at Draft = $(props.draft) m")
    println("─" ^ 70)
    @printf("  Draft / LOA              : %.4f\n", props.draft / LOA)
    @printf("  Displaced Volume         : %.4f m³\n", props.volume)
    @printf("  Volume / LOA³            : %.6f\n", props.volume / LOA^3)
    @printf("  Waterplane Area          : %.4f m²\n", props.waterplane_area)
    @printf("  Area_WP / LOA²           : %.6f\n", props.waterplane_area / LOA^2)
    @printf("  LCB (from bow)           : %.4f m\n", props.lcb)
    @printf("  LCB / LOA                : %.4f\n", props.lcb / LOA)
    @printf("  VCB (from keel)          : %.4f m\n", props.vcb + props.draft)
    @printf("  VCB / Draft              : %.4f\n", (props.vcb + props.draft) / props.draft)
    @printf("  LCF (from bow)           : %.4f m\n", props.lcf)
    @printf("  LCF / LOA                : %.4f\n", props.lcf / LOA)
    @printf("  Ixx (transverse)         : %.4f m⁴\n", props.ixx)
    @printf("  Iyy (longitudinal)       : %.4f m⁴\n", props.iyy)
    @printf("  Wetted Surface Area      : %.4f m²\n", props.wetted_surface)
    @printf("  WSA / LOA²               : %.6f\n", props.wetted_surface / LOA^2)
    @printf("  Waterline Length         : %.4f m\n", props.waterline_length)
    @printf("  WL / LOA                 : %.4f\n", props.waterline_length / LOA)
    println("═" ^ 70)
end

"""
    print_hydrostatic_curves(results::Vector{HydrostaticProperties}, LOA::Float64=1.0)

Print a table of hydrostatic properties across multiple drafts.

# Arguments
- `results::Vector{HydrostaticProperties}`: Array of properties at different drafts
- `LOA::Float64`: Length overall for non-dimensionalization
"""
function print_hydrostatic_curves(results::Vector{HydrostaticProperties}, LOA::Float64=1.0)
    println("\n" * "═" ^ 120)
    println("Hydrostatic Curves")
    println("═" ^ 120)

    # Header
    @printf("%-10s %-12s %-12s %-12s %-12s %-12s %-12s %-12s\n",
            "T/D", "∇/L³", "Awp/L²", "LCB/L", "VCB/T", "LCF/L", "WSA/L²", "WL/L")
    println("─" ^ 120)

    # Data rows
    for props in results
        if props.volume > 1e-10  # Skip near-zero volumes
            @printf("%-10.4f %-12.6f %-12.6f %-12.4f %-12.4f %-12.4f %-12.6f %-12.4f\n",
                    props.draft / (results[end].draft),  # Normalized draft
                    props.volume / LOA^3,
                    props.waterplane_area / LOA^2,
                    props.lcb / LOA,
                    (props.vcb + props.draft) / props.draft,
                    props.lcf / LOA,
                    props.wetted_surface / LOA^2,
                    props.waterline_length / LOA)
        end
    end

    println("═" ^ 120)
    println("Legend:")
    println("  T/D   = Draft ratio (T/Draft_max)")
    println("  ∇/L³  = Displaced volume coefficient")
    println("  Awp/L²= Waterplane area coefficient")
    println("  LCB/L = Longitudinal center of buoyancy")
    println("  VCB/T = Vertical center of buoyancy")
    println("  LCF/L = Longitudinal center of flotation")
    println("  WSA/L²= Wetted surface area coefficient")
    println("  WL/L  = Waterline length ratio")
    println("═" ^ 120)
end

"""
    export_to_csv(results::Vector{HydrostaticProperties}, filename::String)

Export hydrostatic results to CSV file.

# Arguments
- `results::Vector{HydrostaticProperties}`: Array of properties at different drafts
- `filename::String`: Output CSV file path

# Note
Requires CSV and DataFrames packages to be installed.
"""
function export_to_csv(results::Vector{HydrostaticProperties}, filename::String)
    try
        # Try to load CSV and DataFrames packages
        CSV = Base.require(Main, :CSV)
        DataFrames = Base.require(Main, :DataFrames)

        # Create DataFrame
        df = DataFrames.DataFrame(
            draft = [p.draft for p in results],
            volume = [p.volume for p in results],
            waterplane_area = [p.waterplane_area for p in results],
            lcb = [p.lcb for p in results],
            vcb = [p.vcb for p in results],
            lcf = [p.lcf for p in results],
            ixx = [p.ixx for p in results],
            iyy = [p.iyy for p in results],
            wetted_surface = [p.wetted_surface for p in results],
            waterline_length = [p.waterline_length for p in results]
        )

        CSV.write(filename, df)
        println("✓ Results exported to: $filename")
    catch e
        println("✗ Could not export to CSV. Install CSV and DataFrames packages:")
        println("  julia -e 'using Pkg; Pkg.add([\"CSV\", \"DataFrames\"])'")
        # Uncomment to see full error:
        # println("  Error: $e")
    end
end

"""
    main()

Main demonstration function.
"""
function main()
    println("\n" * "═" ^ 70)
    println("Ship-D Hydrostatics Demonstration")
    println("═" ^ 70)

    # Load sample hull offset data
    println("\n[1/3] Loading hull offset data...")
    x, y_offsets, z = load_sample_offsets()

    LOA = x[end] - x[1]
    n_stations = length(x)
    n_waterlines = length(z)

    println("  ✓ Hull offsets loaded")
    @printf("    - Length (LOA): %.2f m\n", LOA)
    @printf("    - Longitudinal stations: %d\n", n_stations)
    @printf("    - Vertical waterlines: %d\n", n_waterlines)
    @printf("    - Draft: %.4f m\n", abs(z[1]))

    # Calculate hydrostatic properties
    println("\n[2/3] Calculating hydrostatic properties...")
    results = calculate_hydrostatics(x, y_offsets, z)
    println("  ✓ Calculations complete")
    @printf("    - Properties calculated at %d drafts\n", length(results))

    # Display results
    println("\n[3/3] Displaying results...")

    # Show detailed properties at design draft (100% draft)
    print_hydrostatic_properties(results[end], LOA)

    # Show properties at multiple drafts (12%, 25%, 50%, 75%, 100%)
    draft_percentages = [0.12, 0.25, 0.50, 0.75, 1.0]
    selected_indices = [round(Int, p * length(results)) for p in draft_percentages]
    selected_indices = [max(1, min(i, length(results))) for i in selected_indices]

    print_hydrostatic_curves(results[selected_indices], LOA)

    # Optional: Export to CSV
    println("\n[Optional] Export results to CSV? (requires CSV and DataFrames packages)")
    println("  Uncomment the line below to enable export:")
    println("  # export_to_csv(results, \"hydrostatic_results.csv\")")

    println("\n✓ Demonstration complete!\n")

    return results
end

# Run demonstration if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    results = main()
end
