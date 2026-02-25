# Junk-Punk Titan: Implementation Strategy

## Current State: ~75% Complete

Phases 1-3 are done. Security patched, architecture cleaned up, core mechanics match GDD, and the game is now completable end-to-end (4-stage Titan upgrade → Final Stand → Victory/Defeat). Remaining: audio/VFX polish (Phase 4) and UI/UX refactoring (Phase 5).

---

## Phase 1: Foundation Fixes (Security, Architecture, Critical Bugs)

No new features — stop the bleeding. Fix what's actively broken or exploitable.

- [x] **1.1** Delete the `RequestPurchase` remote backdoor in `EconomyService` (client-provided `currentCount` bypasses exponential scaling)
- [x] **1.2** Lock roles after first selection — prevent re-firing `RoleSelected` to switch roles mid-session
- [x] **1.3** Add input validation and rate limiting — create a shared `RemoteGuard` utility for throttling + type-checking all remotes
- [x] **1.4** Fix `AddScrap` / `AddStormSteel` to reject negative values
- [x] **1.5** Fix `builtCounts` to decrement on building destruction (currently only increments, so replacement costs escalate unfairly)
- [x] **1.6** Replace all `Parent = nil` with `:Destroy()` (prevents memory leaks from orphaned connections)
- [x] **1.7** Wrap all `Init()` calls in `pcall` with error logging
- [x] **1.8** Centralize `peakPlayerCount` into a single `PlayerTrackingService` — delete the 4 duplicated copies across EnemyService, ResourceService, RoleService, StormService
- [x] **1.9** Extract shared utilities into `Shared/Utils.luau` — `snapToGrid`, `removeToolByName`
- [x] **1.10** Fix blueprint cleanup — add player disconnect handler to destroy orphaned ghost blueprints
- [x] **1.11** Add server-side overlap validation for building placement
- [x] **1.12** Add pending repair timeout in `ResourceService` (10s server-side fallback)

### Phase 1 Changelog

**New files created:**
- `src/shared/Utils.luau` — Shared utility functions (`SnapToGrid`, `RemoveToolByName`) to eliminate duplication across modules.
- `src/server/Services/PlayerTrackingService.luau` — Centralized player count tracking and legacy buff calculations, replacing 4 duplicated copies.
- `src/server/RemoteGuard.luau` — Server-side rate limiter for all client-fired remotes. Tracks per-player call timestamps with configurable window/max.

**Modified files:**
- `src/shared/Remotes.luau` — Removed the exploitable `RequestPurchase` remote.
- `src/server/Services/EconomyService.luau` — Deleted `RequestPurchase` handler, added `amount <= 0` guards on `AddScrap`/`AddStormSteel`.
- `src/server/Services/RoleService.luau` — Role lock after first selection, legacy buffs from `PlayerTrackingService`, `RemoteGuard` on `RoleSelected`, tool cleanup via `Utils`.
- `src/server/Services/BuildingService.luau` — Server-side overlap validation, `builtCounts` decrement on destruction, `RegisterDestroyedSlot` accepts `buildingType`, blueprint cleanup on disconnect, `RemoteGuard` on placement remotes.
- `src/server/Services/EnemyService.luau` — Player tracking via `PlayerTrackingService`, `RemoteGuard` on `HitEnemy`, `:Destroy()` instead of `Parent = nil`.
- `src/server/Services/ResourceService.luau` — Player tracking via `PlayerTrackingService`, 10s pending repair timeout, `RemoteGuard` on `RepairMinigameResult`.
- `src/server/Services/StormService.luau` — Player tracking via `PlayerTrackingService`, `:Destroy()` for wind-killed buildings, `RegisterDestroyedSlot` calls.
- `src/server/init.server.luau` — All `Init()` calls wrapped in `pcall` with `warn()` on failure, `PlayerTrackingService` initialized first.
- `src/client/init.client.luau` — All `Init()` calls wrapped in `pcall` with `warn()` on failure.
- `src/client/Controllers/BlueprintController.luau` — Uses `Utils.SnapToGrid`, removed dead `localPlacedBlueprints` code.

---

## Phase 2: Core Mechanics Completion (Combat, Economy, Enemies)

The game loop is fundamentally incomplete without these.

