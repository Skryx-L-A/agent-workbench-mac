# Installing the Mac shell

Two builds: this repository's Swift package, and the headless core it drives. Roughly twenty
minutes if the core is not built yet, five if it already is.

If you would rather not do it by hand, hand this file to a coding agent and tell it to work
through the steps.

## 0. What has to be there first

```bash
xcode-select --install   # the Swift 6.2 toolchain; a full Xcode install also works
```

macOS 26 or newer — `sw_vers` says which one you have. You also need git, and a network connection
for the first build: SwiftPM fetches SwiftTerm and Highlightr from GitHub.

## 1. Get the core

This repository does not carry the headless core (`app/`); it drives it over a socket. Clone and
build agent-workbench next to this checkout, so both share one parent directory:

```bash
cd ..
git clone https://github.com/<your-github-user>/agent-workbench.git
cd agent-workbench/app
npm ci
npm run build
cd ../..
```

Follow that repository's own INSTALL.md for anything beyond the build — the model registry, the
command-line tools, the role prompts. None of it is required just to start this shell.

## 2. Get this repository

```bash
git clone https://github.com/<your-github-user>/agent-workbench-mac.git
cd agent-workbench-mac
```

After step 1 and this step, the two checkouts sit side by side:

```
some-directory/
├── agent-workbench/
│   └── app/            built in step 1
└── agent-workbench-mac/
    └── ...              this checkout
```

That layout is not a requirement, only the default the next two steps look for on their own —
Section 5 says how to point at a different one.

## 3. Build the shell

```bash
bin/bauen
```

Compiles both products with SwiftPM (`--debug` for a debug build), then assembles
`build/Werkbank.app`: the executable, SwiftTerm's resource bundle, an `Info.plist`, and an ad-hoc
signature so macOS 26 will run it. `bin/bauen` is the only supported way to get the bundle — a
plain `swift build` alone leaves the pieces separate.

## 4. Install it

```bash
bin/installieren
```

Copies the bundle to `/Applications/Werkbank.app`, re-signs it, and registers it with Launch
Services so Spotlight and the Dock see it right away. Run this again after every rebuild; the
bundle carries its program inside itself, so it does not update on its own the way a checkout does.

While it runs, it also looks for the core you built in step 1 — first next to this checkout as
`../app`, then one level further as the sibling checkout from step 1, matching the layout in step 2
— and remembers whichever one it finds so the shell does not have to search for it every time it
starts. If neither is there yet, it says so and installs anyway; Section 5 covers what to do then.

## 5. Start it

A double-click on `/Applications/Werkbank.app`, or from Spotlight, starts the shell, which then
starts the core itself. The first launch after step 4 can take a few seconds longer while the core
comes up.

If it opens with no sessions and no error, but nothing ever connects, the core was not where step 4
expected it. Set the path by hand — replace the example with wherever you built it in step 1:

```bash
mkdir -p ~/.claude/workbench
cat > ~/.claude/workbench/settings.json <<'JSON'
{"macKernPfad": "/absolute/path/to/agent-workbench/app"}
JSON
```

(If that file already holds other settings, add the key instead of replacing the file.) Quit and
reopen the shell afterwards.

There is also a script-driven path, useful in a terminal or from a check rather than the Finder:

```bash
bin/starten --kopflos    # starts core and shell with no window on screen
bin/starten --stop       # stops both and cleans up sockets and PID files
bin/starten --status     # reports what is currently running
```

## 6. The control channel

`awbmac-ctl` is a dependency-free client for the shell's control socket, the Mac counterpart to the
core's own control client:

```bash
build/awbmac-ctl ping    # {"ok":true, ...} once the shell is up
build/awbmac-ctl quit    # asks the shell to shut down cleanly, core included
```

It finds the running shell's socket on its own; `AWBMAC_CONTROL_SOCKET` or `--socket <path>`
override that when more than one instance is running at once.

## Where things end up

| Path | What |
|---|---|
| `/Applications/Werkbank.app` | the installed shell |
| `~/.claude/workbench/settings.json` | `macKernPfad` and the other settings the shell and the core share |
| ~/.config/agent-workbench/mac-lauf/ | the running shell's sockets, PID files and core log |

## Honest limitations

Nothing here installs the core's own tools, rules or model registry — that is agent-workbench's
INSTALL.md, step 1 above only builds what this shell needs to find a core to talk to. Sending mail,
hooks, skills and the knowledge base live in agent-setup, a separate repository this shell does not
need at all.
