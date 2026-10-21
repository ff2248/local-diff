#!/bin/bash
set -euo pipefail

# Update the Homebrew cask in ff2248/homebrew-localdiff. Used by release.yml after the DMG upload.
#
# Usage: scripts/update_homebrew_cask.sh <version> <sha256>
#   version  semver without the "v" prefix (e.g. 1.0.0)
#   sha256   hex digest of the DMG

VERSION="${1:?Usage: scripts/update_homebrew_cask.sh <version> <sha256>}"
SHA256="${2:?Usage: scripts/update_homebrew_cask.sh <version> <sha256>}"

command -v brew >/dev/null || { echo "Error: brew not found"; exit 1; }
command -v git >/dev/null || { echo "Error: git not found"; exit 1; }

REPO="${TAP_REPO:-git@github.com:ff2248/homebrew-localdiff.git}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

git clone "$REPO" "$WORK_DIR"
cd "$WORK_DIR"
mkdir -p Casks

cat > Casks/localdiff.rb << CASK
cask "localdiff" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/ff2248/local-diff/releases/download/v#{version}/LocalDiff-v#{version}.dmg"
  name "LocalDiff"
  desc "Offline side-by-side text diff with character-level highlights"
  homepage "https://github.com/ff2248/local-diff"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "LocalDiff.app"

  zap trash: [
    "~/Library/Application Scripts/io.github.ff2248.localdiff",
    "~/Library/Containers/io.github.ff2248.localdiff",
  ]
end
CASK

HOMEBREW_NO_AUTO_UPDATE=1 brew style --fix Casks/localdiff.rb

if [[ "${DRY_RUN:-}" == 1 ]]; then
  cat Casks/localdiff.rb
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Casks/localdiff.rb
git diff --cached --quiet || { git commit -m "Update LocalDiff to ${VERSION}" && git push; }
