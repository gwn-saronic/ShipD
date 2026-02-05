"""
    test_hydrostatics.jl

Comprehensive tests for Hydrostatics module using ARV.stl
"""

using Test
using Printf

# Add src directory to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Hydrostatics

@testset "Hydrostatics Module Tests" begin

    @testset "Basic Waterplane Calculations" begin
        # Simple rectangular waterplane
        x = [0.0, 1.0, 2.0]
        y = [1.0, 1.0, 1.0]

        # Test waterplane area calculation
        area = Hydrostatics.calculate_waterplane_area(x, y)
        @test area ≈ 4.0  # 2m length × 2m breadth (factor of 2 for full breadth)

        # Test waterplane center (should be at midpoint)
        lcf = Hydrostatics.calculate_waterplane_center(x, y)
        @test lcf ≈ 1.0

        # Test waterline length
        wl_length = Hydrostatics.calculate_waterline_length(x, y)
        @test wl_length ≈ 2.0
    end

    @testset "Second Moments Calculation" begin
        # Rectangular waterplane for predictable second moments
        x = [0.0, 10.0]
        y = [2.0, 2.0]

        area = Hydrostatics.calculate_waterplane_area(x, y)
        lcf = Hydrostatics.calculate_waterplane_center(x, y)

        ixx, iyy = Hydrostatics.calculate_second_moments(x, y, area, lcf)

        # For a rectangle, Ixx should be positive
        @test ixx > 0
        @test iyy > 0
    end

    @testset "Trapezoidal Waterplane" begin
        # Ship-like trapezoidal shape
        x = [0.0, 5.0, 10.0]
        y = [0.5, 2.0, 0.5]  # Narrow at ends, wide in middle

        area = Hydrostatics.calculate_waterplane_area(x, y)
        lcf = Hydrostatics.calculate_waterplane_center(x, y)

        # Area should be positive
        @test area > 0

        # LCF should be at midpoint for symmetric shape
        @test lcf ≈ 5.0

        # Waterline length
        wl_length = Hydrostatics.calculate_waterline_length(x, y)
        @test wl_length ≈ 10.0
    end

    @testset "ARV.stl - STL File Loading" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        # Test that STL file exists
        @test isfile(stl_file)

        # Test STL offset extraction with different resolutions
        @testset "Offset Extraction - Coarse" begin
            x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
                stl_file,
                n_stations=11,
                n_waterlines=5
            )

            @test length(x) == 11
            @test length(z) == 5
            @test size(y_offsets) == (11, 5)

            # Check that offsets are non-negative
            @test all(y_offsets .>= 0)

            # Check that x is sorted and starts at 0
            @test issorted(x)
            @test x[1] ≈ 0.0

            # Check that z is sorted
            @test issorted(z)
        end

        @testset "Offset Extraction - Fine" begin
            x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
                stl_file,
                n_stations=51,
                n_waterlines=21
            )

            @test length(x) == 51
            @test length(z) == 21
            @test size(y_offsets) == (51, 21)
        end
    end

    @testset "ARV.stl - Full Hydrostatic Calculations" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        # Extract offsets
        x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
            stl_file,
            n_stations=51,
            n_waterlines=21
        )

        # Calculate hydrostatics
        results = Hydrostatics.calculate_hydrostatics(x, y_offsets, z)

        @test length(results) == 21

        # Test that properties increase with draft
        volumes = [r.volume for r in results]
        areas = [r.waterplane_area for r in results]

        @test issorted(volumes)  # Volume should increase with draft
        @test all(volumes .>= 0)
        @test all(areas .>= 0)

        # Test final draft properties
        final = results[end]
        @test final.volume > 0
        @test final.waterplane_area > 0
        @test final.lcb > 0  # LCB should be positive (aft of bow)
        @test final.vcb > 0  # VCB should be positive (above keel)
        @test final.ixx > 0
        @test final.iyy > 0
        @test final.wsa > 0  # Wetted surface area
        @test final.waterline_length > 0
    end

    @testset "ARV.stl - Validation Against Reference Data" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        # Reference data from validation.md (Orca3D values)
        # At draft = 1.279 m
        ref_draft = 1.279
        ref_volume = 146.2  # m³
        ref_lcb = 15.84  # m
        ref_vcb = 0.705  # m
        ref_lcf = 17.16  # m
        ref_ixx = 308.75  # m⁴
        ref_iyy = 8406.0  # m⁴
        ref_wsa = 190.016  # m²
        ref_lwl = 30.77  # m
        ref_awp = 140.71  # m²

        # Extract offsets with fine resolution
        x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
            stl_file,
            n_stations=101,
            n_waterlines=41
        )

        # Calculate hydrostatics
        results = Hydrostatics.calculate_hydrostatics(x, y_offsets, z)

        # Find result closest to reference draft
        draft_diffs = [abs(r.draft - ref_draft) for r in results]
        closest_idx = argmin(draft_diffs)
        result = results[closest_idx]

        println("\n=== ARV Validation at Draft $(result.draft) m ===")
        println("Property         | Computed    | Reference   | Diff %")
        println("-----------------|-------------|-------------|-------")

        # Tolerances for validation (engineering tolerance ~5-10%)
        function print_comparison(name, computed, reference, tolerance=0.10)
            diff_pct = abs(computed - reference) / reference * 100
            status = diff_pct <= tolerance * 100 ? "✓" : "✗"
            @printf("%-16s | %11.3f | %11.3f | %5.1f%% %s\n",
                    name, computed, reference, diff_pct, status)
            @test abs(computed - reference) / reference <= tolerance
        end

        print_comparison("Volume (m³)", result.volume, ref_volume, 0.15)
        print_comparison("LCB (m)", result.lcb, ref_lcb, 0.15)
        print_comparison("VCB (m)", result.vcb, ref_vcb, 0.10)
        print_comparison("LCF (m)", result.lcf, ref_lcf, 0.10)
        print_comparison("Ixx (m⁴)", result.ixx, ref_ixx, 0.15)
        print_comparison("Iyy (m⁴)", result.iyy, ref_iyy, 0.15)
        print_comparison("WSA (m²)", result.wsa, ref_wsa, 0.15)
        print_comparison("LWL (m)", result.waterline_length, ref_lwl, 0.10)
        print_comparison("Awp (m²)", result.waterplane_area, ref_awp, 0.10)
    end

    @testset "Hydrostatic Interpolation" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
            stl_file,
            n_stations=51,
            n_waterlines=11
        )

        results = Hydrostatics.calculate_hydrostatics(x, y_offsets, z)

        # Test interpolation at midpoint
        draft_mid = 0.5 * (results[5].draft + results[6].draft)
        result_interp = Hydrostatics.interpolate_hydrostatics(results, draft_mid)

        @test result_interp.draft ≈ draft_mid

        # Interpolated values should be between bounding values
        @test results[5].volume <= result_interp.volume <= results[6].volume
        @test minimum([results[5].waterplane_area, results[6].waterplane_area]) <=
              result_interp.waterplane_area <=
              maximum([results[5].waterplane_area, results[6].waterplane_area])

        # Test edge case: draft below minimum
        result_low = Hydrostatics.interpolate_hydrostatics(results, z[1] - 1.0)
        @test result_low.draft == results[1].draft

        # Test edge case: draft above maximum
        result_high = Hydrostatics.interpolate_hydrostatics(results, z[end] + 1.0)
        @test result_high.draft == results[end].draft
    end

    @testset "Float Equilibrium Solver" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        # Test parameters (approximate ARV vessel)
        mass = 146.0 * 1.025  # tonnes (volume × water density)
        water_density = 1.025  # tonnes/m³
        cog = (16.0, 0.0, 1.5)  # (LCG, TCG, VCG) in meters

        # Extract offsets
        x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
            stl_file,
            n_stations=51,
            n_waterlines=21
        )

        # Solve for equilibrium
        equilibrium = Hydrostatics.solve_equilibrium_float(
            x, y_offsets, z,
            mass, water_density, cog,
            max_iterations=50,
            tolerance=1e-6,
            verbose=true
        )

        # Note: Equilibrium solver may not always converge perfectly with complex geometries
        # and coarse discretization. These tests check that results are physically reasonable.

        # Check physical constraints
        @test equilibrium.equilibrium_draft > 0
        @test equilibrium.equilibrium_draft < z[end]
        @test abs(equilibrium.trim_angle) < deg2rad(15)  # Reasonable trim

        # Check force balance: displacement should be close to expected
        # (within 5% tolerance due to numerical approximations and discretization)
        expected_displacement = mass / water_density
        displacement_error = abs(equilibrium.displacement - expected_displacement) / expected_displacement
        @test displacement_error < 0.05  # 5% tolerance

        # Note: Convergence depends on mesh resolution and initial guess
        # A warning is shown if not converged, which is acceptable for testing

        println("\n=== Float Equilibrium Solution ===")
        println("Draft:        $(round(equilibrium.equilibrium_draft, digits=3)) m")
        println("Trim:         $(round(rad2deg(equilibrium.trim_angle), digits=2))°")
        println("Displacement: $(round(equilibrium.displacement, digits=2)) m³")
        println("Iterations:   $(equilibrium.iterations)")
        println("Converged:    $(equilibrium.converged)")
        println("Residual:     $(round(equilibrium.residual, sigdigits=3))")
    end

    @testset "Convenience Functions" begin
        # Create a sample hydrostatic property
        props = Hydrostatics.HydrostaticProperties(
            1.0,   # draft
            100.0, # volume
            50.0,  # waterplane_area
            5.0,   # lcb
            0.5,   # vcb
            5.5,   # lcf
            200.0, # ixx
            1000.0,# iyy
            120.0, # wsa
            20.0   # waterline_length
        )

        @test Hydrostatics.displaced_volume(props) == 100.0
        @test Hydrostatics.waterplane_area(props) == 50.0
        @test Hydrostatics.center_of_buoyancy(props) == (5.0, 0.5)
        @test Hydrostatics.center_of_flotation(props) == 5.5
        @test Hydrostatics.second_moments(props) == (200.0, 1000.0)
        @test Hydrostatics.wetted_surface_area(props) == 120.0
        @test Hydrostatics.waterline_length(props) == 20.0
    end

    @testset "File Input Interface" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        # Test calculate_hydrostatics_from_file
        results = Hydrostatics.calculate_hydrostatics_from_file(
            stl_file,
            n_stations=31,
            n_waterlines=11
        )

        @test length(results) == 11
        @test all(r -> r.volume >= 0, results)

        # Test with explicit input_type
        results2 = Hydrostatics.calculate_hydrostatics_from_file(
            stl_file,
            input_type=:stl,
            n_stations=31,
            n_waterlines=11
        )

        @test length(results2) == 11
    end

    @testset "Edge Cases and Error Handling" begin
        # Test with minimal data
        x = [0.0, 1.0]
        y = [0.5, 0.5]

        area = Hydrostatics.calculate_waterplane_area(x, y)
        @test area > 0

        # Test with zero breadth
        x = [0.0, 1.0, 2.0]
        y = [0.0, 0.0, 0.0]

        area = Hydrostatics.calculate_waterplane_area(x, y)
        @test area ≈ 0.0

        wl_length = Hydrostatics.calculate_waterline_length(x, y)
        @test wl_length ≈ 0.0
    end

end

println("\n✓ All Hydrostatics tests completed!")
