#!/bin/bash
# Usage: ./release.sh 0.2.1 "One line describing the change"
set -euo pipefail

VERSION=${1:?usage: release.sh X.Y.Z "changelog message"}
MSG=${2:?usage: release.sh X.Y.Z "changelog message"}
REPO="MicahOttah/otter-power"
APPLET_ID="io.github.micahottah.otterpower"

cd "$(dirname "$(readlink -f "$0")")"

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "Version must look like 0.2.1"; exit 1 ;;
esac

EMAIL=$(git config user.email || true)
[ -n "$EMAIL" ] || { echo "Set git user.email first."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Uncommitted changes. Commit them first."; exit 1; }
git fetch origin --tags
git merge-base --is-ancestor origin/main HEAD || { echo "GitHub has commits you don't have. Pull first."; exit 1; }
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "Tag v$VERSION already exists."
  exit 1
fi

START=$(git rev-parse HEAD)
FINISHED=0
undo() {
  if [ "$FINISHED" -eq 0 ]; then
    echo
    echo "Stopped before pushing. Nothing was sent to GitHub."
    echo "To discard the local release commit and tag:"
    echo "  git tag -d v$VERSION; git reset --hard $START"
  fi
}
trap undo EXIT

echo "== bump version to $VERSION"
sed -i "s/\"Version\": \"[^\"]*\"/\"Version\": \"$VERSION\"/" files/home/plasmoid/metadata.json
grep -q "\"Version\": \"$VERSION\"" files/home/plasmoid/metadata.json
sed -i "s/^Version:.*/Version:        $VERSION/" rpm/otter-power.spec
sed -i "s/^Release:.*/Release:        1%{?dist}/" rpm/otter-power.spec
grep -q "^Version:        $VERSION\$" rpm/otter-power.spec
DATE=$(LC_ALL=C date +"%a %b %d %Y")
awk -v d="$DATE" -v e="$EMAIL" -v v="$VERSION" -v m="$MSG" '{print} /^%changelog/{print "* " d " MicahOttah <" e "> - " v "-1"; print "- " m; print ""}' rpm/otter-power.spec > rpm/otter-power.spec.new
mv rpm/otter-power.spec.new rpm/otter-power.spec
if [ -d "$HOME/plasmoids/$APPLET_ID" ]; then
  cp files/home/plasmoid/metadata.json "$HOME/plasmoids/$APPLET_ID/metadata.json"
fi

echo "== commit and tag"
git add -A
git commit -q -m "Release v$VERSION: $MSG"
git tag -a "v$VERSION" -m "Otter Power $VERSION"

echo "== build"
mkdir -p "$HOME/rpmbuild/SOURCES"
git archive --format=tar.gz --prefix="otter-power-$VERSION/" -o "$HOME/rpmbuild/SOURCES/otter-power-$VERSION.tar.gz" "v$VERSION"
if ! rpmbuild -ba rpm/otter-power.spec > /tmp/otter-power-rpmbuild.log 2>&1; then
  tail -30 /tmp/otter-power-rpmbuild.log
  exit 1
fi

OUT="$HOME/release-files/$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$HOME/rpmbuild/RPMS/noarch/otter-power-$VERSION-1."*.noarch.rpm "$HOME/rpmbuild/SRPMS/otter-power-$VERSION-1."*.src.rpm "$HOME/rpmbuild/SOURCES/otter-power-$VERSION.tar.gz" "$OUT/"
(cd "$OUT" && sha256sum -- * > SHA256SUMS && cat SHA256SUMS)
RPMFILE=$(basename "$OUT"/*.noarch.rpm)

NOTES=$(mktemp)
cat > "$NOTES" << NOTES_EOF
$MSG

Tested on one Dell Precision 7670 running Fedora 44 only. It changes power and thermal behavior that the firmware normally owns, so read the README disclaimer first.

Install from the tarball:

    tar xzf otter-power-$VERSION.tar.gz
    cd otter-power-$VERSION
    bash install.sh
    bash verify.sh

Or install the RPM (remove any copy installed with install.sh first):

    sudo dnf install ./$RPMFILE

Check downloads with: sha256sum -c SHA256SUMS
NOTES_EOF

echo
git log --oneline -3
read -r -p "Push to GitHub and create a DRAFT release? [y/N] " ans
[ "$ans" = "y" ] || exit 1

git push origin main
git push origin "v$VERSION"
FINISHED=1

gh release create "v$VERSION" "$OUT"/* -R "$REPO" --title "Otter Power $VERSION" -F "$NOTES" --draft
echo
echo "Draft created. Review and publish it at https://github.com/$REPO/releases"
