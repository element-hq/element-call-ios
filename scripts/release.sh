#!/usr/bin/env bash
#
# Copyright 2026 Element Creations Ltd.
#
# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
# Please see LICENSE files in the repository root for full details.
#
# Prepares a release: validates the version, asks GitHub for the release notes the pull request
# labels imply, and prepends them to CHANGES.md. It stops there.
#
# This script never touches the remote. It does not commit, tag, push, or create a release, so
# running it locally is a real rehearsal rather than an approximation of one -- the worst it can do
# is leave a modified CHANGES.md in the working tree. The workflow does the publishing, from exactly
# these outputs. See RELEASING.md.

set -euo pipefail

usage() {
    cat >&2 <<'USAGE'
Usage: scripts/release.sh <version> [--notes-out <path>]

  <version>       The version to release, bare semver: 0.1.0, or 0.2.0-rc.1 for a prerelease.
  --notes-out     Where to write the generated release notes (default: release-notes.md).
USAGE
    exit 64
}

VERSION=""
NOTES_OUT="release-notes.md"

while [ $# -gt 0 ]; do
    case "$1" in
        --notes-out)
            [ $# -ge 2 ] || usage
            NOTES_OUT="$2"
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        -*)
            echo "error: unknown option $1" >&2
            usage
            ;;
        *)
            [ -z "$VERSION" ] || usage
            VERSION="$1"
            shift
            ;;
    esac
done

[ -n "$VERSION" ] || usage

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CHANGELOG="CHANGES.md"

# The changelog is rewritten through a temporary file, so a failure mid-write leaves the original
# intact -- but it would leave the temporary behind, untracked and not ignored, ready to be swept
# into an unrelated commit by a later `git add -A`.
trap 'rm -f "$CHANGELOG.tmp" "$NOTES_OUT.clean"' EXIT

fail() {
    # ::error:: makes the message the annotation GitHub shows against the step, so a refusal names
    # its own cause on the run summary rather than only in the log.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::error::$1"
    else
        echo "error: $1" >&2
    fi
    exit 1
}

# --- 1. The version is bare semver ------------------------------------------------------------
#
# Bare, because SwiftPM matches a host's `exactVersion` against the tag with no prefix. A `v` is the
# likeliest slip, since matrix-rust-rtc tags that way, so it gets its own message.
case "$VERSION" in
v[0-9]*) fail "Version must not start with 'v'. Tags here are bare, e.g. ${VERSION#v}, because that is what SwiftPM matches against a host's exactVersion." ;;
esac

if ! [[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$ ]]; then
    fail "'$VERSION' is not a semantic version. Expected MAJOR.MINOR.PATCH, optionally followed by a prerelease such as -rc.1."
fi

PRERELEASE="no"
case "$VERSION" in
*-*) PRERELEASE="yes" ;;
esac

# --- 2. The tag does not exist, and sorts above the newest one in this line of history ----------
if git rev-parse -q --verify "refs/tags/$VERSION" > /dev/null 2>&1; then
    fail "Tag $VERSION already exists."
fi

# Two things here are load-bearing, and both were got wrong first.
#
# `--merged HEAD` restricts this to releases in *this* line of history. Without it, a release branch
# cut from the 0.2.0 tag to fix the 0.2 line would see main's 0.3.0 and refuse 0.2.1 as going
# backwards -- and, worse, would generate that release's notes against 0.3.0, listing every pull
# request from a release the fix does not contain.
#
# `versionsort.suffix=-` stops git ranking a prerelease above its own release. By default
# `--sort=-v:refname` gives `0.2.0-rc.1, 0.2.0`, so once an rc has shipped the newest tag is read as
# the rc rather than the release it preceded, and previous_tag_name below points at the wrong place.
# Only release tags, so archive/pre-squash and any other non-version tag are ignored.
LATEST_TAG="$(git -c versionsort.suffix=- tag --list --merged HEAD --sort=-v:refname \
    | grep -E '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$' \
    | head -n 1 || true)"

