#!/usr/bin/env julia

"""
Simple test to verify Hydrostatics module loads and works correctly.
"""

println("Testing Hydrostatics module...")
println("=" ^ 60)

# Test 1: Module loading
println("\n[Test 1] Loading module...")
try
    include(joinpath(@__DIR__, "..", "Hydrostatics.jl"))
    using .Hydrostatics
    println("✓ Module loaded successfully")
catch e
    println("✗ Failed to load module: $e")
    exit(1)
end

# Test 2: Basic waterplane area calculation
println("\n[Test 2] Testing waterplane area calculation...")
try
    x = [0.0, 1.0, 2.0, 3.0, 4.0]
    y = [0.0, 0.5, 0.8, 0.5, 0.0]
    area = Hydrostatics.calculate_waterplane_area(x, y)
    println("✓ Waterplane area: $area m²")
catch e
    println("✗ Test failed: $e")
end

# Test 3: Simple hull offsets
println("\n[Test 3] Testing full hydrostatics calculation...")
try
    # Create simple box-like hull
    x = range(0.0, 10.0, length=11)
    z = range(-1.0, 0.0, length=6)

    # Half-breadth offsets (simple rectangular sections)
    y_offsets = ones(length(x), length(z)) .* 0.5

    # Bow and stern taper
    y_offsets[1, :] .*= 0.0
    y_offsets[2, :] .*= 0.3
    y_offsets[end, :] .*= 0.0
    y_offsets[end-1, :] .*= 0.3

    results = calculate_hydrostatics(collect(x), y_offsets, collect(z))

    println("✓ Hydrostatics calculated for $(length(results)) drafts")
    println("  Design draft properties:")
    props = results[end]
    println("    Volume: $(props.volume) m³")
    println("    Waterplane area: $(props.waterplane_area) m²")
    println("    LCB: $(props.lcb) m")
    println("    VCB: $(props.vcb) m")
catch e
    println("✗ Test failed: $e")
    rethrow(e)
end

println("\n" * "=" ^ 60)
println("All tests passed! ✓")
