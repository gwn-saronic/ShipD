# ShipD Julia Tests

Comprehensive test suite for the ShipD hydrostatics and stability analysis modules.

## Test Files

### [test_hydrostatics.jl](test_hydrostatics.jl)
Tests for the Hydrostatics module including:
- Basic waterplane calculations (area, center of flotation, second moments)
- STL file loading and offset extraction
- Full hydrostatic calculations from ARV.stl
- Validation against reference data (Orca3D, GHS)
- Hydrostatic interpolation
- Float equilibrium solver
- Edge cases and error handling

### [test_stability.jl](test_stability.jl)
Tests for the StabilityAnalysis module including:
- Metacentric property calculations (KB, BM, KM, GM)
- Small angle righting arm calculations
- GZ curve generation
- Stability criteria checks (IMO criteria)
- Full stability analysis using ARV.stl
- Combined equilibrium and stability analysis
- Edge cases (zero volume, very small volumes)

## Running Tests

### Run All Tests
```bash
cd tests
julia runtests.jl
```

### Run Individual Test Files
```bash
# Hydrostatics tests only
julia test_hydrostatics.jl

# Stability tests only
julia test_stability.jl
```

### Run from Julia REPL
```julia
# Run all tests
include("tests/runtests.jl")

# Run specific test file
include("tests/test_hydrostatics.jl")
include("tests/test_stability.jl")
```

## Test Data

The tests use **ARV.stl** (26MB STL file located in the repository root) as the test geometry. This represents a realistic vessel hull with known hydrostatic and stability properties.

### Reference Data

Validation data is compared against commercial naval architecture software:
- **Orca3D**: Professional marine design software
- **GHS**: General HydroStatics software

Reference values at draft = 1.279 m:
- Volume: 146.2 m³
- LCB: 15.84 m
- VCB: 0.705 m
- LCF: 17.16 m
- Ixx: 308.75 m⁴
- Iyy: 8406 m⁴
- WSA: 190.016 m²
- LWL: 30.77 m
- Awp: 140.71 m²
- GM_t: 0.816 m
- GM_l: 56.198 m

See [validation.md](validation.md) for complete reference data.

## Test Coverage

The test suite covers:

✓ **Unit Tests**: Individual function correctness
✓ **Integration Tests**: Full workflow from STL to results
✓ **Validation Tests**: Comparison with industry-standard tools
✓ **Edge Cases**: Boundary conditions and error handling
✓ **Physical Constraints**: Results satisfy physics (positive volumes, GM, etc.)

## Expected Test Results

All tests should pass with computed values within **5-15%** of reference values. Differences are expected due to:
- Different mesh discretization methods
- Numerical integration tolerances
- STL geometry approximations vs NURBS surfaces used in commercial software

## Dependencies

Required Julia packages (listed in Project.toml):
- `Test` (built-in)
- Any dependencies of Hydrostatics.jl and StabilityAnalysis.jl

## Notes

- Tests automatically locate the ARV.stl file in the repository root
- Some tests may take several seconds due to fine mesh resolution (101 stations × 41 waterlines)
- Verbose output can be enabled in equilibrium solver tests by setting `verbose=true`
