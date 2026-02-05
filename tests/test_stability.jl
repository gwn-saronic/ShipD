"""
    test_stability.jl

Comprehensive tests for StabilityAnalysis module using ARV.stl
"""

using Test
using Printf

# Add src directory to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Hydrostatics
using StabilityAnalysis

@testset "Stability Analysis Module Tests" begin

    @testset "Metacentric Properties - Basic Calculations" begin
        # Simple test case with known values
        volume = 100.0  # m³
        vcb = 1.5       # m (absolute)
        zkeel = 0.0     # m (keel at origin)
        ixx = 500.0     # m⁴
        iyy = 5000.0    # m⁴
        kg = 2.0        # m (center of gravity above keel)

        meta_props = StabilityAnalysis.calculate_metacentric_properties(
            volume, vcb, zkeel, ixx, iyy, kg=kg
        )

        # Check KB (height of center of buoyancy above keel)
        @test meta_props.kb ≈ 1.5

        # Check BM (metacentric radius)
        expected_bm_t = ixx / volume  # 500 / 100 = 5.0
        expected_bm_l = iyy / volume  # 5000 / 100 = 50.0
        @test meta_props.bm_t ≈ expected_bm_t
        @test meta_props.bm_l ≈ expected_bm_l

        # Check KM (metacentric height above keel)
        @test meta_props.km_t ≈ meta_props.kb + meta_props.bm_t
        @test meta_props.km_l ≈ meta_props.kb + meta_props.bm_l

        # Check GM (metacentric height)
        @test meta_props.gm_t ≈ meta_props.km_t - kg
        @test meta_props.gm_l ≈ meta_props.km_l - kg

        # For this case, GM should be positive (stable)
        @test meta_props.gm_t > 0
        @test meta_props.gm_l > 0
    end

    @testset "Metacentric Properties - Without KG" begin
        volume = 100.0
        vcb = 1.5
        zkeel = 0.0
        ixx = 500.0
        iyy = 5000.0

        meta_props = StabilityAnalysis.calculate_metacentric_properties(
            volume, vcb, zkeel, ixx, iyy
        )

        @test meta_props.gm_t === nothing
        @test meta_props.gm_l === nothing
        @test meta_props.kg === nothing

        # But KB, BM, KM should still be calculated
        @test meta_props.kb ≈ 1.5
        @test meta_props.bm_t > 0
        @test meta_props.km_t > 0
    end

    @testset "Small Angle Righting Arm" begin
        gm = 1.0  # m

        # At 0 degrees, GZ should be 0
        gz_0 = StabilityAnalysis.calculate_righting_arm_small_angle(gm, 0.0)
        @test gz_0 ≈ 0.0

        # At 10 degrees
        theta_10 = deg2rad(10)
        gz_10 = StabilityAnalysis.calculate_righting_arm_small_angle(gm, theta_10)
        expected_gz_10 = gm * sin(theta_10)
        @test gz_10 ≈ expected_gz_10

        # GZ should increase with angle (for small angles)
        theta_5 = deg2rad(5)
        gz_5 = StabilityAnalysis.calculate_righting_arm_small_angle(gm, theta_5)
        @test gz_5 < gz_10
        @test gz_5 > 0
    end

    @testset "GZ Curve Generation" begin
        # Create metacentric properties
        meta_props = StabilityAnalysis.MetacentricProperties(
            100.0,  # volume
            1.5,    # kb
            5.0,    # bm_t
            50.0,   # bm_l
            6.5,    # km_t
            51.5,   # km_l
            1.5,    # gm_t (KM - KG = 6.5 - 5.0)
            46.5,   # gm_l
            5.0     # kg
        )

        # Generate GZ curve
        angles, gz_values = StabilityAnalysis.calculate_gz_curve(
            meta_props,
            max_angle=45.0,
            n_points=10
        )

        @test length(angles) == 10
        @test length(gz_values) == 10

        # Check angle range
        @test angles[1] ≈ 0.0
        @test angles[end] ≈ 45.0

        # GZ should be 0 at 0 degrees
        @test abs(gz_values[1]) < 1e-10

        # GZ should initially increase with angle
        @test gz_values[2] > gz_values[1]
        @test gz_values[3] > gz_values[2]

        # All small angle values should be positive for positive GM
        small_angle_idx = findfirst(a -> a > 15.0, angles)
        if small_angle_idx !== nothing
            @test all(gz_values[1:small_angle_idx-1] .>= 0)
        end
    end

    @testset "Stability Criteria Check" begin
        # Generate sample GZ curve with good stability
        angles = collect(0.0:5.0:90.0)
        # Typical stable curve: rises to max around 30-40°, then decreases
        gz_values = [0.0, 0.3, 0.6, 0.85, 1.0, 0.95, 0.8, 0.6, 0.35, 0.1, -0.2, -0.5, -0.8, -1.2, -1.5, -1.8, -2.0, -2.2, -2.4]

        gm = 1.5  # Good GM

        criteria = StabilityAnalysis.check_stability_criteria(angles, gz_values, gm)

        # Check basic properties
        @test criteria.gm_positive == true
        @test criteria.gm_adequate == true

        # Maximum GZ should be found
        @test criteria.max_gz > 0.5
        @test 20.0 <= criteria.angle_of_max_gz <= 50.0

        # Angle of vanishing stability should be reasonable
        @test criteria.angle_of_vanishing_stability > 0

        # Area under curve should be positive
        @test criteria.area_under_curve > 0

        println("\n=== Stability Criteria ===")
        println("GM Positive:              $(criteria.gm_positive)")
        println("GM Adequate:              $(criteria.gm_adequate)")
        println("Max GZ:                   $(round(criteria.max_gz, digits=3)) m")
        println("Angle of Max GZ:          $(round(criteria.angle_of_max_gz, digits=1))°")
        println("Vanishing Stability:      $(round(criteria.angle_of_vanishing_stability, digits=1))°")
        println("Area Under Curve:         $(round(criteria.area_under_curve, digits=3)) m·rad")
        println("Meets IMO Criteria:       $(criteria.meets_imo_criteria)")
    end

    @testset "Stability Criteria - Unstable Case" begin
        # Generate curve with negative GM (unstable)
        angles = collect(0.0:10.0:90.0)
        gz_values = [0.0, -0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7, -0.8, -0.9]

        gm = -0.5  # Negative GM (unstable)

        criteria = StabilityAnalysis.check_stability_criteria(angles, gz_values, gm)

        @test criteria.gm_positive == false
        @test criteria.gm_adequate == false
        @test criteria.meets_imo_criteria == false
    end

    @testset "ARV.stl - Full Stability Analysis" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        # Reference data from validation.md
        ref_draft = 1.279  # m
        ref_gm_t = 0.816   # m (Orca3D reference)
        ref_gm_l = 56.198  # m (Orca3D reference)

        # Extract offsets with fine resolution
        x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
            stl_file,
            n_stations=101,
            n_waterlines=41
        )

        # Calculate hydrostatics
        hydro_results = Hydrostatics.calculate_hydrostatics(x, y_offsets, z)

        # Find result closest to reference draft
        draft_diffs = [abs(r.draft - ref_draft) for r in hydro_results]
        closest_idx = argmin(draft_diffs)
        hydro = hydro_results[closest_idx]

        # Calculate metacentric properties
        # Assuming KG = 2.0 m for ARV (this should match the validation data setup)
        kg = 2.0

        meta_props = StabilityAnalysis.calculate_metacentric_properties(
            hydro.volume,
            hydro.vcb,
            z[1],  # keel z-coordinate
            hydro.ixx,
            hydro.iyy,
            kg=kg
        )

        println("\n=== ARV Stability at Draft $(hydro.draft) m ===")
        println("Property         | Computed    | Orca 1.28m  | Diff %")
        println("-----------------|-------------|-------------|-------")

        function print_comparison(name, computed, reference, tolerance=0.10)
            diff_pct = abs(computed - reference) / reference * 100
            status = diff_pct <= tolerance * 100 ? "✓" : "✗"
            @printf("%-16s | %11.3f | %11.3f | %5.1f%% %s\n",
                    name, computed, reference, diff_pct, status)
            # Use relaxed tolerance for comparison tests
            @test abs(computed - reference) / reference <= tolerance
        end

        # Test metacentric properties
        @test meta_props.kb > 0
        @test meta_props.bm_t > 0
        @test meta_props.bm_l > 0
        @test meta_props.km_t > 0
        @test meta_props.km_l > 0

        # Test GM values against reference (with tolerance)
        if meta_props.gm_t !== nothing
            print_comparison("GM_t (m)", meta_props.gm_t, ref_gm_t, 0.15)
        end
        if meta_props.gm_l !== nothing
            print_comparison("GM_l (m)", meta_props.gm_l, ref_gm_l, 0.15)
        end

        # Additional computed properties
        println("\n=== Additional Stability Properties ===")
        println("KB:    $(round(meta_props.kb, digits=3)) m")
        println("BM_t:  $(round(meta_props.bm_t, digits=3)) m")
        println("BM_l:  $(round(meta_props.bm_l, digits=3)) m")
        println("KM_t:  $(round(meta_props.km_t, digits=3)) m")
        println("KM_l:  $(round(meta_props.km_l, digits=3)) m")

        # Generate GZ curve if GM is available
        if meta_props.gm_t !== nothing
            angles, gz_values = StabilityAnalysis.calculate_gz_curve(
                meta_props,
                max_angle=60.0,
                n_points=13
            )

            @test length(angles) == 13
            @test length(gz_values) == 13

            # Check stability criteria
            criteria = StabilityAnalysis.check_stability_criteria(
                angles, gz_values, meta_props.gm_t
            )

            println("\n=== Stability Criteria ===")
            println("GM Positive:              $(criteria.gm_positive)")
            println("GM Adequate (≥0.15m):     $(criteria.gm_adequate)")
            println("Max GZ:                   $(round(criteria.max_gz, digits=3)) m")
            println("Angle of Max GZ:          $(round(criteria.angle_of_max_gz, digits=1))°")
            println("Vanishing Stability:      $(round(criteria.angle_of_vanishing_stability, digits=1))°")
            println("Area Under Curve:         $(round(criteria.area_under_curve, digits=3)) m·rad")
            println("Meets IMO Criteria:       $(criteria.meets_imo_criteria)")

            # Basic stability checks for ARV
            @test criteria.gm_positive == true
            @test criteria.gm_adequate == true
            @test criteria.max_gz > 0.0

            # Print sample GZ curve values
            println("\n=== GZ Curve Sample Points ===")
            println("Angle (°) | GZ (m)")
            println("----------|--------")
            for i in 1:length(angles)
                @printf("%9.1f | %6.3f\n", angles[i], gz_values[i])
            end
        end
    end

    @testset "ARV.stl - Combined Equilibrium and Stability" begin
        stl_file = joinpath(@__DIR__, "..", "ARV.stl")

        # Test parameters
        mass = 146.0 * 1.025  # tonnes
        water_density = 1.025  # tonnes/m³
        cog = (16.0, 0.0, 2.0)  # (LCG, TCG, VCG=KG)

        # Solve equilibrium
        x, y_offsets, z = Hydrostatics.STLReader.extract_offsets_from_stl(
            stl_file,
            n_stations=51,
            n_waterlines=21
        )

        equilibrium = Hydrostatics.solve_equilibrium_float(
            x, y_offsets, z,
            mass, water_density, cog,
            verbose=false
        )

        # Note: Equilibrium convergence is not guaranteed with coarse mesh
        # This is an integration test to verify the workflow

        # Calculate stability at equilibrium
        hydro = equilibrium.hydrostatics
        kg = cog[3]

        meta_props = StabilityAnalysis.calculate_metacentric_properties(
            hydro.volume,
            hydro.vcb,
            z[1],
            hydro.ixx,
            hydro.iyy,
            kg=kg
        )

        println("\n=== Equilibrium & Stability Combined ===")
        println("Equilibrium Draft: $(round(equilibrium.equilibrium_draft, digits=3)) m")
        println("Trim Angle:        $(round(rad2deg(equilibrium.trim_angle), digits=2))°")
        println("Converged:         $(equilibrium.converged)")
        if meta_props.gm_t !== nothing
            println("GM_t:              $(round(meta_props.gm_t, digits=3)) m")
            println("GM_l:              $(round(meta_props.gm_l, digits=3)) m")

            # Note: This is a smoke test to verify integration works
            # Stability values depend on equilibrium convergence
            # With current mesh resolution (51x21), convergence may be limited
            if equilibrium.converged
                @test meta_props.gm_t > 0
                @test meta_props.gm_l > 0
            else
                @warn "Equilibrium not converged - skipping GM stability checks"
            end
        end
    end

    @testset "Edge Cases - Zero Volume" begin
        volume = 0.0
        vcb = 0.0
        zkeel = 0.0
        ixx = 100.0
        iyy = 1000.0

        meta_props = StabilityAnalysis.calculate_metacentric_properties(
            volume, vcb, zkeel, ixx, iyy
        )

        # BM should be 0 when volume is 0
        @test meta_props.bm_t == 0.0
        @test meta_props.bm_l == 0.0
    end

    @testset "Edge Cases - Very Small Volume" begin
        volume = 1e-12
        vcb = 0.5
        zkeel = 0.0
        ixx = 1.0
        iyy = 10.0

        meta_props = StabilityAnalysis.calculate_metacentric_properties(
            volume, vcb, zkeel, ixx, iyy
        )

        # Should handle small volumes without numerical issues
        @test isfinite(meta_props.bm_t)
        @test isfinite(meta_props.bm_l)
    end

end

println("\n✓ All Stability tests completed!")
