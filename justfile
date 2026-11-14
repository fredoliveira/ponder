# Build the log feed helper and the overlay app.
build:
    cd feed && cargo build --release
    swift build -c release

# Follow Arena's live log.
run: build
    OVERLAY_FEED=feed/target/release/overlay-feed .build/release/Overlay

# Cycle through the packs recorded in a recall archive / saved feed output.
replay file interval="4": build
    .build/release/Overlay --replay "{{file}}" --interval {{interval}}

# Build dist/Overlay.app for this machine (app + feed helper, signed; see scripts/bundle.sh).
bundle:
    scripts/bundle.sh

# Build the universal app and dist/Overlay.dmg, as the release workflow does (minus notarizing).
dmg:
    scripts/bundle.sh --universal --dmg

# Build the app bundle and copy it to /Applications.
install: bundle
    rm -rf /Applications/Overlay.app
    cp -R dist/Overlay.app /Applications/
