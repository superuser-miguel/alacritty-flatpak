#!/usr/bin/env bash
# Publish the unofficial Alacritty Flatpak to its signed, auto-updating repo.
#
# Ships two ways: a one-off .flatpak bundle on GitHub Releases, and this hosted
# OSTree repo at https://superuser-miguel.github.io/alacritty-flatpak-repo/
# that `flatpak update` tracks.
#
# Layout choice (deliberate): the published repo is regenerated wholesale and
# **force-pushed as a single commit** each release, so its git history never
# accumulates superseded, content-addressed OSTree objects. It is a separate
# GitHub repo from the packaging source — the code repo stays clean.
#
# Prerequisites:
#   - flatpak-builder, ostree, git, gpg
#   - the signing secret key present in the local GPG keyring (see KEYID below);
#     losing it means you can no longer publish trusted updates to this remote.
#   - push access to git@github.com:superuser-miguel/alacritty-flatpak-repo.git
#
# Usage:  build-aux/publish-repo.sh
set -euo pipefail

KEYID="D67DB8E03D50A8C0"          # public key is baked into the .flatpakref
APP_ID="io.github.superuser_miguel.Alacritty"
PAGES_URL="https://superuser-miguel.github.io/alacritty-flatpak-repo"
PUBLISH_REMOTE="git@github.com:superuser-miguel/alacritty-flatpak-repo.git"
MANIFEST="flatpak/${APP_ID}.yml"

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
repo="$work/repo"
build="$work/build-dir"

echo ">> Building signed release into a fresh OSTree repo…"
flatpak-builder --user --force-clean --repo="$repo" --gpg-sign="$KEYID" \
    "$build" "$MANIFEST"

echo ">> Generating static deltas + signing the summary…"
flatpak build-update-repo --generate-static-deltas --prune --gpg-sign="$KEYID" "$repo"

echo ">> Assembling the publish tree (repo + .flatpakref + landing page)…"
pub="$work/publish"
mkdir -p "$pub"
cp -a "$repo" "$pub/repo"
touch "$pub/.nojekyll"   # serve OSTree byte-for-byte; do not let Jekyll rewrite it

key_b64="$(gpg --export "$KEYID" | base64 --wrap=0)"
cat > "$pub/alacritty.flatpakref" <<EOF
[Flatpak Ref]
Name=${APP_ID}
Branch=master
Url=${PAGES_URL}/repo/
Title=Alacritty (unofficial Flatpak)
Homepage=https://github.com/superuser-miguel/alacritty-flatpak
Comment=Signed Flatpak repo for automatic updates
GPGKey=${key_b64}
RuntimeRepo=https://flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
EOF

cat > "$pub/index.html" <<'EOF'
<!doctype html><meta charset=utf-8><title>Alacritty (unofficial Flatpak) — repo</title>
<meta name=viewport content="width=device-width,initial-scale=1">
<style>body{font-family:system-ui,sans-serif;max-width:42rem;margin:4rem auto;padding:0 1rem;line-height:1.6}code,pre{background:#f0f0f0;padding:.1em .3em;border-radius:3px}pre{padding:.8em;overflow-x:auto}.warn{border-left:4px solid #d97706;background:#fffbeb;padding:.8em 1em;border-radius:4px}@media(prefers-color-scheme:dark){body{background:#111;color:#eee}code,pre{background:#222}.warn{background:#2a2010;border-color:#d97706}a{color:#7dd3fc}}</style>
<h1>Alacritty — signed Flatpak repo</h1>
<p class=warn><strong>Unofficial.</strong> The Alacritty project does not publish or endorse
this package and has declined Flatpak support upstream. Report packaging problems to
<a href="https://github.com/superuser-miguel/alacritty-flatpak">this repo</a>, never to Alacritty.</p>
<pre><code>flatpak install --user https://superuser-miguel.github.io/alacritty-flatpak-repo/alacritty.flatpakref
flatpak run io.github.superuser_miguel.Alacritty</code></pre>
<p>Updates then arrive with <code>flatpak update</code>. Signed with the packager's GPG key.</p>
EOF

echo ">> Force-pushing as a single squashed commit…"
version="$(date +%Y-%m-%d)"
git -C "$pub" init -q -b main
git -C "$pub" add -A
git -C "$pub" -c user.name=superuser-miguel \
    -c user.email=16271056+superuser-miguel@users.noreply.github.com \
    commit -q -m "Publish Alacritty Flatpak (${version}) — signed OSTree repo + .flatpakref"
git -C "$pub" remote add origin "$PUBLISH_REMOTE"
git -C "$pub" push -u --force origin main

echo ">> Done. Verify from the public URL:"
echo "   flatpak install --user ${PAGES_URL}/alacritty.flatpakref"
