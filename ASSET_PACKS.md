# Development Asset Packs

This project supports development-time asset pack switching for visuals, audio, and animations.

## Quick switch

1. Open `src/shared/AssetPackConfig.luau`.
2. Set `ActivePack` to the pack name you want.
3. Sync/restart Studio session if needed.

Example:

```luau
return {
	ActivePack = "Default",
	Strict = false,
}
```

## File layout

- `src/shared/AssetPackConfig.luau`
- `src/shared/assetpacks/AssetPackResolver.luau`
- `src/shared/assetpacks/DefaultPack.luau`

Additional packs belong in `src/shared/assetpacks/`.

## Naming for custom packs

The resolver accepts either:

- exact module name (`MyPack`)
- or module name with `Pack` suffix (`MyPackPack`)

Recommended naming is exact name match with config, like:

- `AssetPackConfig.ActivePack = "RetroIndustrial"`
- module file: `src/shared/assetpacks/RetroIndustrial.luau`

## Pack contract

Every pack module must return:

- `VisualManifest` table
- `AudioManifest` table
- `Animations` table

Minimum animation keys expected by current code:

- `Punch`
- `Shot`
- `Build`

## Fallback and validation behavior

- Missing pack module -> falls back to `DefaultPack`.
- Missing section/key -> merges from `DefaultPack`.
- `Strict = false` warns and continues.
- `Strict = true` throws on contract violations.

## Create a new pack

1. Copy `src/shared/assetpacks/DefaultPack.luau`.
2. Rename to your pack name.
3. Edit only assets you want to test.
4. Set `ActivePack` in config.

## Smoke test checklist

- Change one color in `VisualManifest` and verify in-game.
- Change one sound in `AudioManifest` and verify in-game.
- Change one animation in `Animations` and verify tool/build animation updates.
