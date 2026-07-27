# Releasing

Three things ship, and all three are signed with the same key.

| Artifact | Where | Signed by |
|---|---|---|
| `.flatpak` bundle | GitHub Releases | the OSTree commit it was exported from |
| Signed OSTree repo + `.flatpakref` | `superuser-miguel/alacritty-flatpak-repo` → Pages | `flatpak build-update-repo --gpg-sign` |
| Git tag + commits | this repo | GPG, `tag.gpgsign` / `commit.gpgsign` |

## The signing key

```
D67DB8E03D50A8C0    superuser-miguel (git_keys)
                    <16271056+superuser-miguel@users.noreply.github.com>
```

The same key signs Septima and its repo. It is configured per-repo rather than
globally:

```sh
git config --local user.signingkey D67DB8E03D50A8C0
git config --local commit.gpgsign true
git config --local tag.gpgsign true
git config --local user.email 16271056+superuser-miguel@users.noreply.github.com
git config --local user.name superuser-miguel
```

The commit email must match an address on the key **and** a verified address on
the GitHub account, or GitHub will show the commit as Unverified even though the
signature is valid. The public key is already registered on the account, so
signed commits show the Verified badge immediately. If it ever needs
re-adding, export it with `gpg --armor --export D67DB8E03D50A8C0` and paste it
at <https://github.com/settings/gpg/new>.

Confirm a pushed commit was accepted:

```sh
gh api repos/superuser-miguel/alacritty-flatpak/commits/<sha> \
  --jq '.commit.verification | {verified, reason}'
# {"reason":"valid","verified":true}
```

> [!WARNING]
> The key is a standing dependency, not a one-off. Every future release must be
> signed with **this** key or existing installs will refuse the update — flatpak
> pins the key that was baked into the `.flatpakref` at install time. Losing it
> means no trusted updates to that remote ever again, and every user reinstalling
> from scratch.

## Cutting a release

1. **Tag it.** Annotated and signed — never a lightweight tag:

   ```sh
   git tag -s v0.17.0-N -m "v0.17.0-N — <summary>"
   git push origin v0.17.0-N
   ```

   Note that `gh release create <tag>` will happily invent a lightweight,
   unsigned tag if one doesn't exist yet. Always tag first.

2. **Build the bundle.**

   ```sh
   flatpak-builder --user --force-clean --repo=flatpak/repo-release \
       flatpak/build-rel flatpak/io.github.superuser_miguel.Alacritty.yml
   flatpak build-bundle flatpak/repo-release Alacritty.flatpak \
       io.github.superuser_miguel.Alacritty master
   ```

3. **Publish the release.**

   ```sh
   gh release create v0.17.0-N Alacritty.flatpak --title "…" --notes "…"
   ```

4. **Update the hosted repo**, so existing installs get it via `flatpak update`:

   ```sh
   build-aux/publish-repo.sh
   ```

   This rebuilds from scratch, signs the OSTree summary, regenerates static
   deltas, and force-pushes the whole repo as a single squashed commit. It needs
   push access to `git@github.com:superuser-miguel/alacritty-flatpak-repo.git`.

## Verifying

```sh
git tag -v v0.17.0-N                    # tag signature
git log --show-signature -1             # commit signature
git log --format='%h %G? %s' -5         # G = good, N = unsigned

flatpak remote-info --user alacritty-origin io.github.superuser_miguel.Alacritty
```

A clean end-to-end check is to install from the public URL on a machine that has
never seen the app — flatpak verifies the repo signature against the key
embedded in the `.flatpakref`:

```sh
flatpak install --user \
  https://superuser-miguel.github.io/alacritty-flatpak-repo/alacritty.flatpakref
```

## Gotcha: the publish script and tmpfs

`publish-repo.sh` creates its work directory **inside the project**
(`.publish-tmp.XXXXXX`, gitignored) with an explicit `--state-dir`, not in
`/tmp`. `/tmp` is tmpfs here, and flatpak-builder refuses to run when its state
dir and target dir are on different filesystems:

```
The state dir (…/.flatpak-builder) is not on the same filesystem as the
target dir (/tmp/tmp.XXXXXXXX)
```

It would also put the whole cargo build in RAM. Don't move it back to `mktemp -d`.
