# Don't Look Human performance baseline

> Machine-specific advisory snapshot. FPS thresholds do not block release; runtime errors and structural budgets do.

- Generated (UTC): `2026-08-15 19:33:22`
- OS: `Windows`
- CPU: `12th Gen Intel(R) Core(TM) i7-12700KF` (20 logical processors)
- GPU: `NVIDIA GeForce RTX 5060`
- Display: `200.0 Hz`, VSync mode `0`, engine FPS cap `0`
- Renderer: `forward_plus / d3d12`
- Configuration: `1280x720`, `Medium`, reduced motion `false`, 2.0s warm-up + 5.0s sample per level

| Level | Avg FPS | 1% low FPS | Median frame ms | P95 frame ms | Max process ms | Max draw calls | Max nodes | Structural |
|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| Community Park | 200.0 | 170.9 | 5.00 | 5.76 | 5.29 | 220 | 637 | PASS |
| Playground | 200.0 | 163.4 | 5.01 | 5.96 | 5.42 | 270 | 788 | PASS |
| Lakeside | 200.0 | 168.6 | 5.01 | 5.82 | 5.33 | 290 | 609 | PASS |
| Festival | 200.0 | 162.8 | 5.01 | 6.05 | 5.42 | 400 | 809 | PASS |
| Botanical Gardens | 200.0 | 175.0 | 5.01 | 5.65 | 5.54 | 237 | 500 | PASS |

Advisory targets: average FPS >= 60 and frame-time-derived 1% low FPS >= 45.

Raw monitor distributions and every structural budget are available in `performance_baseline.json`.
