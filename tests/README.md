# Ship-D Julia Tests

Test suite for the Julia hydrostatics and analysis modules.

## Running Tests

### Run All Tests
```bash
# From the repository root
julia tests/test_hydrostatics.jl
julia tests/test_stability_features.jl
julia tests/test_all_inputs.jl
```

### Individual Test Files

#### test_hydrostatics.jl
Basic tests for the Hydrostatics module:
- Module loading
- Waterplane area calculation
- Full hydrostatics calculation with synthetic hull
- Volume, LCB, VCB verification

```bash
julia tests/test_hydrostatics.jl
```

#### test_stability_features.jl
Tests for stability analysis features:
- Stability properties calculation
- Metacentric height (GM)
- Righting arm (GZ) curves
- Form coefficients (Cb, Cp, Cwp, etc.)

```bash
julia tests/test_stability_features.jl
```

#### test_all_inputs.jl
Tests for multiple input methods:
- Direct offset input
- STL file input
- Type-safe input interfaces
- Input validation

```bash
julia tests/test_all_inputs.jl
```

## Test Data

The tests use:
- Synthetic hull data (generated programmatically)
- Sample STL files from the repository root:
  - `ARV.stl`
  - `sample_Hull_Mesh.stl`

## Expected Output

All tests should print:
```
✓ Test passed
```

If a test fails, it will print:
```
✗ Test failed: [error message]
```

## Adding New Tests

When adding new features, please add corresponding tests to the appropriate test file or create a new test file following the naming convention `test_*.jl`.
