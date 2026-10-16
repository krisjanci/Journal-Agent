# Journal Agent

A private, voice-first macOS journal organized around useful summaries. Speak naturally, finish the recording, and browse a concise account of your day. Original audio and transcripts remain available inside each entry.

## Open the app

Open **Build/Journal Agent.app** or double-click **Launch Journal Agent.command**. To run from Xcode, open **EasyJournal/EasyJournal.xcodeproj**, choose **EasyJournal → My Mac**, and press **⌘R**.

Requires macOS 26 or later. Voice recognition and local AI require supported Apple silicon hardware. No API keys, subscriptions, Python server, or third-party model downloads are needed.

## Local AI setup

The app uses **Apple Foundation Models**, explicitly with `SystemLanguageModel.default`. There is no cloud fallback. Turn on Apple Intelligence in **System Settings → Apple Intelligence & Siri** if it is not already enabled. macOS manages the model download; keep the Mac connected to power and Wi-Fi while it prepares. The sidebar reports whether the model is ready. Apple's local model was available on this Mac during verification.

Speech transcription uses a separate Apple SpeechTranscriber model, which may download on first use. Microphone permission is requested when you start a recording.

## Daily workflow

- **New voice entry / ⌘N:** open the composer or continue a saved draft.
- **Microphone / ⌘⇧R:** start talking. Click again to **Finish & save**.
- **Manual entry:** use the secondary writing option, then **Save entry / ⌘S**.
- **Summary:** the original saves immediately; local AI prepares a short title, summary, topics, activities, accomplishments, stated plans, and explicitly expressed feelings with quotes.
- **Original entry:** expand this section to play recordings, seek within audio, read the full transcript, or edit it. Editing the transcript makes the old summary outdated and queues a fresh one.
- **Journal:** browse summary cards. **Ask your journal** accepts natural-language searches such as “progress on a project” or “time spent outside.” Press Return or click Search.
- **Export data / ⌘⇧E:** save a CSV containing original text, current summaries, structured fields, and analysis metadata.

Older entries are summarized automatically when the model is ready. Older recordings that were never retained cannot be recovered; their transcripts remain accessible. New recordings are retained locally as CAF audio. Closing or quitting preserves the current draft. A recording without recognized words can still be saved and given a transcript later.

## What search does

Apple's local language model interprets the query into concepts and related terms. The app then checks those terms against each entry's summary and structured details, ranks the supported matches, and explains the matching concepts. This is AI-assisted concept search, not an embedding database or a chatbot. It does not invent entry IDs or answer from unrelated text. Entries without a current summary are searched using the full original transcript.

Specific English date requests can also filter results. Search is most reliable with concrete subjects, activities, and projects; model-generated expansions may still miss a relevant entry. If AI search fails or is unavailable, the app clearly labels a fallback to exact-text search. Searches can be cancelled and replaced; stale results are discarded.

## Data and privacy

SQLite is the source of truth. The original text is never replaced by generated output. Analysis is stored separately with a transcript hash, generation date, schema version, engine name, and operating-system version. An old analysis cannot overwrite a newer edit. Long transcripts are processed in chunks and combined. Feelings and plans are conservatively filtered against source evidence; AI interpretations can still be imperfect. The app does not invent numerical mood ratings or diagnoses.

Use **Show journal files** to open the app's private Application Support folder:

```
~/Library/Containers/devplaceholder.AVNQ8R12.EasyJournal/Data/Library/Application Support/Journal Agent/
  journal.sqlite          original entries, drafts, and analysis
  journal.sqlite-wal      SQLite working data while the app is open
  journal.sqlite-shm      SQLite coordination while the app is open
  journal.csv             automatically refreshed data snapshot
  Recordings/*.caf        original recordings from new voice entries
```

These are local files; they are not separately encrypted by the app. Audio storage grows with recording length. Deleting an entry removes its analysis, transcript, and recordings. Discarding a draft removes its recordings. Exported CSV copies are independent snapshots and do not contain the audio bytes; copy the whole journal folder with the app closed when making a complete backup. Journal data and generated builds are excluded from Git.

The database automatically migrates the earlier journal format without discarding existing entries or drafts. CSV snapshots refresh after saving, editing, deleting, and analysis. A failed CSV write does not undo the database save. Analysis failures leave originals untouched and can be retried.

CSV columns include `id`, `created_at`, `updated_at`, `title`, `text`, `source`, `duration_seconds`, `word_count`, `summary`, `topics`, `activities`, `accomplishments`, `next_steps`, `feelings`, `analysis_generated_at`, `analysis_engine`, `analysis_system_version`, `analysis_version`, `analysis_source_hash`, and `audio_files`. Array fields contain JSON. Dates are ISO 8601 UTC; the app displays local dates. CSV quotes preserve commas and multiple lines. Formula-like strings are escaped for spreadsheet safety; the database retains the original text.

For later analysis, load the CSV into pandas or read SQLite directly. Use the original transcript to verify AI-derived observations before drawing conclusions.

## Build and tests

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-retrieval.sh
./scripts/test-transcription.sh
./scripts/test-intelligence.sh
```

Storage tests use temporary databases and cover migration, persistence, draft recovery, stale-analysis rejection, audio metadata, and CSV handling. Retrieval tests cover concept matching, unrelated queries, word boundaries, and older entries. Transcription tests use a synthetic sentence and retain its audio in a temporary file. The AI smoke test uses fictional entries to check summarization, evidence filtering, relevant retrieval, and an unrelated query. AI and transcription smoke tests need their Apple models available locally.

Debug builds support an isolated test journal via `--test-journal <name>`; Release builds do not accept this option. Normal runs always use the real app container.

Apple references: [Foundation Models](https://developer.apple.com/documentation/FoundationModels) · [SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