if [ -n "$LATEST_TAG" ]; then
    echo "Newest release tag in this history: $LATEST_TAG"

    # `sort -V` orders a prerelease *after* its release (0.2.0 < 0.2.0-rc.1), the same inversion
    # git has, so compare the release parts and let an equal pair through: 0.2.0-rc.2 after
    # 0.2.0-rc.1 is legitimate, and so is 0.2.0 after 0.2.0-rc.1.
    if [ "$(printf '%s\n%s\n' "${LATEST_TAG%%-*}" "${VERSION%%-*}" | sort -V | head -n 1)" != "${LATEST_TAG%%-*}" ]; then
        fail "$VERSION sorts below $LATEST_TAG, which is already released in this history. To fix an older line, branch from that line's tag rather than from main."
    fi
else
    echo "No release tag in this history; this is the first."
fi

# The one case the comparison above lets through, because it compares release parts and treats an
# equal pair as fine: a prerelease for a version that already shipped stably. 0.2.0-rc.1 after
# 0.2.0 is never what anyone meant.
if [ "$PRERELEASE" = "yes" ] && git rev-parse -q --verify "refs/tags/${VERSION%%-*}" > /dev/null 2>&1; then
    fail "${VERSION%%-*} has already been released, so $VERSION is a prerelease of the past. Bump the patch or minor instead."
fi

# --- 3. This commit has a green test run ------------------------------------------------------
#
# The release job runs on Linux and never opens Xcode, so it cannot test anything itself. It asks
# instead whether the Tests workflow already passed for this exact commit, which keeps the pinned
# simulator triple in tests.yml and record-snapshots.yml rather than adding a third copy here.
# tests.yml runs on pushes to release/** for this reason.
#
# Skipped for a local rehearsal, where the answer is usually "not pushed yet".
SHA="$(git rev-parse HEAD)"

if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # An unfinished run has a null conclusion, so report `status` too -- "in_progress" is a very
    # different instruction to the reader than "failure" or "no run at all". The `|| fail` matters:
    # without it a 403 or 404 would kill the script inside the assignment, with no annotation, and
    # the promise that every refusal names its own cause would be quietly false.
    RUN="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/tests.yml/runs?head_sha=$SHA&per_page=1" \
        --jq '.workflow_runs[0] | if . == null then "none/none" else "\(.status)/\(.conclusion // "pending")" end' \
        || fail "Could not query the Tests workflow for $SHA. The token needs actions:read on this repository.")"

    if [ "${RUN#*/}" != "success" ]; then
        case "$RUN" in
            none/none) fail "No Tests run exists for $SHA. Push the branch and let Tests run before releasing it." ;;
            *) fail "Tests has not succeeded for $SHA (status: ${RUN%%/*}, conclusion: ${RUN#*/}). Releasing an untested commit is not allowed; wait for it, or re-run it." ;;
        esac
    fi
    echo "Tests: success for $SHA"
else
    echo "Tests: not checked (local run)"
fi

# --- 4. Ask GitHub for the notes the labels imply ----------------------------------------------
#
# generate-notes is the read-only half of the release API's generate_release_notes: it accepts a tag
# that does not exist yet and creates nothing, reading the categories from .github/release.yml on
# its own. That is what lets the tag be created last and still contain its own changelog entry.
# element-x-ios has to create the release first and read the body back off the response, which is
# why its CHANGES.md commit lands after the tag rather than inside it.
BODY_ARGS=(-f "tag_name=$VERSION" -f "target_commitish=$SHA")
if [ -n "$LATEST_TAG" ]; then
    BODY_ARGS+=(-f "previous_tag_name=$LATEST_TAG")
fi

gh api -X POST "repos/${GITHUB_REPOSITORY:-element-hq/element-call-ios}/releases/generate-notes" \
    "${BODY_ARGS[@]}" --jq .body > "$NOTES_OUT" \
    || fail "Could not generate release notes for $VERSION."

