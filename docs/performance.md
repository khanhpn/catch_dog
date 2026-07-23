# Performance and platform verification

## Targets

The vertical-slice target is 60 FPS at 1080p on the Medium preset. The Low preset must remain at or above 30 FPS on the target AMD-GPU Mac. Windows x86_64 is also a release platform.

These are acceptance targets, not recorded measurements. No physical Windows or AMD-GPU Mac performance result is asserted by this repository until the release owner captures and records it.

## Current controls

- Godot 4.6.3 with the Forward+ renderer; Godot's OpenGL fallback remains enabled.
- Configured viewport: 1280×720; physics tick rate: 60 Hz.
- Graphics presets: Low disables glow/fog and reduces directional shadow distance; Medium and High retain the longer shadow distance.
- Gameplay uses authored navigation and bounded dynamic populations. Replay removes dynamic dogs, pickups, guards, and projectiles before restoring the session.

These controls reduce obvious cost and lifecycle pressure, but they are not a substitute for profiling an exported build.

## Release-owner measurement procedure

For each physical target device—one Windows x86_64 system and the target Intel/AMD-GPU Mac—run the signed candidate where applicable and record:

1. OS/device model, CPU, GPU, memory, display resolution, driver/OS version, build version, and Godot 4.6.3 export provenance.
2. Preset, resolution, fullscreen state, and test duration.
3. Frame-time statistics at 1080p: average FPS plus 1% low (or an equivalent documented frame-time percentile).
4. At least one busy gameplay loop with dogs, nets, fuel pickups, and active guard pursuit; include menu, pause/replay, and result transitions.
5. Visual defects, hitches, navigation failures, input responsiveness, thermal throttling, and crashes.

Accept Medium only when it meets the 60 FPS target at 1080p on the agreed target system. Accept Low on the AMD-GPU Mac only when it meets the 30 FPS target. Do not turn missing measurements into a pass; attach the results to the release record and leave the gate open when a target device is unavailable.

## Profiling approach

Use Godot's profiler/monitoring tools and a release-like exported build. Compare idle driving with the busy loop above, then investigate the dominant cost before changing quality settings. Keep gameplay readability intact: the target lock, HUD, guard warnings, and collision/navigation behavior must survive a lower preset.

When a regression is found, record the reproducer, preset, scene, metric, and before/after result. Avoid claiming a universal gain from editor-only or headless timing.
