# Asset policy

Warptracker is **fully free**: every asset must be usable by anyone, for anything, forever, with no strings attached.

## The rule

An asset may be included only if it is one of:

1. **Procedural** — generated in code in this repo (this is the default and the preference; 100% of current assets are procedural).
2. **CC0 / public domain** — no attribution required, no usage restrictions.
3. **Originally created and donated** — made by the contributor and explicitly dedicated CC0 in the PR description.

## Explicitly not allowed

- CC-BY, CC-BY-SA, or anything requiring attribution or share-alike
- "Free for personal/non-commercial use" assets
- Anything extracted from another game (yes, including Diablo)
- AI-generated assets trained to imitate a specific copyrighted style or franchise

## Good CC0 sources

- [Quaternius](https://quaternius.com) — CC0 low-poly 3D models; the Universal Animation Library + Universal Base Characters are our preferred character/animation stack
- [Kenney](https://kenney.nl) — CC0 game assets
- [Poly Haven](https://polyhaven.com) — CC0 HDRIs/textures/models
- [OpenGameArt](https://opengameart.org) — filter by CC0
- [poly.pizza](https://poly.pizza) — CC0 model search
- [freesound](https://freesound.org) — filter by CC0

## Art direction notes

- **No KayKit packs.** They're CC0 and lovely, but heavily used across community games (including World of Claudecraft) — Warptracker should not look like a reskin. Prefer Quaternius, Kenney, or procedural.
- **No Mixamo.** Free to use but not CC0 — its license forbids redistributing raw animation files, which committing to this repo would do. Quaternius's animation libraries cover the same ground as CC0.
- Environment/world leans procedural first; downloaded assets are mainly for characters, creatures, and animation.

Every non-procedural asset added must be listed in this file with its source link and license confirmation.

## Current asset manifest

| Asset | Source | License |
|---|---|---|
| `art/hero-ubc-wip.glb` (not shipped — awaiting outfit pass) | [Quaternius Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) + [Universal Animation Library 1](https://quaternius.com/packs/universalanimationlibrary.html)/[2](https://quaternius.com/packs/universalanimationlibrary2.html) (19 curated clips merged in Blender, meshopt) | CC0 |
| `public/models/knight.glb`, `sword.glb`, `helmet.glb` | [Quaternius Animated Knight Pack](https://quaternius.com/packs/knightcharacter.html) (FBX→GLB via Blender) | CC0 |
| `public/models/skeleton.glb`, `bat.glb` | [Quaternius Animated Monster Pack](https://quaternius.com/packs/animatedmonster.html) (FBX→GLB via Blender) | CC0 |
| `public/models/ghost.glb`, `demon.glb` | [Quaternius Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) (glTF→GLB) | CC0 |
| World decor, warp/telegraph VFX | procedural (`src/game/*.ts`) | MIT (code) |
| All sound effects | procedural WebAudio (`src/game/audio.ts`) | MIT (code) |
| Favicon | inline SVG (`index.html`) | MIT (code) |
