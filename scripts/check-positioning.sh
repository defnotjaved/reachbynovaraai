#!/usr/bin/env bash
# Product law: parents "Know they reach", drivers get "Proof you reached".
# Surveillance vocabulary in product code is a bug, enforced here from day 0.
set -euo pipefail

if grep -rniE '\b(track|tracking|tracked|tracker|monitor|monitoring|monitored|watch|watching|watched|surveil|surveillance|surveilled)\b' \
  --include='*.js' --include='*.jsx' --include='*.html' --include='*.sql' \
  backend/src frontend/src db/migrations; then
  echo ''
  echo 'FAIL: surveillance language found in product code.'
  echo 'Reach credits the driver for doing the job; it does not describe itself this way.'
  exit 1
fi

echo 'Positioning check passed.'
