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
- Optimized for minimal tick overhead (~20-30% improvement)
- Fully compatible with Stormworks API restrictions

**Documentation:**
- [FIRE_CONTROL_OPTIMIZATION.md](FIRE_CONTROL_OPTIMIZATION.md) - Performance analysis and optimization techniques
- [STORMWORKS_API_COMPATIBILITY.md](STORMWORKS_API_COMPATIBILITY.md) - API compatibility guide and best practices
- [USAGE_GUIDE.md](USAGE_GUIDE.md) - Complete usage guide
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Quick integration reference