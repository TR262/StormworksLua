# StormworksLua

### Map.lua

Draws the map with radar sweep animation and current heading indicator

### Radar.lua

Draws radar contacts as little red dots

### FireControlRadar.lua

Advanced fire control radar system with predictive target tracking, 3D coordinate transformation, and optimized tick performance. Features:

- Tracks up to 8 simultaneous targets with Kalman-like filtering
- Predictive velocity estimation for lead calculation
- Dual mode operation: automatic closest-target tracking or manual free mode
- Real-time HUD with target position, velocity vector, and telemetry
- Optimized for minimal tick overhead with cached functions and pre-calculated values

See [FIRE_CONTROL_OPTIMIZATION.md](FIRE_CONTROL_OPTIMIZATION.md) for detailed performance analysis and optimization techniques.