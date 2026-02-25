# Junk-Punk Titan: Implementation Strategy

## Current State: ~35-40% Complete

The core loop skeleton exists (role selection, building placement, wave spawning, storms), but ~60% of the GDD is missing, broken, or incorrectly implemented. This document tracks our phased plan to bring the game to full spec.

---

## Phase 1: Foundation Fixes (Security, Architecture, Critical Bugs)

No new features — stop the bleeding. Fix what's actively broken or exploitable.

- [ ] **1.1** Delete the `RequestPurchase` remote backdoor in `EconomyService` (client-provided `currentCount` bypasses exponential scaling)
- [ ] **1.2** Lock roles after first selection — prevent re-firing `RoleSelected` to switch roles mid-session
- [ ] **1.3** Add input validation and rate limiting — create a shared `RemoteGuard` utility for throttling + type-checking all remotes
- [ ] **1.4** Fix `AddScrap` / `AddStormSteel` to reject negative values
- [ ] **1.5** Fix `builtCounts` to decrement on building destruction (currently only increments, so replacement costs escalate unfairly)
- [ ] **1.6** Replace all `Parent = nil` with `:Destroy()` (prevents memory leaks from orphaned connections)
- [ ] **1.7** Wrap all `Init()` calls in `pcall` with error logging
- [ ] **1.8** Centralize `peakPlayerCount` into a single `PlayerTrackingService` — delete the 4 duplicated copies across EnemyService, ResourceService, RoleService, StormService
- [ ] **1.9** Extract shared utilities into `Shared/Utils.luau` — `snapToGrid`, `createScrapBundle`, `removeToolByName`
- [ ] **1.10** Fix blueprint cleanup — add player disconnect handler to destroy orphaned ghost blueprints
- [ ] **1.11** Add server-side overlap validation for building placement
- [ ] **1.12** Add pending repair timeout in `ResourceService` (10s server-side fallback)

---

## Phase 2: Core Mechanics Completion (Combat, Economy, Enemies)

The game loop is fundamentally incomplete without these.

- [ ] **2.1** Implement rat HP system — give rats actual health, turrets deal damage per shot, shotgun deals damage with role multiplier
- [ ] **2.2** Fix turret balance — damage per shot + fire rate so rats survive multiple hits
- [ ] **2.3** Implement scrap bundle pickup — add `.Touched` handler + 30s despawn timer to all scrap bundles
- [ ] **2.4** Differentiate standard kill vs. thief kill rewards — standard = 2-5 scrap, thief = 50% of stolen building cost
- [ ] **2.5** Fix enemy targeting — distribute rats across multiple buildings instead of all piling on one
- [ ] **2.6** Hook up `GetDifficultyMultiplier()` — actually use it in `SpawnWave` for player-count scaling
- [ ] **2.7** Correct Constants to match GDD — Turret base cost 100, Drill 250, rat reward 2-5, shotgun range shortened
- [ ] **2.8** Implement loose scrap spawns — periodic map-wide scrap pile generation for Scrappers
- [ ] **2.9** Fix storm steel timing — spawn during storm (not after), despawn when storm ends
- [ ] **2.10** Fix storm wind damage — separate damage system (not `DismantleProgress`), don't reward players for wind destruction
- [ ] **2.11** Add death penalty cooldown — per-player 10s cooldown on scrap tax
- [ ] **2.12** Implement tool restrictions — Enforcer can't use Wrench, non-Enforcer can't effectively use Shotgun

---

## Phase 3: The Win Condition (Titan Stages, Finale, Victory)

Without this, the game cannot be completed.

- [ ] **3.1** Design stage cost table — define Scrap + Steel costs for stages 1-4 in `Constants.luau`
- [ ] **3.2** Create Titan deposit interaction — proximity prompt at Titan Core, hold E to deposit resources
- [ ] **3.3** Wire up `ObjectiveService.CompleteStage` — trigger when deposit thresholds are met
- [ ] **3.4** Add Titan visual updates — change Titan appearance on each stage completion
- [ ] **3.5** Add Titan progress UI — top-right HUD showing integrity bar + stage requirements
- [ ] **3.6** Implement the 99% Final Stand — permanent storm, infinite elite swarm, hidden 3-5 min timer
- [ ] **3.7** Implement Victory state — shockwave VFX, all enemies vaporized, VICTORY screen
- [ ] **3.8** Add session statistics tracking — scrap gathered, rats killed, buildings lost, display on victory/defeat

