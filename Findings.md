# Findings: Terminal Emulators, Flatpak, and the Sandbox Problem

Notes from investigating whether Alacritty could be packaged as a Flatpak,
and how Ptyxis and GNOME Terminal actually handle (or avoid) the same
problem.

## The question and reply, verbatim

**Q (user):** "I have Ptyxis terminal, Gnome Terminal and this repo is
alacritty. There has to be a way to have this terminal as a flatpak."

**Reply:** Checked Flathub directly — no listing for Alacritty. This isn't
an oversight; it's a deliberate, repeated refusal from upstream, visible
across several closed GitHub issues:

- **#8770 "implement flatpak packaging support"** — maintainer chrisduerr:
  *"I have no interest in supporting Flatpak."* When someone offered to
  maintain an unofficial Flathub package themselves so upstream wouldn't
  have to touch it, the answer was still no: *"Community maintained
  releases have been proven to just cause issues in the past."*
- **#6474 "Flatpak package on flathub"**, **#5828 "Flatpak/Flathub
  distribution support"**, **#2571 "Alacritty on Flathub"** — all closed,
  same stance.
- **#8628 "Execute commands on the host when running in a flatpak
  sandbox"** — a deeper technical objection from maintainer kchibisov: a
  terminal sandboxed by Flatpak either (a) runs your shell *inside* the
  sandbox, which traps you in the Flatpak runtime's filesystem instead of
  your real system, or (b) has to punch a hole to the host to spawn
  processes there, which undercuts what the sandbox is supposed to buy you.
  His view: terminals (like file managers) are a poor fit for Flatpak's
  model on principle, not just a packaging inconvenience. He also pointed
  out the workaround in passing: *"it could be done in `script` that you
  set for `program.shell`"* — i.e. override Alacritty's configured shell
  command yourself.

So: no official path, and upstream has asked people not to publish
unofficial ones either.

**Clarifying question posed back to the user:** given that stance, three
options — (1) build a private, unpublished local Flatpak just for this
machine, (2) skip Flatpak and install natively, or (3) treat Ptyxis (which
is already a proper Flatpak with working host PTY spawning) as already
solving the underlying want.

**User's answer:** Personal local Flatpak.

**Result:** Built `io.github.superuser_miguel.Alacritty` at
`~/my-progs/alacritty/flatpak/` — compiled from source (v0.17.0) via
flatpak-builder, never published. Solved kchibisov's exact objection using
his own suggested mechanism: Alacritty's `terminal.shell` config option is
set (in a flatpak-only config file, `~/.config/alacritty/flatpak.toml`) to
run `flatpak-spawn --host bash -l` instead of a plain local shell. Verified
for real, not just "should work" — compared `/proc/<pid>/ns/mnt` of the
spawned `bash -l` against the host shell's mount namespace and they
matched, while Alacritty's own GUI/GPU process sits in a distinct bwrap
namespace. GPU rendering stays sandboxed; the actual shell session runs
unconfined on the host.

This is, not coincidentally, the exact same trick Ptyxis uses in
production — see below.

## How Ptyxis actually works

Ptyxis (app-id `app.devsuite.Ptyxis`, formerly "Prompt") is built as **two
processes**, not one:

- **The UI** — a GTK4/libadwaita frontend: windows, tabs, preferences,
  theming, and the VTE terminal widget itself.
- **`ptyxis-agent`** — a separate helper process responsible for the
  lower-level, potentially-host-touching work:
  - Creating and managing PTYs.
  - Talking directly to container runtimes (Podman, Toolbox, etc.) for
    discovery and for spawning processes inside containers.
  - Monitoring host processes and reading system info (shell, OS, proxy
    settings).
  - Communicating with the UI over a `socketpair()`, not a shared address
    space.

**The sandbox-escape mechanism:** when Ptyxis is packaged as a Flatpak, the
UI process is sandboxed as normal, but it launches `ptyxis-agent` on the
**host** using `flatpak-spawn --host`, enabled by the
`--talk-name=org.freedesktop.Flatpak` permission in its `finish-args`. This
isn't theoretical — it's visible live on this machine right now in the
process tree captured while testing the Alacritty build:

