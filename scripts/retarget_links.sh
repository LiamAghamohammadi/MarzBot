#!/usr/bin/env bash
set -euo pipefail
find . -type f \( -name "*.md" -o -name "*.sh" -o -name "*.php" -o -name "*.txt" \) -print0 | \
xargs -0 sed -i 's#raw.githubusercontent.com/LiamAghamohammadi/MarzBot#raw.githubusercontent.com/LiamAghamohammadi/MarzBot#g'
find . -type f \( -name "*.md" -o -name "*.sh" -o -name "*.php" -o -name "*.txt" \) -print0 | \
xargs -0 sed -i 's#github.com/LiamAghamohammadi/MarzBot#github.com/LiamAghamohammadi/MarzBot#g'
echo "All repo links retargeted to LiamAghamohammadi/MarzBot"