- [x] **2.1** Implement rat HP system — give rats actual health, turrets deal damage per shot, shotgun deals damage with role multiplier
- [x] **2.2** Fix turret balance — damage per shot + fire rate so rats survive multiple hits
- [x] **2.3** Implement scrap bundle pickup — add `.Touched` handler + 30s despawn timer to all scrap bundles
- [x] **2.4** Differentiate standard kill vs. thief kill rewards — standard = 2-5 scrap, thief = 50% of stolen building cost
- [x] **2.5** Fix enemy targeting — distribute rats across multiple buildings instead of all piling on one
- [x] **2.6** Hook up `GetDifficultyMultiplier()` — actually use it in `SpawnWave` for player-count scaling
- [x] **2.7** Correct Constants to match GDD — Turret base cost 100, Drill 250, rat reward 2-5, shotgun range shortened
- [x] **2.8** Implement loose scrap spawns — periodic map-wide scrap pile generation for Scrappers
- [x] **2.9** Fix storm steel timing — spawn during storm (not after), despawn when storm ends
- [x] **2.10** Fix storm wind damage — separate damage system (not `DismantleProgress`), don't reward players for wind destruction
- [x] **2.11** Add death penalty cooldown — per-player 10s cooldown on scrap tax
- [x] **2.12** Implement tool restrictions — Enforcer can't use Wrench, non-Enforcer can't effectively use Shotgun

### Phase 2 Changelog

**New files created:**
- `src/server/Services/ScrapSpawnService.luau` — Periodically spawns loose scrap piles across the map (3 piles every 15s, 5 scrap each, 45s despawn). Raycast-placed on terrain surface with `.Touched` pickup handler.

**Modified files:**

- `src/shared/Constants.luau` — Comprehensive GDD alignment:
  - `BASE_COSTS`: Turret 50→100, Drill 75→250.
  - `BUILDING`: `TurretFireInterval` 0.5→1.5s, added `TurretDamage = 15`, `DefaultHP = 100`.
  - `COMBAT`: Renamed `ShotgunDamage` → `ShotgunBaseDamage = 40`, `ShotgunRange` 80→30, removed `RatKillScrapReward`, added `RatBaseHealth = 100`, `RatFleeSpeedMultiplier = 1.2`, `StandardKillMinReward = 2`, `StandardKillMaxReward = 5`, `ThiefKillRefundPercent = 0.5`, `ScrapBundleDespawnSeconds = 30`.
  - `MAINTENANCE`: `DrillBaseOutput` 10→15.
  - Added `ECONOMY` section: `InitialScrap = 100`, `DeathPenaltyPercent = 0.15`, `DeathPenaltyCooldownSeconds = 10`.
  - Added `SCRAP_SPAWNS` section for loose scrap system.
  - `STORM`: Added `SteelSpawnRadius = 120`, `StormSteelDropCount` 3→5.
  - Removed top-level `SCRAP_BUNDLE_VALUE`.

- `src/server/Services/EnemyService.luau` — Major rewrite:
  - **Rat HP system**: Rats spawn with `Humanoid.MaxHealth = 100`. Death handled via `Humanoid.Died` event instead of instant destruction.
  - **Rat state machine**: `ratStates` table tracks `"approaching"` → `"dismantling"` → `"fleeing"` with `stolenBuildingCost` and `despawning` flag.
  - **Standard vs. thief kills**: Standard kills award 2-5 random scrap immediately. Thief kills (rat in flee state) additionally drop a physical Scrap Bundle worth 50% of the stolen building's base cost.
  - **Collectible scrap bundles**: `.Touched` pickup handler with double-collection guard and 30s auto-despawn.
  - **Distributed targeting**: `getTargetBuilding()` randomly picks from top 3 most expensive buildings instead of always targeting the single most expensive one.
  - **Difficulty scaling**: `SpawnWave` now applies `GetDifficultyMultiplier()` to enemy count (1x for ≤3 players, 1.5x for 4, 2x for 5+).
  - **Server-authoritative damage**: `HitEnemy` handler computes damage from `ShotgunBaseDamage * player.DamageMult` — client no longer sends damage.
  - **Enforcer gate**: `HitEnemy` rejects players without `Role = "Enforcer"`.
  - **Flee speed**: Fleeing rats get 1.2x walk speed. Movement loop exits early if humanoid dies mid-path.
  - Removed `getMostExpensiveBuilding`, `getBuildingTypeAndBaseCost`, `spawnScrapBundle` (replaced by new implementations).

- `src/server/Services/BuildingService.luau` — Turret + wind HP changes:
  - **Turrets deal damage**: `humanoid:TakeDamage(TurretDamage)` per shot instead of `killRatFromBuilding()`. A rat survives ~7 turret shots (10.5s).
  - **Skip dead rats**: `getNearestRat` checks `humanoid.Health > 0` before targeting.
  - **Building HP attribute**: `createFinalBuilding` sets `BuildingHP = 100` on every new building.
  - Removed `killRatFromBuilding` entirely — kill rewards now handled by `Humanoid.Died` in `EnemyService`.