```
flatpak-spawn --host --watch-bus --forward-fd=3 \
  /var/lib/flatpak/app/app.devsuite.Ptyxis/.../ptyxis-agent --socket-fd=3 --rlimit-nofile=1024
```

If host-side execution of the agent fails (e.g. glibc/linker
incompatibility between the host and the Flatpak runtime), Ptyxis falls
back to running the agent *inside* its own sandbox — accepting reduced
host-interaction capability rather than crashing.

**Container integration** rides on the same agent: it shells out to
commands like `podman ps --all --format=json` to discover running
containers/toolboxes, then constructs and runs `podman exec -it ...` or
`toolbox enter ...` to open a session inside one, wiring up the PTY and I/O
itself.

Ptyxis's actual Flathub `finish-args` (from the `flathub/app.devsuite.Ptyxis`
manifest repo):

```
--allow=devel
--device=dri
--filesystem=host
--share=ipc
--share=network
--socket=fallback-x11
--socket=wayland
--talk-name=org.freedesktop.Flatpak
```

This is essentially the same shape of permission set used for the personal
Alacritty build — Ptyxis was designed from day one with Flatpak
distribution as a goal, so it built the agent/host-spawn split in as
architecture rather than bolting it on.

## How GNOME Terminal actually works

GNOME Terminal has **no Flatpak at all**, official or otherwise — confirmed
directly: `flathub/org.gnome.Terminal` doesn't exist (404), and there's no
`build-aux/flatpak` manifest anywhere in the GNOME Terminal source tree
either. It isn't that nobody's tried; it's that the app's own architecture
doesn't lend itself to sandboxing without a Ptyxis-style rewrite.

GNOME Terminal uses a **D-Bus-activated server/factory model**, not a
plain "one process per window" design. From its own README:

> "Since GNOME Terminal uses a D-Bus activated server, you cannot simply
> run the self-built gnome-terminal directly."

In practice: `gnome-terminal-server` is the actual long-lived process,
registered under a well-known D-Bus name. The `gnome-terminal` binary
people normally run is a thin client — it just asks the already-running
(or newly D-Bus-activated) server to open a new window or tab inside
itself. All windows/tabs across your whole session typically live inside
one server process.

That architecture is fine on a normal host (D-Bus activation, dconf, and
process spawning are all just host-native operations) but doesn't map onto
Flatpak's sandbox model at all: there's no separate host-facing agent to
punch through the sandbox with, the way Ptyxis has. Sandboxing it properly
would mean the same kind of split-process redesign Ptyxis did — the
GNOME project chose to build that as a new app instead of retrofitting
GNOME Terminal, which is a large part of *why Ptyxis exists* as a distinct
project rather than GNOME Terminal simply growing Flatpak support.

## Summary comparison

| | Sandboxed itself? | Shell/PTY execution | Flathub? |
|---|---|---|---|
| **GNOME Terminal** | No — plain host process, D-Bus-activated server/client | Directly on host, no agent split | No, and no manifest exists anywhere |
| **Ptyxis** | Yes — GTK4 UI in Flatpak sandbox | Separate `ptyxis-agent`, host-spawned via `flatpak-spawn --host` | Yes, official |
| **Alacritty (this personal build)** | Yes — same bwrap sandbox as any Flatpak | Login shell host-spawned via `flatpak-spawn --host` (config-level override, no agent process needed since Alacritty already lets you override `terminal.shell`) | No — personal-only, per upstream's explicit request not to publish |

