# Game Phases

This document describes the time-based pacing system that drives difficulty and enemy composition in *Junk Punk Titan*. The game targets a **25-minute** session, with phases alternating between pressure and relief to create rhythm and emotional peaks.

---

## Overview

- **Total duration:** 25 minutes (0:00 → 25:00)
- **Wave-driven:** Swarms spawn at phase-specific intervals. Intensity and enemy mix change per phase.
- **Design goals:**
  - Beginners often lose around 13–15 minutes
  - Experienced players can win within 25 minutes
  - Clear peaks (pressure) and valleys (relief, reward)

---

## Phase Summary

| Phase | Time       | Wave Interval | Intensity | Feel |
| ----- | ---------- | ------------- | --------- | ---- |
| 1     | 0–3 min    | 70s           | 0.35×     | Intro, learning |
| 2     | 3–5 min    | 50s           | 0.80×     | First challenge |
| 3     | 5–10 min   | 65s           | 0.45×     | Elation, "big winner" |
| 4     | 10–13 min  | 50s           | 1.00×     | Slow ramp-up |
| 5     | 13–15 min  | 38s           | 1.70×     | Heavy pressure, beginners die |
| 6     | 15–18 min  | 60s           | 0.50×     | Wind down, recovery |
| 7     | 18–20 min  | 80s           | 0.25×     | Peace, max reward |
| 8     | 20–23 min  | 42s           | 1.30×     | Warning escalation |
| 9     | 23–25 min  | 28s           | 2.50×     | Last stand onslaught |

---

## Phase Details

### Phase 1 — Introduction (0:00 – 3:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 70 seconds |
| Intensity    | 0.35× |
| LootVacuum weight | 1 (baseline) |

**Enemy composition:** Standard rats only (100%).

**Intent:** Teach mechanics. Low pressure, time to build turrets and drills.

---

### Phase 2 — First Challenge (3:00 – 5:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 50 seconds |
| Intensity    | 0.80× |
| LootVacuum weight | 1 |

**Enemy composition:** Standard 85%, Thief 15%.

**Relief:** **StrongLootVacuum** guaranteed at swarm end (base center) to ease transition.

**Intent:** First real challenge. Players pick up power-ups to defend the base.

---

### Phase 3 — Elation (5:00 – 10:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 65 seconds |
| Intensity    | 0.45× |
| LootVacuum weight | 2 (more WeakLootVacuum) |

**Enemy composition:** Standard 85%, Thief 15%.

**Intent:** Strong base, “big winner” feel, players may assume the rest is easy.

---

### Phase 4 — Slow Ramp (10:00 – 13:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 50 seconds |
| Intensity    | 1.00× |
| LootVacuum weight | 2 |

**Enemy composition:** Standard 70%, Thief 10%, **WallEater** 20%.

**Intent:** Noticeable difficulty increase. WallEaters pressure walls first, then drills, turrets, Titan.

---

### Phase 5 — Heavy Pressure (13:00 – 15:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 38 seconds |
| Intensity    | 1.70× |
| LootVacuum weight | 3 |
| Max Juggernauts per wave | 3 |

**Enemy composition:** Standard 55%, Thief 10%, WallEater 15%, Juggernaut 8%, Decoy 12%, **ScrapCarrier 25%** (last batch only).

**Relief:** **StrongLootVacuum** guaranteed at swarm end.

**Intent:** Highest stress. Many beginners lose here. ScrapCarriers reward surviving the last batch.

---

### Phase 6 — Wind Down (15:00 – 18:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 60 seconds |
| Intensity    | 0.50× |
| LootVacuum weight | 3 |

**Enemy composition:** Standard 85%, Thief 15%.

**Intent:** Recovery after Phase 5, chance to repair and rebuild.

---

### Phase 7 — Peace & Max Reward (18:00 – 20:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 80 seconds |
| Intensity    | 0.25× |
| LootVacuum weight | 4 |

**Enemy composition:** Standard 60%, Thief 10%, **ScrapCarrier** 30%.

**Intent:** Low pressure, high ScrapCarrier drops. Moment of peace and strong rewards before the final stretch.

---

### Phase 8 — Escalation Warning (20:00 – 23:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 42 seconds |
| Intensity    | 1.30× |
| LootVacuum weight | 4 |
| Max Juggernauts per wave | 3 |

**Enemy composition:** Standard 50%, Thief 10%, WallEater 15%, Juggernaut 10%, Decoy 15%.

**Relief:** **StrongLootVacuum** guaranteed at swarm end.

**Intent:** Signal that the worst is coming. Players should finish base and upgrades now.

---

### Phase 9 — Last Stand (23:00 – 25:00)

| Parameter    | Value |
| ------------ | ----- |
| Wave interval| 28 seconds |
| Intensity    | 2.50× |
| LootVacuum weight | 4 |
| Max Juggernauts per wave | 3 |

**Enemy composition:** Standard 50%, WallEater 20%, Juggernaut 10%, Decoy 20%. No Thieves.

**Intent:** Short, intense push. Final 2-minute onslaught before Titan Final Stand mode.

---

## Enemy Types

| Type        | Speed | HP  | Role | Targeting |
| ----------- | ----- | --- | ---- | --------- |
| **Standard**| 12   | 18  | Basic threat | Closest building |
| **Thief**   | 14.4 | 15  | Steals scrap, flees | Buildings with scrap |
| **WallEater** | 18 | 14  | Burst walls, then drills/turrets | Wall > Drill > Turret > Titan |
| **Juggernaut** | 5  | 120 | Tanky, high damage | Turrets only (Titan if none) |
| **Decoy**   | 16   | 65  | Absorbs turret fire, no damage | Runs to base, no dismantle |
| **ScrapCarrier** | 7 | 30 | High scrap drop | Standard, last batch only in Phase 5 |

*All enemy HP is multiplied by 1.10 (global buff).*

---

## Power-Up Behavior

- **WeakLootVacuum:** Common, ~20 stud radius around the player. Appears from phase-weighted random drops.
- **StrongLootVacuum:** Rare. Full base radius. Guaranteed at swarm end in **Phases 2, 5, and 8** near base center.
- **lootVacuumWeight:** Extra entries for WeakLootVacuum in the power-up pool (1–4 depending on phase).

---

## Post-Game

After victory or defeat in the Final Stand, the game continues for **10 seconds** before the end screen. Players can process what happened while enemies finish retreating.

---

## Configuration Reference

Phase data is defined in `src/shared/Constants.luau` under `GAME_PHASES`. Enemy stats live in `Constants.ENEMY_TYPES` and `Constants.THIEF_RAT`.