- `src/server/Services/StormService.luau` — Timing + damage model fix:
  - **Steel spawns during storm**: `spawnStormSteelDuringStorm()` called at storm start, `clearStormSteel()` at storm end. Previously steel only appeared after the storm was over.
  - **Wind damage uses `BuildingHP`**: Reads/decrements a separate `BuildingHP` attribute instead of hijacking `DismantleProgress`. No `IsBeingDismantled` flag set.
  - **No scrap for wind destruction**: Buildings destroyed by wind trigger `RegisterDestroyedSlot` but no `AddScrap` — purely a loss event as intended by GDD.
  - Removed `createStormScrapBundle` and post-storm `spawnStormSteelDrops`.

- `src/server/Services/EconomyService.luau` — Death penalty overhaul:
  - **Per-player 10s cooldown**: `deathPenaltyCooldowns` map tracks last penalty timestamp per `UserId`. Dying twice within 10s only triggers one penalty.
  - **Initial scrap from constants**: Uses `Constants.ECONOMY.InitialScrap` (100) instead of hardcoded parameter.
  - **Cleanup on disconnect**: Cooldown timestamps cleared on `PlayerRemoving`.

- `src/client/Controllers/ToolController.luau` — Role enforcement:
  - **Enforcer-only shotgun**: `fireShotgun()` early-returns if `Role ~= "Enforcer"`.
  - **Fixer-only wrench**: `useWrench()` early-returns if `Role ~= "Fixer"`.
  - **No client-sent damage**: `HitEnemy:FireServer(ratModel)` — removed damage parameter (now server-authoritative).

- `src/client/Controllers/VFXController.luau` — Fixed broken constant reference:
  - `RatKillScrapReward` → `StandardKillMaxReward` for kill position VFX.

- `src/server/init.server.luau` — Added `ScrapSpawnService` to init order. `EconomyService.Init()` no longer receives hardcoded `100` (uses constant).

---

## Phase 3: The Win Condition (Titan Stages, Finale, Victory)

Without this, the game cannot be completed.

- [x] **3.1** Design stage cost table — define Scrap + Steel costs for stages 1-4 in `Constants.luau`
- [x] **3.2** Create Titan deposit interaction — proximity prompt at Titan Core, hold E to deposit resources
- [x] **3.3** Wire up `ObjectiveService.CompleteStage` — trigger when deposit thresholds are met
- [x] **3.4** Add Titan visual updates — change Titan appearance on each stage completion
- [x] **3.5** Add Titan progress UI — top-right HUD showing integrity bar + stage requirements
- [x] **3.6** Implement the 99% Final Stand — permanent storm, infinite elite swarm, hidden 3-5 min timer
- [x] **3.7** Implement Victory state — shockwave VFX, all enemies vaporized, VICTORY screen
- [x] **3.8** Add session statistics tracking — scrap gathered, rats killed, buildings lost, display on victory/defeat

### Phase 3 Changelog

**New remotes added** (`Remotes.luau`):
- `GlobalVictory` (RemoteEvent), `TitanStageCompleted` (RemoteEvent), `FinalStandStarted` (RemoteEvent), `RequestSessionStats` (RemoteFunction).

**New type** (`Types.luau`):
- `SessionStats` — scrapGathered, ratsKilled, buildingsLost, stagesCompleted, wavesCompleted, timeElapsed.

**Modified files:**

- `src/shared/Constants.luau` — Added `TITAN` section:
  - Stage costs: Stage 1 (200 Scrap), Stage 2 (400 Scrap + 2 Steel), Stage 3 (600 Scrap + 5 Steel), Stage 4 (800 Scrap + 10 Steel).
  - `IntegrityRepairPerStage = 25`, `DepositRange = 12`, `FinalStandDurationSeconds = 240`, `EliteRatHealthMult = 2.0`, `EliteRatSpeedMult = 1.3`, `EliteSpawnIntervalSeconds = 3`.

