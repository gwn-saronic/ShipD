# Hydrostatics Input Methods

The Julia hydrostatics module supports multiple input methods to accommodate different workflows.

## Summary Table

| Input Method | Use Case | Setup Required | Speed | Flexibility |
|--------------|----------|----------------|-------|-------------|
| **STL File** | Quick analysis from 3D models | None | Medium (~1-2s) | Limited by mesh |
| **Offset Table** | Production code, precise control | Manual or Python | Fast (~10-50ms) | Full control |
| **Ship-D Parameters** | Working with Ship-D dataset | PyCall | Medium (~100-200ms) | Ship-D hulls only |
| **Type-Safe Interface** | Large codebases, type checking | None | Same as above | Abstraction layer |

## Input Methods

### 1. STL File Input ⭐ Recommended for Quick Analysis

**Best for**: Quick analysis, visualization, validation

```julia
include("Hydrostatics.jl")
using .Hydrostatics

# Simplest method - automatic format detection
results = calculate_hydrostatics_from_file("hull.stl")

# With custom parameters
results = calculate_hydrostatics_from_file(
    "hull.stl",
    input_type=:stl,
    n_stations=51,
    n_waterlines=11,
    draft=0.885  # Optional
)
```

**Pros**:
- ✅ Works with any 3D hull model
- ✅ No manual offset calculation needed
- ✅ Automatic waterline extraction
- ✅ Supports both ASCII and binary STL

**Cons**:
- ❌ Slower than direct offsets (~1-2 seconds vs ~10-50 ms)
- ❌ Accuracy depends on mesh quality
- ❌ Limited control over offset distribution

**Requirements**:
- STL file with hull mesh
- Coordinate system: X=longitudinal, Y=transverse, Z=vertical
- Centerline at Y=0 (or use absolute Y values)

---

### 2. Direct Offset Table Input ⭐ Recommended for Production

**Best for**: Production code, batch processing, maximum control

```julia
include("Hydrostatics.jl")
using .Hydrostatics

# Define offset table
x = [0.0, 2.5, 5.0, 7.5, 10.0]  # Longitudinal stations
z = [-1.0, -0.5, 0.0]            # Vertical positions
y_offsets = [                     # Half-breadth offsets [x_idx, z_idx]
    0.0  0.2  0.4;   # Station 1 (bow)
    0.8  1.0  1.2;   # Station 2
    0.8  1.0  1.2;   # Station 3
    0.8  1.0  1.2;   # Station 4
    0.0  0.3  0.5    # Station 5 (stern)
]

# Calculate
results = calculate_hydrostatics(x, y_offsets, z)
```

**Pros**:
- ✅ Fastest method (~10-50 ms)
- ✅ Full control over offset distribution
- ✅ Precise, no discretization errors
- ✅ Minimal dependencies

**Cons**:
- ❌ Requires pre-computed offsets
- ❌ More setup work

**Requirements**:
- Offset table in correct format
- x: Vector of longitudinal positions
- z: Vector of vertical positions (sorted ascending, negative below waterline)
- y_offsets: Matrix [x_idx, z_idx] of half-breadths

---

### 3. Ship-D Parameter Input ⭐ Recommended for Ship-D Users

**Best for**: Working with Ship-D hull parameter vectors

```julia
include("Hydrostatics.jl")
include("ShipDPy2Jl.jl")
using .Hydrostatics, .ShipDPy2Jl

# Load hull parameters (45-parameter vector)
vectors = load_hull_vectors("Input_Vectors_SampleHulls.csv")
params = vectors[1, :]

# Generate offsets via Python interface
offsets = generate_offsets_for_hydrostatics(
    params,
    draft_fraction=1.0,
    num_stations=51
)

# Calculate hydrostatics
results = calculate_hydrostatics(
    offsets.x,
    offsets.y_offsets,
    offsets.z
)
```

**Pros**:
- ✅ Direct integration with Ship-D dataset
- ✅ Access to 30,000+ parametric hulls
- ✅ Consistent with Python Ship-D code
- ✅ Can validate/compare with Python

**Cons**:
- ❌ Requires PyCall setup
- ❌ Python dependency
- ❌ Limited to Ship-D parameterization

**Requirements**:
- PyCall configured
- Ship-D Python package installed
- Ship-D hull parameter vectors

---

### 4. Type-Safe Interface

**Best for**: Large codebases, type safety, abstraction

```julia
include("Hydrostatics.jl")
using .Hydrostatics
using .Hydrostatics: OffsetInput, STLInput

# Option A: OffsetInput
input = OffsetInput(x, y_offsets, z)
results = calculate_hydrostatics(input)

# Option B: STLInput
input = STLInput("hull.stl", 51, 11, nothing)
results = calculate_hydrostatics(input)
```

**Pros**:
- ✅ Type checking at compile time
- ✅ Clean abstraction
- ✅ Easy to extend
- ✅ Polymorphic dispatch

**Cons**:
- ❌ Slightly more verbose
- ❌ No performance benefit

**Requirements**:
- Same as underlying input method

---

## Choosing an Input Method

### Quick Decision Tree

