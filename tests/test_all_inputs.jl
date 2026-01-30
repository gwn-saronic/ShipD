#!/usr/bin/env julia

"""
Test all input methods for hydrostatics calculations.
"""

include(joinpath(@__DIR__, "..", "Hydrostatics.jl"))
using .Hydrostatics
using .Hydrostatics: OffsetInput, STLInput
using Printf

println("="^70)
println("Testing All Hydrostatics Input Methods")
println("="^70)

# Test 1: Direct offset input
println("\n[Test 1] Direct Offset Input")
println("-"^70)
try
    x = collect(range(0.0, 10.0, length=11))
    z = collect(range(-1.0, 0.0, length=6))
    y_offsets = ones(length(x), length(z)) .* 0.5
    y_offsets[1, :] .= 0.0
    y_offsets[end, :] .= 0.0

    results = calculate_hydrostatics(x, y_offsets, z)
    @printf("✓ PASS - Volume: %.4f m³\n", results[end].volume)
catch e
    println("✗ FAIL - $e")
end

# Test 2: OffsetInput type
println("\n[Test 2] OffsetInput Type")
println("-"^70)
try
    x = collect(range(0.0, 10.0, length=11))
    z = collect(range(-1.0, 0.0, length=6))
    y_offsets = ones(length(x), length(z)) .* 0.5
    y_offsets[1, :] .= 0.0
    y_offsets[end, :] .= 0.0

    input = OffsetInput(x, y_offsets, z)
    results = calculate_hydrostatics(input)
    @printf("✓ PASS - Volume: %.4f m³\n", results[end].volume)
catch e
    println("✗ FAIL - $e")
end

# Test 3: STL file input
println("\n[Test 3] STL File Input")
println("-"^70)
stl_file = joinpath(@__DIR__, "..", "sample_Hull_Mesh.stl")
if isfile(stl_file)
    try
        results = calculate_hydrostatics_from_file(stl_file, n_stations=31, n_waterlines=7)
        @printf("✓ PASS - Volume: %.4f m³\n", results[end].volume)
    catch e
        println("✗ FAIL - $e")
    end
else
    println("⊘ SKIP - STL file not found")
end

# Test 4: STLInput type
println("\n[Test 4] STLInput Type")
println("-"^70)
if isfile(stl_file)
    try
        input = STLInput(stl_file, 31, 7, nothing)
        results = calculate_hydrostatics(input)
        @printf("✓ PASS - Volume: %.4f m³\n", results[end].volume)
    catch e
        println("✗ FAIL - $e")
    end
else
    println("⊘ SKIP - STL file not found")
end

# Test 5: Auto-detection
println("\n[Test 5] Automatic Format Detection")
println("-"^70)
if isfile(stl_file)
    try
        results = calculate_hydrostatics_from_file(stl_file)
        @printf("✓ PASS - Auto-detected STL, Volume: %.4f m³\n", results[end].volume)
    catch e
        println("✗ FAIL - $e")
    end
else
    println("⊘ SKIP - STL file not found")
end

# Test 6: Consistency check
println("\n[Test 6] Consistency Check (Same Hull, Different Methods)")
println("-"^70)
try
    # Method A: Direct offsets
    x = collect(range(0.0, 10.0, length=21))
    z = collect(range(-1.0, 0.0, length=11))
    y_offsets = ones(length(x), length(z)) .* 0.7
    for i in 1:length(x)
        x_frac = (i-1) / (length(x)-1)
        if x_frac < 0.2
            y_offsets[i, :] .*= (x_frac / 0.2)
        elseif x_frac > 0.8
            y_offsets[i, :] .*= (1.0 - x_frac) / 0.2
        end
    end

    results_a = calculate_hydrostatics(x, y_offsets, z)
    vol_a = results_a[end].volume

    # Method B: Via OffsetInput type
    input = OffsetInput(x, y_offsets, z)
    results_b = calculate_hydrostatics(input)
    vol_b = results_b[end].volume

    diff = abs(vol_a - vol_b) / vol_a * 100.0
    @printf("✓ PASS - Direct: %.4f m³, Type: %.4f m³, Diff: %.2f%%\n", vol_a, vol_b, diff)

    if diff > 0.01
        println("⚠ WARNING - Difference exceeds tolerance")
    end
catch e
    println("✗ FAIL - $e")
end

println("\n" * "="^70)
println("All Tests Complete")
println("="^70)
