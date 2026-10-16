#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p .build Build
xcodebuild -project EasyJournal/EasyJournal.xcodeproj -scheme EasyJournal \
  -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build > .build/build.log 2>&1 || {
    tail -80 .build/build.log
    exit 1
  }
ditto .build/DerivedData/Build/Products/Release/EasyJournal.app 'Build/Journal Agent.app'
print 'Built: Build/Journal Agent.app'
