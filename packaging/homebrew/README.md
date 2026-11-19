# Homebrew cask

Ponder ships as a cask in the [fredoliveira/homebrew-tap](https://github.com/fredoliveira/homebrew-tap)
tap, next to Recall's formula and cask:

```sh
brew install --cask fredoliveira/tap/ponder
```

`Casks/ponder.rb` in the tap is **generated** by [`generate.sh`](generate.sh) here - edit the
generator, never the tap file directly. It points at the signed, notarized universal `Ponder.dmg`
that the Release workflow attaches to each GitHub release.

## On every release: automated

The Release workflow's `tap` job checksums the just-built `Ponder.dmg`, regenerates
`Casks/ponder.rb` and pushes it to the tap. It authenticates with the **`TAP_PUSH_TOKEN`** repo
secret - a fine-grained PAT with `contents: write` on `fredoliveira/homebrew-tap` (the same token
Recall uses works). If the secret is missing the job skips quietly and the bump must be done by
hand (below).

## Manual bump (fallback)

```sh
sha="$(gh release download vX.Y.Z -R fredoliveira/ponder -p Ponder.dmg -O - | shasum -a 256 | cut -d' ' -f1)"
packaging/homebrew/generate.sh X.Y.Z "$sha" > ../homebrew-tap/Casks/ponder.rb
```

Commit and push the tap repo.

## Verify

From within the tap repo:

```sh
brew audit --strict --online --cask Casks/ponder.rb
brew install --cask Casks/ponder.rb
```
