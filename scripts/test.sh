#!/bin/zsh
set -eu
cd "${0:A:h}/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -module-cache-path "$build_dir/module-cache" EasyJournal/EasyJournal/JournalAnalysis.swift EasyJournal/EasyJournal/JournalStore.swift Tests/StorageTests.swift -o "$build_dir/storage-tests"
"$build_dir/storage-tests"
xcrun swiftc -module-cache-path "$build_dir/module-cache" EasyJournal/EasyJournal/JournalAnalysis.swift EasyJournal/EasyJournal/JournalStore.swift Tests/AnalysisStorageTests.swift -o "$build_dir/analysis-storage-tests"
"$build_dir/analysis-storage-tests"
