# Level Balance Targets

These targets describe the intended difficulty curve after the Phase 5 balance pass. Route estimates come from the shortest flat route through all five collectibles and the exit. They include a movement/interaction allowance, but they do not model collision detours, waiting for patrols, or water slowdown. Real playtest results should replace the estimates over time.

| Level | Timer | Grade thresholds | Route | First-attempt target | Experienced target | Rangers | Pigeons | Visitors | Intended pressure |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Park | 85s | 40 / 55 / 75s | 47.5m | 60–75s | 35–45s | 2 | 13 | 8 | Tutorial: readable patrols and abundant blending cover |
| Playground | 80s | 42 / 55 / 72s | 51.1m | 65–80s | 38–50s | 3 | 15 | 16 | Crowds and blocked sightlines with moderate detection pressure |
| Lakeside | 75s | 35 / 48 / 65s | 41.2m | 60–75s | 35–50s | 3 | 9 | 10 | Route choice, exposed food, slower recovery, and water slowdown |
| Festival | 85s | 48 / 65 / 80s | 57.8m | 75–85s | 45–60s | 3 | 12 | 22 | Longest route and densest moving crowd |
| Botanical Gardens | 65s | 32 / 45 / 58s | 35.4m | 55–65s | 35–50s | 4 | 6 | 7 | Short route offset by limited cover and consistent four-ranger pressure |

## Difficulty progression

- Park uses lower suspicion gain, faster recovery, and higher thresholds than later levels. The player starts outside both notice radii.
- Playground introduces three moderately alert rangers, but its large pigeon and visitor population supplies frequent cover.
- Lakeside increases detection and reduces suspicion recovery while placing three collectibles inside initial ranger coverage. Water adds route risk.
- Festival's rangers now react comparably to the middle levels. Its dense crowd provides cover while its timer accounts for the longest route.
- Botanical Gardens has the fewest pigeons, four consistently alert rangers, slower recovery, and four initially exposed collectibles. Its nearest ranger still does not detect the player at spawn.

## Automated balance constraints

The Phase 5 validation checks that:

- Every level contains five collectibles.
- Every player spawn begins outside every ranger's base notice radius.
- The timer leaves at least ten seconds beyond the modeled experienced route.
- Procedurally spawned pigeons and visitors stay within the playable park.
- A route-pressure index increases across all five levels, combining route length with ranger count, notice distance, active suspicion gain, and recovery.
- The measured route, NPC population, ranger exposure, and nearby pigeon cover are printed for comparison.

Run the measurement with:

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/phase5_balance_validation.gd
```

## Manual playtest notes

For each run, record the level, completion time, result, where suspicion first reached Investigate and Chase, and whether the final catch explanation matched the behavior that caused it. Adjust one lever at a time: timer, ranger notice distance, suspicion rates, NPC count, or a single spawn position.
