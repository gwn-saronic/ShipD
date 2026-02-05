"""
    runtests.jl

Main test runner for ShipD Julia modules
Runs all test suites for Hydrostatics and Stability analysis
"""

using Test

println("="^70)
println("ShipD Julia Test Suite")
println("="^70)
println()

# Track overall results
test_files = [
    "test_hydrostatics.jl",
    "test_stability.jl"
]

all_passed = true

for test_file in test_files
    println("\n" * "="^70)
    println("Running: $test_file")
    println("="^70)

    try
        include(test_file)
    catch e
        println("\n❌ Tests in $test_file failed with error:")
        println(e)
        all_passed = false
    end
end

println("\n" * "="^70)
if all_passed
    println("✓ All test suites completed successfully!")
else
    println("❌ Some tests failed. Please review the output above.")
end
println("="^70)
