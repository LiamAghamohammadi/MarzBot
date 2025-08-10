#!/usr/bin/env bash
set -euo pipefail
PAYDIR="payment"
if [[ -d "$PAYDIR" ]]; then
  for d in "$PAYDIR"/*; do
    [[ -d "$d" ]] || continue
    bn="$(basename "$d")"
    case "$bn" in
      nowpayments|card2card|telegram_stars) echo "keep: $bn";;
      *) echo "removing: $bn"; rm -rf "$d";;
    esac
  done
else
  echo "payment directory not found."
fi
echo "Done."
