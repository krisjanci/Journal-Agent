#!/bin/zsh
set -eu
cd "${0:A:h}"
if [[ ! -d 'Build/Journal Agent.app' ]]; then
  ./scripts/build.sh
fi
open 'Build/Journal Agent.app'
