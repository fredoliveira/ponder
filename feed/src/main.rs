//! ponder-feed: follows Arena's Player.log with recall-core and prints the draft events
//! Ponder cares about as JSON lines on stdout - the same generic view recall's
//! archive writes (`{"event": "draft_pack", ...}`), so an archive file replays identically.
//!
//! Usage: `ponder-feed` follows the live log; `ponder-feed <LOG>` parses one file and exits.
//! Nothing is uploaded anywhere: the only service is the stdout printer.

use std::io::Write;

use recall_core::events::{GameEvent, Service};
use recall_core::follower::Follower;
use recall_core::paths;

struct Printer;

impl Service for Printer {
    /// Always reports the event as delivered: Ponder keeps no checkpoint (it re-reads
    /// the log from the start on every launch to restore an in-progress draft).
    fn handle(&mut self, event: &GameEvent) -> bool {
        if !matches!(
            event,
            GameEvent::DraftPack(_) | GameEvent::DraftPick(_) | GameEvent::EventCourse { .. }
        ) {
            return true;
        }
        let mut line = serde_json::Map::new();
        line.insert("event".into(), event.name().into());
        if let serde_json::Value::Object(fields) = event.to_json() {
            line.extend(fields);
        }
        let mut out = std::io::stdout().lock();
        // A closed pipe means Ponder quit: stop following.
        if writeln!(out, "{}", serde_json::Value::Object(line)).is_err() || out.flush().is_err() {
            std::process::exit(0);
        }
        true
    }
}

fn main() {
    // Exit with Ponder: once it is gone we are re-parented and nothing reads stdout.
    let parent = std::os::unix::process::parent_id();
    std::thread::spawn(move || {
        loop {
            std::thread::sleep(std::time::Duration::from_secs(2));
            if std::os::unix::process::parent_id() != parent {
                std::process::exit(0);
            }
        }
    });

    let mut follower = Follower::with_sink(Printer);

    if let Some(path) = std::env::args().nth(1) {
        follower.parse_log(&path, false);
        return;
    }

    let current: Vec<_> = paths::possible_current_filepaths()
        .into_iter()
        .filter(|f| f.exists())
        .collect();
    if current.is_empty() {
        eprintln!("ponder-feed: no Player.log found");
        std::process::exit(1);
    }
    // Reads the current log from the start (restoring an in-progress draft), then tails it.
    for file in &current {
        follower.parse_log(&file.to_string_lossy(), true);
    }
}