- `src/server/Services/ObjectiveService.luau` — Complete rewrite:
  - **ProximityPrompt deposit**: 1.5s hold on Titan Core, shows next stage requirements. Validates scrap/steel, deducts via `EconomyService.DeductScrap/DeductStormSteel`.
  - **Stage progression**: `CompleteStage` enforces sequential order (must complete 1→2→3→4). Each stage repairs +25 integrity, updates Titan visual appearance (color, material, PointLight brightness/range per stage).
  - **Final Stand**: Stage 4 completion fires `FinalStandStarted`, sets `GameState = "final_stand"` attribute on Titan model, starts 240s hidden timer. If integrity > 0 when timer expires → `triggerVictory()`.
  - **Victory**: Sets `GameState = "victory"`, fires `GlobalVictory` to all clients. EnemyService and StormService react via BindableEvent signal → destroy all enemies, stop storm.
  - **BindableEvent**: `ConnectGameStateChanged(callback)` API for cross-service signaling without circular dependencies.
  - **Session stats**: `RequestSessionStats` handler uses lazy `require` at runtime to query `EnemyService.GetTotalKills()`, `BuildingService.GetBuildingsLost()`, `EconomyService.GetTotalScrapGathered()`, plus own `currentStage` and `sessionStartTime`.

- `src/server/Services/EnemyService.luau` — Final Stand + stats:
  - **Kill counter**: `totalKills` incremented in `handleRatDeath`. Exposed via `GetTotalKills()`.
  - **Elite rats**: `createScrapRatModel(pos, isElite)` — elite rats have 2x HP (200), 1.3x speed, larger red-tinted body.
  - **Final Stand spawning**: `startFinalStandSpawning()` — spawns one elite rat every 3 seconds toward Titan/buildings, runs until victory/defeat.
  - **Game state listener**: Connects to `ObjectiveService.ConnectGameStateChanged`. On "final_stand" → start elite spawning. On "victory"/"defeat" → `StopAll()` destroys all active rats and halts wave loop.
  - **`gameActive` flag**: Wave loop and HitEnemy handler gate on this flag.
  - Refactored `SpawnScrapRat` to use shared `spawnRatToward` internal function.

- `src/server/Services/StormService.luau` — Permanent storm + stop:
  - **Requires ObjectiveService**: Connects to game state changes.
  - **`StartPermanentStorm()`**: Sets `permanentStorm = true`, storm runs indefinitely (duration = `math.huge`). Respawns steel every 30 seconds.
  - **`StopStorm()`**: Immediately clears pads, steel, sets `activeStorm = false`.
  - **Game state listener**: On "final_stand" → permanent storm. On "victory" → stop storm + fire `StormEnded`.
  - **`gameActive` flag**: Storm interval loop gates on this.

- `src/server/Services/EconomyService.luau` — Stats + deduct methods:
  - **`totalScrapGathered`**: Running total incremented in `AddScrap`. Exposed via `GetTotalScrapGathered()`.
  - **`DeductScrap(amount)`**: Subtracts from team pool, fires update. Returns false if insufficient.
  - **`DeductStormSteel(amount)`**: Same for steel. Used by `ObjectiveService.CompleteStage`.

- `src/server/Services/BuildingService.luau` — Stats:
  - **`buildingsLostCount`**: Incremented in `RegisterDestroyedSlot`. Exposed via `GetBuildingsLost()`.

- `src/client/UI/MainHUD.luau` — Titan UI + end screens:
  - **Titan progress panel** (top-right): Shows "STAGE X/4", integrity bar (color-coded green/yellow/red), next stage requirements. Updates via `GetAttributeChangedSignal` on Titan model — no Heartbeat polling.
  - **Final Stand banner**: Pulsing "FINAL STAND — DEFEND THE TITAN" banner with alternating gold/red text animation.
  - **Victory screen**: Full overlay with gold "VICTORY" title, session stats, 6s auto-teleport.
  - **Game over enhanced**: Now displays session stats before teleport.
  - **Stage completion flash**: Titan stage label flashes yellow on `TitanStageCompleted`.

- `src/client/Controllers/VFXController.luau` — Victory shockwave:
  - On `GlobalVictory`: spawns expanding golden Neon sphere at Titan Core position (4→500 studs over 2.5s, fading to transparent).

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
| `src/server/Services/ScrapSpawnService.luau` | Periodic loose scrap pile spawning for Scrappers |
| `src/server/Services/PlayerTrackingService.luau` | Centralized player count + legacy buff calculations |
| `src/server/RemoteGuard.luau` | Server-side rate limiter for client-fired remotes |
| `src/shared/Utils.luau` | Shared utilities (SnapToGrid, RemoveToolByName) |
| `src/server/Services/DebugService.luau` | Studio-only debug commands |
| `src/client/UI/MainHUD.luau` | All UI (893-line god module) |
| `src/client/Controllers/BlueprintController.luau` | Client-side building preview + placement |
| `src/client/Controllers/ToolController.luau` | Shotgun + wrench input handling |
| `src/client/Controllers/VFXController.luau` | Particles, loot fountains, storm lighting |
