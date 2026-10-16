# Journal Agent

A minimalist, voice-first macOS journal. Click the microphone, talk naturally, and click **Finish & save**. Your transcript becomes a dated journal entry and is included in an automatically updated CSV file. Typing is available as a secondary option.

## Open the app

Double-click **Build/Journal Agent.app**, or **Launch Journal Agent.command** in this project folder. The launcher builds the app if it has not been built yet.

To develop it, open **EasyJournal/EasyJournal.xcodeproj** in Xcode and run the EasyJournal scheme on My Mac. The project, source, tests, build tools, and built app all live in this folder. No third-party packages or API keys are required.

Requires macOS 26 or later. Voice transcription requires a supported Apple silicon Mac and a language supported by Apple's SpeechTranscriber. Manual entry remains available when speech is unavailable. The first recording asks for microphone access and may download Apple's speech model; model installation needs internet. The app transcribes on-device and does not save or upload audio.

## Daily use

- **Voice:** click the microphone or press **⌘⇧R**. Watch the live transcript and input meter. Click again to finish; the app waits for the final words before saving.
- **Type:** choose **Prefer to write? Add a manual entry**, then **Save entry** or **⌘S**.
- **Continue:** record into an existing draft to append spoken words. A draft is preserved locally as text arrives or is typed.
- **Review:** search the sidebar, open entries, edit the title or text, or delete with confirmation.
- **New entry:** **⌘N** returns to the draft. It never throws away an existing draft.
- **Export:** use **Export CSV** or **⌘⇧E** to save a snapshot wherever you like. **Show journal files** opens the automatically maintained CSV in Finder.
- **Close or quit:** a running recording is stopped and its latest words stay in the draft. Reopen to continue or save.

## Storage recommendation: SQLite + CSV

SQLite is the source of truth. It handles reliable saves, edits, and draft recovery without rewriting or parsing CSV. `journal.csv` is an automatically regenerated snapshot after saving, editing, deleting, and launching. Exported copies are independent snapshots, not live connections. A CSV mirror is not a separate backup; keep backups of important journals.

macOS stores the journal in the app's private Application Support folder, separate from the source repository so private journal content never enters Git. Use **Show journal files** to find the exact folder:

```
~/Library/Containers/devplaceholder.AVNQ8R12.EasyJournal/Data/Library/Application Support/Journal Agent/
  journal.sqlite       authoritative database
  journal.sqlite-wal   SQLite working data while open
  journal.sqlite-shm   SQLite coordination while open
  journal.csv          automatically updated spreadsheet copy
```

The CSV columns are `id`, `created_at`, `updated_at`, `title`, `text`, `source`, `duration_seconds`, and `word_count`. Dates are ISO 8601 UTC; the app displays local dates. Text is UTF-8 with CSV escaping for commas, quotes, and multiple lines. Formula-like text is prefixed with an apostrophe in CSV to make opening in spreadsheets safer; SQLite preserves the original text.

For pandas, load the CSV with `pd.read_csv(path, parse_dates=["created_at", "updated_at"])`, or use `pd.read_sql_query("SELECT * FROM entries", sqlite3.connect(path))` for the original data. A DataFrame is useful for analysis; SQLite is better as the app's permanent storage.

## Build and verification

```sh
./scripts/build.sh
./scripts/test.sh
```

`Tests/StorageTests.swift` covers database persistence, draft recovery, editing, Unicode and multiline CSV, spreadsheet formula escaping, empty-entry rejection, and deletion. `Tests/TranscriptionSmoke.swift` exercises the same audio conversion pipeline against a local audio fixture; see `scripts/test-transcription.sh`.

The app uses SwiftUI, AVAudioEngine, Apple's SpeechAnalyzer/SpeechTranscriber, and the system SQLite library. It does not rewrite journal content with a language model or infer mood/ratings. Recognition accuracy depends on microphone quality, language, and the speech model; saved text remains editable.

If voice setup fails, check System Settings → Privacy & Security → Microphone and System Settings → Sound → Input. An interrupted or failed transcript stays in the draft. If CSV generation fails, an error is shown while SQLite retains the saved entry.

Apple API reference: https://developer.apple.com/videos/play/wwdc2025/277/
