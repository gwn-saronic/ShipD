# STL File Support for Hydrostatics

The Julia hydrostatics module now supports STL file input in addition to offset tables.

## Quick Examples

### Method 1: Direct STL File (Simplest)

```julia
include("Hydrostatics.jl")
using .Hydrostatics

# Automatic format detection from file extension
results = calculate_hydrostatics_from_file("hull.stl")

# Access results
props = results[end]
println("Volume: $(props.volume) m³")
```

### Method 2: Explicit STL Processing

```julia
# Specify STL format explicitly with custom parameters
results = calculate_hydrostatics_from_file(
    "hull.stl",
    input_type=:stl,
    n_stations=51,      # Number of longitudinal stations
    n_waterlines=11,    # Number of vertical waterlines
    draft=0.885         # Optional: specify draft (uses full depth if omitted)
)
```

### Method 3: Using Type-Safe Interface

```julia
using .Hydrostatics: STLInput

# Create input object
input = STLInput("hull.stl", 51, 11, nothing)

# Calculate
results = calculate_hydrostatics(input)
```

### Method 4: Direct Offset Input (Original Method)

```julia
# If you already have offset tables
x = [0.0, 2.5, 5.0, 7.5, 10.0]
z = [-1.0, -0.5, 0.0]
y_offsets = [...]  # Half-breadth matrix [x_idx, z_idx]

results = calculate_hydrostatics(x, y_offsets, z)
```

## How STL Processing Works

1. **Read STL File**: Supports both ASCII and binary STL formats (auto-detected)
2. **Extract Waterlines**: Intersects mesh with horizontal planes at specified z-heights
3. **Create Offset Table**: Converts waterline intersections to structured offset data
4. **Calculate Hydrostatics**: Uses standard naval architecture formulas

## Parameters

### `n_stations` (default: 51)
Number of longitudinal stations (must be odd for compatibility with Michell integral).
- More stations = higher accuracy but slower computation
- Recommended: 51-101 for typical hulls

### `n_waterlines` (default: 11)
Number of vertical waterlines from keel to design waterline.
- More waterlines = more detailed hydrostatic curves
- Recommended: 11-21 for typical analysis

### `draft` (default: nothing)
Draft to use for calculations:
- `nothing`: Uses full height of mesh (from z_min to z_max)
- `Float64`: Specific draft value (mesh is clipped at z_max - draft)

## Performance

Processing the sample hull (228,384 triangles):
- STL reading: ~100-200 ms
- Waterline extraction: ~500-1000 ms
- Hydrostatics calculation: ~10-50 ms
- **Total: ~1-2 seconds**

Performance scales roughly linearly with number of triangles.

## STL File Requirements

### Coordinate System
The STL file should use:
- **X-axis**: Longitudinal (bow to stern)
- **Y-axis**: Transverse (port to starboard)
- **Z-axis**: Vertical (keel to deck)

### Hull Orientation
- Centerline should be at Y = 0
- Only half the hull is needed (port or starboard)
- Full hull works too (will use absolute Y values)

### Mesh Quality
- Watertight mesh recommended but not required
- Closed surfaces give more accurate results
- Open meshes work but may have edge effects

## Validation

Results from the sample Ship-D hull (sample_Hull_Mesh.stl):

```
Volume:          10.41 m³
Waterplane area: 15.09 m²
LCB:             5.18 m
VCB:             -0.39 m (from waterline)
Wetted surface:  28.08 m²
```

These values are consistent with the original Ship-D hull parameters.

## Comparison: Offsets vs STL

| Feature | Offset Input | STL Input |
|---------|--------------|-----------|
| Setup | Manual calculation | Automatic extraction |
| Accuracy | Depends on table | Depends on mesh quality |
| Speed | Fastest (~10-50 ms) | Slower (~1-2 sec) |
| Flexibility | Full control | Limited by mesh |
| Ease of use | Requires offsets | Works with any STL |

**Recommendation**: Use STL input for quick analysis and validation. Use offset input for production code where performance matters.

## Troubleshooting

### "STL support not available"
Make sure `STLReader.jl` is in the same directory as `Hydrostatics.jl`.

### "Cannot auto-detect input type"
Specify `input_type=:stl` explicitly:
```julia
calculate_hydrostatics_from_file("file.dat", input_type=:stl)
```

### Incorrect results
Check:
1. STL coordinate system matches expectations (X=longitudinal, Z=vertical)
2. Mesh is at correct scale (not in mm when expecting meters)
3. Centerline is at Y=0
4. Draft parameter is set correctly

### Slow performance
For large meshes (>500k triangles):
1. Reduce `n_stations` (try 31 or 41)
2. Reduce `n_waterlines` (try 7 or 9)
3. Consider decimating the mesh first

## Complete Example Script

```julia
#!/usr/bin/env julia

include("Hydrostatics.jl")
using .Hydrostatics
using Printf

# Load STL and calculate hydrostatics
results = calculate_hydrostatics_from_file(
    "hull.stl",
    n_stations=51,
    n_waterlines=11
)

# Display results at each draft
println("Hydrostatic Curves:")
println("="^60)
for (i, props) in enumerate(results)
    @printf("Draft %2d: T=%.3f  V=%.2f m³  Awp=%.2f m²\n",
            i, props.draft, props.volume, props.waterplane_area)
end

# Design draft details
println("\n" * "="^60)
println("Properties at Design Draft:")
println("="^60)
props = results[end]
@printf("Volume:              %10.4f m³\n", props.volume)
@printf("Waterplane Area:     %10.4f m²\n", props.waterplane_area)
@printf("LCB:                 %10.4f m\n", props.lcb)
@printf("VCB:                 %10.4f m\n", props.vcb)
@printf("LCF:                 %10.4f m\n", props.lcf)
@printf("Wetted Surface:      %10.4f m²\n", props.wetted_surface)
@printf("Waterline Length:    %10.4f m\n", props.waterline_length)
```

## Integration with Ship-D

STL files can be generated from Ship-D hull parameters:

```python
from shipd import Hull_Parameterization as HP
import numpy as np

# Load hull parameters
params = np.loadtxt('Input_Vectors_SampleHulls.csv', delimiter=',')[0]
hull = HP(params)

# Generate STL mesh
hull.gen_stl(NUM_WL=100, PointsPerWL=800, namepath='./my_hull')
```

Then use in Julia:

```julia
results = calculate_hydrostatics_from_file("my_hull.stl")
```

## Future Enhancements

Planned features:
- [ ] IGES/STEP file support
- [ ] CSV offset table import
- [ ] Parallel processing for large meshes
- [ ] Adaptive waterline spacing
- [ ] Direct mesh quality checking
- [ ] Export waterlines to CSV

---

**See also**: `examples/hydrostatics_multi_input.jl` for complete demonstrations