---

## Phase 4: Audio & Visual Polish ("Juice")

This makes the game feel good.

- [ ] **4.1** Create centralized `AudioManifest.luau` — all sound IDs in one place
- [ ] **4.2** Add shotgun fire sound — positional 3D audio
- [ ] **4.3** Add building placement sounds — construction clank
- [ ] **4.4** Add enemy sounds — spawn burrow, movement skitter, dismantle scraping, death squeal
- [ ] **4.5** Add UI sounds — button clicks, role selection, minigame hit/miss
- [ ] **4.6** Add ambient music system — background track, intensity shifts during waves
- [ ] **4.7** Add wave siren at 00:00 — low-frequency horn per GDD spec
- [ ] **4.8** Fix camera shake — use CFrame offset instead of tweening `CurrentCamera.CFrame` directly
- [ ] **4.9** Add missing VFX — enemy death particles, building destruction, overclock glow, clog smoke
- [ ] **4.10** Fix loot fountain — parallelize gear spawns, add magnetic snap-to-player

---

## Phase 5: UI, UX, and Quality of Life

This makes the game playable by real humans.

- [ ] **5.1** Split `MainHUD.luau` (893 lines) into focused modules — `RoleSelectionUI`, `BuildToolbar`, `RepairMinigame`, `WaveTimerUI`, `GameOverUI`, `DismantleBarManager`
- [ ] **5.2** Convert to responsive layout — replace all `fromOffset` with `fromScale` or adaptive `UDim2`
- [ ] **5.3** Add role descriptions to selection screen — explain what each role does, not just raw multipliers
- [ ] **5.4** Add Fixer-specific strobing yellow border on dismantle bars (GDD spec)
- [ ] **5.5** Add settings menu — volume sliders, keybind display
- [ ] **5.6** Add tutorial/onboarding — brief contextual hints for first-time players
- [ ] **5.7** Add minimap or spatial awareness aid
- [ ] **5.8** Fix tween caching — reuse tweens instead of creating new ones every update
- [ ] **5.9** Throttle `updateDismantleBars` — run every 0.1s instead of every frame
- [ ] **5.10** Add victory/defeat screen with session stats

---

## Execution Order

```
Phase 1 (Foundation)  →  Phase 2 (Mechanics)  →  Phase 3 (Win Condition)
                                                         ↓
                                              Phase 4 (Audio/Polish)
                                                         ↓
                                              Phase 5 (UI/UX)
```

Phase 1 is non-negotiable first — security and architectural fixes before building new features on a shaky foundation. Phase 2 transforms the tech demo into a playable game. Phase 3 makes it completable. Phases 4-5 make it feel worth playing.

---

## Key Files Reference

| File | Role |
|------|------|
| `src/server/init.server.luau` | Server bootstrap — all service Init() calls |
| `src/client/init.client.luau` | Client bootstrap |
| `src/shared/Constants.luau` | All game tuning values |
| `src/shared/Types.luau` | Luau type definitions |
| `src/shared/Remotes.luau` | Remote event/function registry |
| `src/shared/TheftComponent.luau` | Reusable dismantle progress tracker |
| `src/server/Services/EconomyService.luau` | Team scrap pool, exponential cost, death penalty |
| `src/server/Services/BuildingService.luau` | Blueprint placement, ghost→building, turret/drill behavior |
| `src/server/Services/EnemyService.luau` | Wave spawning, rat AI, pathfinding, combat |
| `src/server/Services/ResourceService.luau` | Drill stability, degradation, wrench repair |
| `src/server/Services/ObjectiveService.luau` | Titan core, integrity drain, stage completion (dead code) |
| `src/server/Services/RoleService.luau` | Role assignment, stat multipliers, legacy buff |
| `src/server/Services/StormService.luau` | Storm events, tether pads, wind damage, steel drops |
| `src/server/Services/DebugService.luau` | Studio-only debug commands |
| `src/client/UI/MainHUD.luau` | All UI (893-line god module) |
| `src/client/Controllers/BlueprintController.luau` | Client-side building preview + placement |
| `src/client/Controllers/ToolController.luau` | Shotgun + wrench input handling |
| `src/client/Controllers/VFXController.luau` | Particles, loot fountains, storm lighting |
