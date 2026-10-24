#!/bin/bash
#
# Archive BisonHealth AI with a build number that is unique and increasing.
#
# Why this exists: CURRENT_PROJECT_VERSION is 1 in the project file, in six places. App
# Store Connect rejects a second upload that reuses a build number for the same marketing
# version, so every upload after the first would have needed the number edited by hand — in
# six places, consistently, every time. That is the kind of step that gets skipped once and
# then blocks a release at the worst moment.
#
# The build number is the commit count. It is monotonic on a linear history, needs nothing
# stored or remembered, and ties a build back to an exact commit.
#
# Usage:
#   Scripts/archive.sh                      # archive to build/BisonHealth.xcarchive
#   Scripts/archive.sh --dry-run            # print the number and settings, build nothing
#   Scripts/archive.sh --output <path>      # archive somewhere else
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=0
ARCHIVE_PATH="$REPO_ROOT/build/BisonHealth.xcarchive"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --output) ARCHIVE_PATH="$2"; shift 2 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 64 ;;
    esac
done

# A shallow clone counts only the commits it has, which would produce a build number LOWER
# than one already uploaded — App Store Connect would reject it, and the cause would not be
# obvious. Refuse rather than guess.
if [[ "$(git rev-parse --is-shallow-repository)" != "false" ]]; then
    echo "error: shallow clone — the commit count would be wrong." >&2
    echo "       run: git fetch --unshallow" >&2
    exit 1
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"
MARKETING_VERSION="$(
    xcodebuild -project HealthApp/HealthApp.xcodeproj -scheme HealthApp \
        -showBuildSettings -configuration Release 2>/dev/null \
        | awk '$1 == "MARKETING_VERSION" { print $3; exit }'
)"
COMMIT="$(git rev-parse --short HEAD)"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: working tree is dirty — this archive will not match commit $COMMIT" >&2
fi

echo "Marketing version : ${MARKETING_VERSION:-unknown}"
echo "Build number      : $BUILD_NUMBER  (commit count)"
echo "Commit            : $COMMIT"
echo "Archive path      : $ARCHIVE_PATH"

if [[ "$DRY_RUN" == "1" ]]; then
    echo "(dry run — nothing built)"
    exit 0
fi

rm -rf "$ARCHIVE_PATH"
mkdir -p "$(dirname "$ARCHIVE_PATH")"

# Signing is intentionally left to the project's own settings: this script decides the build
# number and nothing else. An archive for upload needs an Apple Distribution identity, which
# is not yet set up (see tracker item 35).
xcodebuild archive \
    -project HealthApp/HealthApp.xcodeproj \
    -scheme HealthApp \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo
echo "Archived build $BUILD_NUMBER ($MARKETING_VERSION) from $COMMIT"
echo "Next: export with an Apple Distribution identity, then upload."
