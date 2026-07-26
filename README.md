<h1 align="center">Alacritty — unofficial Flatpak</h1>

<p align="center">
Flatpak packaging of <a href="https://github.com/alacritty/alacritty">Alacritty</a>,
with a working host-shell escape — plus notes on why terminal emulators are
awkward to sandbox at all.
</p>

> [!WARNING]
> **Unofficial and unendorsed.** The Alacritty project has declined official
> Flatpak support and asked that unofficial packages not be published
> ([#8770](https://github.com/alacritty/alacritty/issues/8770),
> [#6474](https://github.com/alacritty/alacritty/issues/6474),
> [#5828](https://github.com/alacritty/alacritty/issues/5828),
> [#2571](https://github.com/alacritty/alacritty/issues/2571)). This package is
> built and maintained independently under Alacritty's Apache-2.0 licence.
> **Report packaging bugs here, never to the Alacritty project.** If you want a
> supported Flatpak terminal, use [Ptyxis](https://flathub.org/apps/app.devsuite.Ptyxis).

## Install

**Recommended — hosted repo, gets `flatpak update`:**

```sh
flatpak install --user https://superuser-miguel.github.io/alacritty-flatpak-repo/alacritty.flatpakref
flatpak run io.github.superuser_miguel.Alacritty
```

This subscribes you to a signed remote, so future releases arrive with
`flatpak update`.

**Alternative — single-file bundle** from
[Releases](https://github.com/superuser-miguel/alacritty-flatpak/releases/latest).
A bundle is a frozen file with **no update path** — you would redownload and
reinstall to upgrade:

```sh
flatpak install --user ./Alacritty.flatpak
```

Both need the Flathub remote configured for the `org.freedesktop.Platform//25.08`
runtime.

## The sandbox problem

A Flatpak'd terminal either runs your shell *inside* the sandbox — trapping you
in the runtime's filesystem rather than your real system — or punches a hole to
the host to spawn processes there. Upstream's objection is that both outcomes
are bad, so terminals are a poor fit for the model on principle.

This build takes the second path, using the mechanism an Alacritty maintainer
suggested in passing: override `terminal.shell` to launch
`flatpak-spawn --host bash -l`. The GPU and UI process stay sandboxed; the shell
session runs on the host.

Verified rather than assumed — comparing `/proc/<pid>/ns/mnt` across the three
processes:

| process | mount namespace |
|---|---|
| a host shell | `mnt:[4026531832]` |
| alacritty (sandboxed) | `mnt:[4026533599]` |
| the spawned `bash -l` | `mnt:[4026531832]` — matches the host |

This is the same trick [Ptyxis](https://gitlab.gnome.org/chergert/ptyxis) uses in
production, via its separately host-spawned `ptyxis-agent`. See
[`Findings.md`](Findings.md) for the full write-up and a comparison with GNOME
Terminal, which has no Flatpak at all.

## Configuration

The shell override ships *inside* the app at `/app/share/alacritty/flatpak.toml`,
and the desktop entry passes it with `--config-file`. That file imports your own
`~/.config/alacritty/alacritty.toml` if you have one; Alacritty merges imports
with the importing file winning, so your fonts, colours and keybindings apply
while the shell override stays in force. A missing import is logged and ignored.

Launching `flatpak run io.github.superuser_miguel.Alacritty` **without**
`--config-file` skips all of that and drops you in a sandbox-trapped shell.

## Build from source

```sh
cd flatpak
flatpak-builder --user --install --force-clean build io.github.superuser_miguel.Alacritty.yml
```

Needs the `org.freedesktop.Sdk.Extension.rust-stable` SDK extension (runtime
`25.08`). Builds Alacritty v0.17.0 from a pinned upstream tag and commit. The
manifest builds with `--share=network` so cargo can fetch crates.io
dependencies; a Flathub-grade package would vendor them instead, which this
deliberately does not attempt to be.

Publishing a release (bundle + signed repo) is `build-aux/publish-repo.sh`.

## Licence

Alacritty is Apache-2.0, © the Alacritty project. The packaging files in this
repo are offered under the same licence.