# Not `[ -s ]`: the body is never empty, because it always ends with a **Full Changelog** compare
# link. A release with nothing in it is one with no list items, and it would otherwise write a
# changelog section containing only that link.
if ! grep -qE '^\* ' "$NOTES_OUT"; then
    fail "GitHub generated no changelog entries for $VERSION. Nothing has merged since ${LATEST_TAG:-the start of the history}."
fi

echo
echo "--- Release notes -------------------------------------------------------------"
cat "$NOTES_OUT"
echo "-------------------------------------------------------------------------------"
echo

# An unlabelled pull request lands under Others, per the "*" catch-all in .github/release.yml.
# Nothing enforces the label at merge time, so this is where it gets noticed -- and because the
# notes are generated now rather than at merge, relabelling the merged pull request and running
# again is the whole fix.
if grep -q '^### Others' "$NOTES_OUT"; then
    echo "note: there are entries under 'Others'. Those pull requests are missing a pr- label."
    echo "      Label them and run again; the notes are generated now, so a late label still lands."
    echo
fi

# --- 5. Close the Unreleased section and open a fresh one --------------------------------------
#
# CHANGES.md keeps a `## Unreleased` heading at the top. Releasing renames it to `## <version> -
# <date>` and opens an empty one above, which is why the file exists in the repository rather than
# being conjured by the first release: contributors can see where a host-facing note goes, and
# `git restore CHANGES.md` works after a rehearsal.
#
# Anything hand-written under Unreleased is carried into the released section and kept *above* the
# generated list, because a breaking change someone bothered to write out by hand should not be
# below thirty lines of "* Bump foo by @renovate".
#
# The generated part gets the same cleanup element-x-ios applies in
# Tools/Sources/Commands/CI/ReleaseToGithub.swift, so both repositories' changelogs read alike: the
# notes' own "## What's Changed" becomes a level-three heading under ours, and its level-three
# category headings become plain separators.
if ! grep -qE '^## Unreleased[[:space:]]*$' "$CHANGELOG"; then
    fail "$CHANGELOG has no '## Unreleased' heading, so there is nowhere to record $VERSION. Restore it before releasing."
fi

sed -e 's/<!--.*-->//' -e 's/^### /\n/' -e 's/^## /### /' "$NOTES_OUT" > "$NOTES_OUT.clean"

awk -v version="$VERSION" -v released="$(date -u +%Y-%m-%d)" -v notes="$NOTES_OUT.clean" '
function flush() {
    print "## Unreleased"
    print ""
    print "_Nothing yet._"
    print ""
    print "## " version " - " released
    print ""

    # Drop the placeholder wherever it sits, rather than only when it is the entire body: someone
    # adding a note by hand is as likely to leave "_Nothing yet._" above it as to replace it.
    gsub(/(^|\n)_Nothing yet\._[[:space:]]*(\n|$)/, "\n", carried)

    # Then trim blank lines from both ends of what is left.
    gsub(/^\n+|\n+$/, "", carried)
    if (carried != "") {
        print carried
        print ""
    }

    while ((getline line < notes) > 0) print line
    close(notes)
    print ""
}
state == "" {
    if ($0 ~ /^## Unreleased[[:space:]]*$/) { state = "unreleased"; next }
    print
    next
}
state == "unreleased" {
    if ($0 ~ /^## /) { flush(); state = "done"; print; next }
    carried = carried $0 "\n"
    next
}
{ print }
END { if (state == "unreleased") flush() }
' "$CHANGELOG" > "$CHANGELOG.tmp"

mv "$CHANGELOG.tmp" "$CHANGELOG"
rm -f "$NOTES_OUT.clean"

echo "Recorded $VERSION in $CHANGELOG and opened a fresh Unreleased section."

# Consumed by the workflow: the tag it should push, and whether the release is a prerelease.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "version=$VERSION"
        echo "prerelease=$PRERELEASE"
        echo "notes=$NOTES_OUT"
    } >> "$GITHUB_OUTPUT"
fi

echo "Prepared $VERSION (prerelease: $PRERELEASE). Nothing has been pushed."
