# Range Indicator Technical Documentation

## Overview
The fire control radar includes a small circular range indicator in the bottom-right corner of the display. This indicator shows the relative positions of detected targets compared to the currently tracked target.

## Display Geometry

### Coordinate System
The range indicator uses a polar coordinate projection where:
- **Azimuth (horizontal angle)** controls the X position via `sin(azimuth)`
- **Elevation (vertical angle)** controls the Y position via `cos(elevation)`

This creates a 2D projection of 3D space suitable for a heads-up radar display.

### Indicator Components

1. **Arc Lines** (Green, 0, 50, 0)
   - Two lines at ±21.6° (0.03 × 2π radians)
   - Represent the field of view edges
   - Length: 29 pixels from center

2. **Target Markers** (Yellow, 255, 255, 0)
   - Each detected target shown as a 1×1 pixel
   - Position calculated as:
     ```lua
     X = center_x + 28 × distance_ratio × sin(azimuth)
     Y = center_y - 28 × distance_ratio × cos(elevation)
     ```
   - `distance_ratio = target_distance / tracked_target_distance`
   - Only shown if ratio ≤ 1.05 (within ~5% of tracked distance)

## Why This Coordinate Mapping?

### Azimuth → X via sin()
In polar coordinates, azimuth represents rotation around the vertical axis:
- 0° azimuth = forward (top of display)
- 90° azimuth = right
- -90° azimuth = left

Using `sin(azimuth)`:
- sin(0°) = 0 → center
- sin(90°) = 1 → right edge
- sin(-90°) = -1 → left edge

This correctly maps horizontal angle to horizontal position.

### Elevation → Y via cos()
Elevation represents angle above/below the horizon:
- 0° elevation = horizon (center)
- 90° elevation = straight up
- -90° elevation = straight down

Using `-cos(elevation)` (negative because Y increases downward in screen coordinates):
- -cos(0°) = -1 → center (horizon)
- -cos(90°) = 0 → top edge (up)
- -cos(-90°) = 0 → bottom edge (down)

This correctly maps vertical angle to vertical position.

## Example Scenarios

### Scenario 1: Target at same altitude, 30° right
- Azimuth: 30° → sin(30°) = 0.5 → marker at +50% horizontal
- Elevation: 0° → cos(0°) = 1 → marker at horizon line
- **Result:** Marker appears to the right at center height

### Scenario 2: Target 45° above horizon, straight ahead
- Azimuth: 0° → sin(0°) = 0 → marker at center horizontal
- Elevation: 45° → cos(45°) = 0.707 → marker at 70.7% up
- **Result:** Marker appears above center

### Scenario 3: Target at same range, 20° left and 15° below
- Azimuth: -20° → sin(-20°) = -0.342 → marker at -34% horizontal
- Elevation: -15° → cos(-15°) = 0.966 → marker slightly below center
- **Result:** Marker appears to the left and slightly down

## Distance Ratio Filtering

The `ratio ≤ 1.05` check ensures only targets within roughly the same distance band as the tracked target are shown. This:
- Prevents cluttering the display with targets at very different ranges
- Focuses attention on threats at similar distances
- Maintains the circular indicator's geometric accuracy (far targets would project beyond the circle)

## Code Reference

Original obfuscated code:
```lua
if M[_][1] <= 1.05 then
    ad(n - 6 + 28 * M[_][1] * am(M[_][2]),
       c - 1 - 28 * M[_][1] * ao(M[_][3]),
       1,1)
end
```

Optimized code:
```lua
local ratio = distance / base_distance
if ratio <= 1.05 then
    local marker_x = width - 6 + 28 * ratio * math_sin(azimuth)
    local marker_y = height - 1 - 28 * ratio * math_cos(elevation)
    screen_drawRectF(marker_x, marker_y, 1, 1)
end
```

Both implementations are functionally identical, with the optimized version using clearer variable names and pre-cached math functions.