```
Do you have an STL file?
├─ YES → Use STL File Input (Method 1)
│         Fast setup, good for one-off analysis
└─ NO
   │
   Do you have Ship-D parameters?
   ├─ YES → Use Ship-D Parameter Input (Method 3)
   │         Best integration with Ship-D
   └─ NO
      │
      Do you have offset tables?
      ├─ YES → Use Direct Offset Input (Method 2)
      │         Fastest, best for production
      └─ NO → Generate offsets manually or from CAD
                Then use Method 2
```

### By Use Case

| Use Case | Recommended Method |
|----------|-------------------|
| One-off hull analysis | STL File (1) |
| Batch processing 100+ hulls | Direct Offset (2) |
| Ship-D dataset work | Ship-D Parameters (3) |
| Prototyping / validation | STL File (1) |
| Production optimization | Direct Offset (2) |
| Type-safe large codebase | Type-Safe Interface (4) |
| Real-time calculations | Direct Offset (2) |
| Working from CAD models | STL File (1) |

---

## Performance Comparison

Tested on Apple M-series laptop with sample Ship-D hull:

| Method | Time | Notes |
|--------|------|-------|
| Direct Offset | 10-50 ms | 51 stations × 11 waterlines |
| STL File | 1-2 sec | 228k triangles → offsets → hydrostatics |
| Ship-D Params | 100-200 ms | Python interface overhead (first call) |
| Type-Safe | +0 ms | Same as underlying method |

**Speedup factors**:
- Direct Offset vs STL: **20-40× faster**
- Direct Offset vs Ship-D: **2-4× faster**

**Memory usage**:
- Direct Offset: ~1 MB
- STL File: ~50-100 MB (depends on mesh size)
- Ship-D Params: ~10 MB (Python overhead)

---

## Code Examples

See `examples/` directory:
- `hydrostatics_demo.jl` - Standalone demo with synthetic hull
- `hydrostatics_multi_input.jl` - All input methods demonstrated
- `hydrostatics_with_shipd.jl` - Ship-D integration

---

## Conversion Between Formats

### STL → Offsets

```julia
using .Hydrostatics

# Extract offsets from STL
include("STLReader.jl")
using .STLReader

x, y_offsets, z = extract_offsets_from_stl(
    "hull.stl",
    n_stations=51,
    n_waterlines=11
)

# Save offsets for later use (example)
# using DelimitedFiles
# writedlm("offsets_x.csv", x, ',')
# writedlm("offsets_z.csv", z, ',')
# writedlm("offsets_y.csv", y_offsets, ',')
```

### Ship-D Params → STL → Offsets

```python
# Python: Generate STL from Ship-D parameters
from shipd import Hull_Parameterization as HP
import numpy as np

params = np.loadtxt('Input_Vectors_SampleHulls.csv', delimiter=',')[0]
hull = HP(params)
hull.gen_stl(NUM_WL=100, PointsPerWL=800, namepath='./hull')
```

```julia
# Julia: Load STL and extract offsets
results = calculate_hydrostatics_from_file("hull.stl")
```

### Ship-D Params → Offsets (Direct)

```julia
using .ShipDPy2Jl

# Direct offset generation via Python
offsets = generate_offsets_for_hydrostatics(params)
x, y_offsets, z = offsets.x, offsets.y_offsets, offsets.z
```

---

## Input Format Specifications

### Offset Table Format

```
x: Vector{Float64} of length N
   Longitudinal positions from bow to stern
   Example: [0.0, 2.5, 5.0, 7.5, 10.0]

z: Vector{Float64} of length M
   Vertical positions from keel to waterline
   Must be sorted ascending
   Negative below waterline, 0 at waterline
   Example: [-1.0, -0.5, 0.0]

y_offsets: Matrix{Float64} of size N × M
   Half-breadth at each (x, z) point
   Indexed as y_offsets[x_idx, z_idx]
   Example: [0.0 0.2 0.4;
             0.8 1.0 1.2;
             ...]
```

### STL File Format

```
- Format: ASCII or Binary STL (auto-detected)
- Coordinate system:
  - X: Longitudinal (bow to stern)
  - Y: Transverse (port/starboard)
  - Z: Vertical (keel to deck)
- Requirements:
  - Centerline at Y=0 (or absolute Y values used)
  - Single hull (half or full)
  - Units: Consistent (meters recommended)
```

### Ship-D Parameter Format

```
- Format: 45-element Float64 vector
- Source: Input_Vectors_SampleHulls.csv or InputVectors_30k.npy
- Elements: [LOA, Lb, Ls, Bd, Dd, Bs, WL, Bc, Beta, ...]
- See Ship-D documentation for complete parameter list
```

---

## Troubleshooting

### "Package Hydrostatics not found"
Use `include("Hydrostatics.jl")` and `using .Hydrostatics` instead of just `using Hydrostatics`

### "STL support not available"
Ensure `STLReader.jl` is in the same directory as `Hydrostatics.jl`

### Dimension mismatch errors
Check that `size(y_offsets) == (length(x), length(z))`

### Ship-D import errors
Configure PyCall: `ENV["PYTHON"] = "/path/to/python"; using Pkg; Pkg.build("PyCall")`

---

**See also**:
- `STL_SUPPORT.md` - Detailed STL documentation
- `HYDROSTATICS_README.md` - Complete API reference
- `QUICK_START_HYDROSTATICS.md` - Quick start guide
