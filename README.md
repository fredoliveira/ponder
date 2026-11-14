# overlay

A native macOS side panel for MTG Arena drafts: lists the current pack sorted by 17Lands
GIH WR, with card art, colours and rarity on each row. Hover a row for the full card.

- `feed/` - `overlay-feed`, a small Rust binary that follows `Player.log` with `recall-core`
  and prints draft events as JSON lines (the same shape as recall's archive). Uploads nothing.
- `Sources/Overlay/` - the Swift/AppKit app: a non-activating floating panel that docks to
  Arena's window (windowed or fullscreen), shows only while Arena is frontmost and a pick is
  pending, and can be dragged; a `GIH` menu-bar item toggles it and quits.

Ratings come from `17lands.com/api/card_data` (one request per set and format, cached for
3 hours in `~/Library/Caches/mtg-overlay`, along with card images).

## Develop

```sh
just run                      # follow the live log
just replay <events.jsonl>    # cycle through recorded packs, e.g. a recall archive file
.build/release/Overlay --replay <file> --at 0 --snapshot out.png   # render one pack to a PNG
```

`recall-core` comes from recall's GitHub repo, pinned to a release tag in `feed/Cargo.toml`.
To try unreleased parser changes, point it at a local checkout with `path = "../../recall/crates/core"`
for the duration (don't commit that).

## Build and release

```sh
just bundle                   # dist/Overlay.app for this machine, Developer ID signed
just install                  # ...and copy it to /Applications
just dmg                      # universal app + dist/Overlay.dmg
```

Releases are built by `.github/workflows/release.yml`: bump `VERSION`, commit, then push a
matching tag (`v0.1.0`). The workflow builds the universal app, signs, notarizes and staples
it and the .dmg, and publishes a GitHub release. It needs the six `APPLE_*` repo secrets listed
at the top of the workflow (the same ones recall uses).
