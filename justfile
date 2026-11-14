# Build the log feed helper and Ponder.
build:
    cd feed && cargo build --release
    swift build -c release

# Follow Arena's live log.
run: build
    PONDER_FEED=feed/target/release/ponder-feed .build/release/Ponder

# Cycle through the packs recorded in a recall archive / saved feed output.
replay file interval="4": build
    .build/release/Ponder --replay "{{file}}" --interval {{interval}}

# Build dist/Ponder.app for this machine (app + feed helper, signed; see scripts/bundle.sh).
bundle:
    scripts/bundle.sh

# Build the universal app and dist/Ponder.dmg, as the release workflow does (minus notarizing).
dmg:
    scripts/bundle.sh --universal --dmg

# Build the app bundle and copy it to /Applications.
install: bundle
    rm -rf /Applications/Ponder.app
    cp -R dist/Ponder.app /Applications/
