<h1 align="center">Alacritty — unofficial Flatpak</h1>

<p align="center">
A write-up on why terminal emulators are hard to sandbox — with a working
reference implementation.
</p>

This repo is primarily **educational**. The question it answers is a real one:
*why is there no Flatpak of Alacritty, and what would it take?* The answer turns
out to be architectural rather than a packaging oversight, and it is the same
problem [Ptyxis](https://gitlab.gnome.org/chergert/ptyxis) solves with a
host-spawned agent and that GNOME Terminal's design cannot solve at all.

[**`Findings.md`**](Findings.md) is the write-up and the point of the repo. The
Flatpak manifest alongside it is the reference implementation — something you
can read, build, and verify the claims against, rather than a product.

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

## The sandbox problem

A Flatpak'd terminal either runs your shell *inside* the sandbox — trapping you
in the runtime's filesystem rather than your real system — or punches a hole to
the host to spawn processes there. Upstream's objection is that both outcomes
are bad, so terminals are a poor fit for the model on principle.

This build takes the second path, using the mechanism an Alacritty maintainer
suggested in passing: override `terminal.shell` so the shell is launched on the
host. The GPU and UI process stay sandboxed; the shell session runs on the host.

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

## The part everyone gets wrong

Getting the shell onto the host is the easy half, and it is where most write-ups
about `flatpak-spawn` stop. The half nobody mentions is that `flatpak-spawn`
hands the **controlling terminal** to the proxy rather than to your shell.

`TIOCSCTTY` is an exclusive, one-shot claim: the first session to grab a PTY owns
it permanently. Alacritty does the textbook thing — `setsid()` + `TIOCSCTTY` in
its child, then `exec` — but that child is `flatpak-spawn`, which only makes a
D-Bus call. The proxy performs the land grab; the real shell is spawned
separately by the portal and arrives to find the terminal taken. It starts with
no controlling terminal at all:

```
1824071  flatpak-spawn --host bash -l   pts/0  Ssl+    <- proxy owns the terminal
1824076  bash -l                        ?      Ss      <- the actual shell
```

So `Ctrl+Z`, `fg`, `bg` and `jobs` silently stop working, `tty` cannot name your
terminal, and window resizes never reach anything running in the shell.

This build fixes it with [`flatpak/alacritty-host-shell`](flatpak/alacritty-host-shell),
a ~60-line PTY relay that opens a second PTY and **deliberately never claims
it** — which lets the portal hand it to the shell, where it belongs. The relay
also forwards `SIGWINCH`, which `flatpak-spawn` does not, so live resize works.

📄 **[The sandboxed terminal that lost its job control](https://superuser-miguel.github.io/alacritty-flatpak/pty-job-control.html)**
— the full debugging write-up, with measurements and reproduction steps.

## Configuration

The shell override ships *inside* the app at `/app/share/alacritty/flatpak.toml`,
and the desktop entry passes it with `--config-file`. That file imports your own
`~/.config/alacritty/alacritty.toml` if you have one; Alacritty merges imports
with the importing file winning, so your fonts, colours and keybindings apply
while the shell override stays in force. A missing import is logged and ignored.

Launching `flatpak run io.github.superuser_miguel.Alacritty` **without**
`--config-file` skips all of that and drops you in a sandbox-trapped shell.

## Try it

Building it yourself (below) is the honest way to verify any of the above. If
you just want the artifact to poke at, a `.flatpak` bundle is on
[Releases](https://github.com/superuser-miguel/alacritty-flatpak/releases/latest):

```sh
flatpak install --user ./Alacritty.flatpak
flatpak run io.github.superuser_miguel.Alacritty
```

There is also a signed repo, if you would rather `flatpak update` track it:

```sh
flatpak install --user https://superuser-miguel.github.io/alacritty-flatpak-repo/alacritty.flatpakref
```

Both need the Flathub remote configured for the `org.freedesktop.Platform//25.08`
runtime. To confirm the host-shell claim on your own machine, launch it and
compare `readlink /proc/<pid>/ns/mnt` for the `alacritty` process against the
`bash -l` it spawns.

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
