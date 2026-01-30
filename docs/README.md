# Ship-D Julia Documentation

Detailed documentation for the Julia hydrostatics and analysis modules.

## Documentation Files

### Getting Started
- See [Quick Start Guide](../examples/QUICK_START_HYDROSTATICS.md) in the examples folder for basic usage

### API Reference
- [HYDROSTATICS_README.md](HYDROSTATICS_README.md) - Complete API documentation for hydrostatics calculations
- [INPUT_METHODS.md](INPUT_METHODS.md) - Guide to different input methods (offsets, STL files, Ship-D parameters)
- [STL_SUPPORT.md](STL_SUPPORT.md) - Working with STL files for hull analysis

### Feature Documentation
- [COMPLETE_FEATURES.md](COMPLETE_FEATURES.md) - Comprehensive list of all implemented features
- [STABILITY_AND_COEFFICIENTS.md](STABILITY_AND_COEFFICIENTS.md) - Stability analysis and form coefficient calculations
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Technical implementation details

## Module Overview

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `Hydrostatics.jl` | Core hydrostatic calculations | `calculate_hydrostatics`, `calculate_hydrostatics_from_file` |
| `STLReader.jl` | STL file parsing | `read_stl`, `extract_offsets_from_stl` |
| `StabilityAnalysis.jl` | Stability analysis | `calculate_stability_properties`, `calculate_gz_curve` |
| `FormCoefficients.jl` | Form coefficients | `calculate_form_coefficients` |

## Quick Links

- [Main README](../README.md) - Project overview and quick start
- [Examples](../examples/) - Working code examples
- [Tests](../tests/) - Test suite

## Coordinate System

All modules use the following coordinate system:
- **x**: Longitudinal (bow to stern, positive aft)
- **y**: Transverse (half-breadth, positive to port/starboard)
- **z**: Vertical (absolute z-coordinate from STL file, or relative depth)

## Support

For questions or issues, please open an issue on the GitHub repository.
