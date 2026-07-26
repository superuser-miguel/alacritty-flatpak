# Alacritty — personal Flatpak build

A local, unpublished Flatpak packaging of [Alacritty](https://github.com/alacritty/alacritty)
for a single machine, plus notes on why terminal emulators are awkward to
sandbox at all.

> **Not for distribution.** Alacritty upstream has declined official Flatpak
> support and asked that unofficial packages not be published either
> (alacritty/alacritty#8770, #6474, #5828, #2571). This manifest exists for
> personal use only and is not submitted to Flathub or any other repo.

## What's here

| Path | |
|---|---|
| `flatpak/io.github.superuser_miguel.Alacritty.yml` | flatpak-builder manifest (builds v0.17.0 from source) |
| `flatpak/io.github.superuser_miguel.Alacritty.desktop` | Desktop entry, points at the Flatpak-only config |
| `Findings.md` | Write-up: the sandbox problem, and how Ptyxis and GNOME Terminal handle it |

Build artifacts (`.flatpak-builder/`, `build/`, `repo/`) are ignored — they
regenerate from the manifest.

## The sandbox problem, briefly

A Flatpak'd terminal either runs your shell *inside* the sandbox — trapping
you in the runtime's filesystem rather than your real system — or punches a
hole to the host to spawn processes there.

This build takes the second path, using the mechanism an Alacritty maintainer
suggested in passing: override `terminal.shell` to launch
`flatpak-spawn --host bash -l`. The GUI/GPU process stays sandboxed; the shell
session runs on the host. Verified by comparing `/proc/<pid>/ns/mnt` of the
spawned shell against a host shell — they match, while Alacritty's own process
sits in a distinct bwrap namespace.

This is the same trick Ptyxis uses in production, via its separate
host-spawned `ptyxis-agent`. See `Findings.md` for the full comparison.

## Building

```sh
cd flatpak
flatpak-builder --user --install --force-clean build io.github.superuser_miguel.Alacritty.yml
```

Needs the `org.freedesktop.Sdk.Extension.rust-stable` SDK extension (runtime
`25.08`). The manifest builds with `--share=network` so cargo can fetch
crates.io dependencies — fine for a personal build, not acceptable for a
Flathub submission, which would vendor them instead.

## Shell config

The desktop entry passes `--config-file ~/.config/alacritty/flatpak.toml`
explicitly. That file lives outside this repo (and outside the Flatpak, so it
survives rebuilds) and carries the `terminal.shell` override described above.
Launching via `flatpak run io.github.superuser_miguel.Alacritty` directly
skips it and lands you in a sandbox-trapped shell.
