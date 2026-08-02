# Vox Semaphore

Play your emotes **in a mission**, and broadcast them so squadmates running the mod see them
on your character.

## Requirements

| Mod | Required | Purpose |
| --- | --- | --- |
| **SimpleAssets** | **yes** | loads the emote wheel's petal art at runtime |
| **Vox Manifold** | optional | relays emotes to squadmates; without it the mod plays your emotes for yourself only |

`SimpleAssets` is by **deluxghost** and `Vox Manifold` is by **Wobin**.

The `+ Vox Manifold + SimpleAssets` archive bundles both for convenience; the plain
`Vox Semaphore` archive is the mod on its own. If you already have either dependency
installed, keep whichever version is newer.

## Load order

Load order does not matter. Vox Semaphore resolves both dependencies lazily, retries the
Vox Manifold connection at mission start, and reloads the wheel art the first time you open
the wheel, so it works whatever order the mods appear in `mod_load_order.txt`.

## Using it

- **Hold `Alt` + `Middle Mouse`** to open the emote wheel.
- Move the cursor out to a category, then further out to pick an emote from it.
- Release to play the highlighted emote.

Only emotes you own *and* that your character's animation set can actually play are shown.

## Options

| Setting | Default | Notes |
| --- | --- | --- |
| Camera during your own emote | Over the shoulder | or "Facing you" |
| Show emotes played by your squad | On | turn off to ignore other players' emotes |
| Emote wheel keybind | Alt + Middle Mouse | hold to open |
| Play your first equipped emote | unbound | convenience hotkey |

## Notes

- Emotes end about a second before the animation clip does, because the tail of most clips is
  the character settling with nothing left to see.
- Moving, attacking or blocking cancels an emote.
- Long emotes run their full length; a 19 second dance really does take 19 seconds.