```Thanks ! I'll do some research into this build and the other terminals too.                                                                                                                 

● Sounds good — everything's in place if you want to come back to it: the build and manifest at ~/my-progs/alacritty/flatpak/, the write-up at ~/my-progs/alacritty/Findings.md, and your
  flatpak-only shell config at ~/.config/alacritty/flatpak.toml. Happy to dig further into any of the three terminals' internals whenever you're ready.

✻ Brewed for 4s

❯ "and your flatpak-only shell config at ~/.config/alacritty/flatpak.toml"                                                                                                                    

● That's the small standalone config file created earlier specifically for the Flatpak build — separate from any future native alacritty.toml so the two never collide. Current contents:

  Read 1 file (ctrl+o to expand)

● It's just one setting: terminal.shell tells Alacritty what to launch instead of your default shell. Here it launches flatpak-spawn --host bash -l, which is the trick that makes the
  sandboxed Alacritty actually usable — without it, bash would run trapped inside the Flatpak's sandbox filesystem instead of your real machine.

  It's only wired in because the app's .desktop launcher passes --config-file /home/definitive_group/.config/alacritty/flatpak.toml explicitly (covered in the Findings.md write-up) — running
  flatpak run io.github.superuser_miguel.Alacritty directly would skip it and fall back to a plain, sandbox-trapped shell.

  If you want to add your own settings (font, colors, keybindings, etc.) for the flatpak build specifically, this is the file to edit — it'll persist across rebuilds since it lives outside
  the Flatpak itself.```

---

# Addendum (2026-07-26): the `flatpak-spawn` trick is not enough

Everything above stands — the shell really does run on the host, verified by
mount namespace. But "runs on the host" and "is a working terminal session" turn
out to be different claims, and the original verification only established the
first.

The symptom, present since the very first build and missed for months because
the terminal *looks* fine:

```
bash: cannot set terminal process group (-1): Inappropriate ioctl for device
bash: no job control in this shell
tty: ttyname error: No such device
```

**Cause.** `TIOCSCTTY` is an exclusive, one-shot claim — the first session to
grab a PTY owns it permanently. Alacritty does the textbook thing (`setsid()` +
`TIOCSCTTY` in its child, then `exec`), but under Flatpak that child is
`flatpak-spawn`, a proxy that only makes a D-Bus call. The proxy performs the
land grab. The real shell is spawned separately by the portal, in a different
process tree, and by then the terminal is taken — so it starts with no
controlling terminal at all (`tty_nr` = 0 in `/proc/<pid>/stat`) and disables
job control. `Ctrl+Z`, `fg`, `bg` and `jobs` are all gone. `Ctrl+C` survives
only because `flatpak-spawn` separately forwards eight signals over the portal —
`SIGWINCH` is not one of them, so live window resize never reaches anything
running in the shell either.

The `ttyname()` failure is a second, unrelated bug: the sandbox gets a private
devpts instance (`0:158` versus the host's `0:28`), so the PTY has no device
node the host can name.

**Fix.** Subtraction, not addition. The portal's own child setup already gives
the host process a controlling terminal automatically — but only if the terminal
is free. So the app now ships `flatpak/alacritty-host-shell`, a ~60-line PTY
relay that opens a second PTY and deliberately never claims it, puts the outer
terminal in raw mode, runs `flatpak-spawn --host bash -l` on the inner slave, and
forwards `SIGWINCH` (which it receives, being the foreground process group of the
outer PTY). `python3` is in the freedesktop Platform runtime, so there is no host
dependency. Adding `--device=all` to `finish-args` puts the sandbox on the host's
devpts, which restores `tty`, `who` and utmp; it grants nothing new given the app
already holds `--talk-name=org.freedesktop.Flatpak`.

`script(1)` — the workaround an Alacritty maintainer suggested in passing, quoted
earlier in this document — cannot do the job: Fedora no longer installs it, and
it claims the controlling terminal in its own child regardless, which reproduces
the bug one layer down.

The full debugging write-up, with measurements and reproduction steps, is at
<https://superuser-miguel.github.io/alacritty-flatpak/pty-job-control.html>.

This also sharpens the upstream argument quoted at the top of this document.
kchibisov's objection was that a sandboxed terminal either traps the shell or
punches a hole to the host. The truer statement is narrower and harder: sessions,
process groups and controlling terminals are kernel-global, single-owner objects,
and they do not survive being split across two process trees. That is why Ptyxis
needed a whole host-side agent rather than a config option.

