# Quick Start: Julia Hydrostatics

## Running the Demos

### 1. Standalone Demo (No Python Required)

```bash
julia examples/hydrostatics_demo.jl
```

This generates a synthetic ship hull and calculates hydrostatic properties.

### 2. Multi-Input Demo (Offsets + STL)

```bash
julia examples/hydrostatics_multi_input.jl
```

This demonstrates all input methods: direct offsets, STL files, and type-safe interfaces.

### 3. With Ship-D Data (Requires PyCall)

```bash
# First, set up PyCall to use your Python environment
julia -e 'using Pkg; Pkg.add("PyCall")'
julia -e 'ENV["PYTHON"] = "/path/to/python"; using Pkg; Pkg.build("PyCall")'

# Then run the demo
julia examples/hydrostatics_with_shipd.jl
```

This loads real Ship-D hull parameters and compares Julia vs Python calculations.

## Basic Usage in Your Code

### Option A: From STL File (Easiest)

```julia
# Load the module
include("/path/to/ShipD/Hydrostatics.jl")
using .Hydrostatics

# Calculate from STL file (auto-detects format)
results = calculate_hydrostatics_from_file("hull.stl")

# Access properties
props = results[end]  # At design draft
println("Volume: $(props.volume) m³")
println("LCB: $(props.lcb) m")
println("Waterplane area: $(props.waterplane_area) m²")
```

### Option B: From Offset Table

```julia
# Load the module
include("/path/to/ShipD/Hydrostatics.jl")
using .Hydrostatics

# Prepare your offset data
# x: longitudinal stations (bow to stern)
# z: vertical positions (negative below waterline)
# y_offsets[i,j]: half-breadth at station i, waterline j

x = [0.0, 2.5, 5.0, 7.5, 10.0]
z = [-1.0, -0.5, 0.0]
y_offsets = [
    0.0  0.2  0.4;   # Bow
    0.8  1.0  1.2;   # Midship
    0.8  1.0  1.2;
    0.8  1.0  1.2;
    0.0  0.3  0.5    # Stern
]

# Calculate hydrostatics
results = calculate_hydrostatics(x, y_offsets, z)

# Access properties
props = results[end]  # At design draft
println("Volume: $(props.volume) m³")
println("LCB: $(props.lcb) m")
println("Waterplane area: $(props.waterplane_area) m²")
```

## Using with Ship-D Hull Parameters

```julia
include("/path/to/ShipD/Hydrostatics.jl")
include("/path/to/ShipD/ShipDPy2Jl.jl")
using .Hydrostatics, .ShipDPy2Jl

# Load hull parameter vector (45 parameters)
vectors = load_hull_vectors("Input_Vectors_SampleHulls.csv")
params = vectors[1, :]

# Generate offsets
offsets = generate_offsets_for_hydrostatics(params)

# Calculate hydrostatics
results = calculate_hydrostatics(
    offsets.x,
    offsets.y_offsets,
    offsets.z
)

# Display results
for props in results
    println("Draft: $(props.draft), Volume: $(props.volume)")
end
```

## Calculated Properties

Each `HydrostaticProperties` struct contains:

- `volume` - Displaced volume (m³)
- `waterplane_area` - Waterplane area (m²)
- `lcb` - Longitudinal center of buoyancy (m)
- `vcb` - Vertical center of buoyancy (m, from waterline)
- `lcf` - Longitudinal center of flotation (m)
- `ixx` - Second moment about longitudinal axis (m⁴)
- `iyy` - Second moment about transverse axis (m⁴)
- `wetted_surface` - Wetted surface area (m²)
- `waterline_length` - Waterline length (m)

## Files Created

```
ShipD/
├── Hydrostatics.jl                    # Main hydrostatics module
├── ShipDPy2Jl.jl                      # Python-Julia interface
├── test_hydrostatics.jl               # Basic tests
├── HYDROSTATICS_README.md             # Full documentation
├── QUICK_START_HYDROSTATICS.md        # This file
└── examples/
    ├── hydrostatics_demo.jl           # Standalone demo
    └── hydrostatics_with_shipd.jl     # Full Ship-D integration
```

## Performance

Julia is ~2-5× faster than Python for these calculations:
- Single hull: ~10-50 ms (51 stations × 11 waterlines)
- Batch processing: ~2-5 seconds for 100 hulls (after JIT warmup)

## Next Steps

See `HYDROSTATICS_README.md` for:
- Complete API reference
- Detailed examples
- Validation results
- Troubleshooting
- Future enhancements (AD support, stability analysis, etc.)
