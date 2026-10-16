#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p .build
say -o .build/speech-test.aiff 'Today I am testing my journal. I took a walk outside and had a productive afternoon.'
xcrun swiftc -module-cache-path .build/module-cache \
  EasyJournal/EasyJournal/JournalAnalysis.swift EasyJournal/EasyJournal/JournalStore.swift EasyJournal/EasyJournal/SpeechRecorder.swift \
  Tests/TranscriptionSmoke.swift -o .build/transcription-smoke
.build/transcription-smoke .build/speech-test.aiff
