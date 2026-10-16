#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p .build
xcrun swiftc -module-cache-path .build/module-cache -target arm64-apple-macos26.0 \
  EasyJournal/EasyJournal/JournalAnalysis.swift EasyJournal/EasyJournal/JournalStore.swift \
  EasyJournal/EasyJournal/JournalRetrieval.swift EasyJournal/EasyJournal/AnalysisOutput.swift EasyJournal/EasyJournal/JournalIntelligence.swift \
  Tests/IntelligenceSmoke.swift -o .build/intelligence-smoke
.build/intelligence-smoke
