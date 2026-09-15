# agent-workbench-mac

A native macOS shell for the agent workbench: SwiftUI and AppKit instead of a window around a
browser engine. It drives the same headless core the Electron window drives — same sessions, same
worker panes, same control channel — through a small wire protocol instead of Node's IPC. Terminal
panes render with SwiftTerm; the editor's syntax highlighting comes from Highlightr.

## This repository is the Mac shell alone

It carries the Swift package and nothing else — no core, no agent rules, no skills. The headless
core (`app/`) it drives lives in a second public repository,
**[agent-workbench](https://github.com/<your-github-user>/agent-workbench)**, and has to be built
there first; INSTALL.md says how. The wider setup around all of it — rules, skills, hooks, the
knowledge base — is a third repository,
**[agent-setup](https://github.com/<your-github-user>/agent-setup)**. All three are built from the
same private source tree by the same script, so they never drift apart.

Take this one if you are on a Mac and want the native shell instead of the Electron window. Take
agent-workbench on its own on Linux, or if you would rather not build a second program to get the
same sessions.

`<your-github-user>` stands for the account these repositories are hosted under. It is a
placeholder on purpose: the tool that extracts this repository from a working machine removes
account names everywhere, and it cannot tell the account in a public URL from the one on the
machine. The address bar you cloned from shows which one it is.

## What is in here

```
Package.swift            the SwiftPM manifest: two executables (Werkbank, awbmac-ctl), one
                          library (WerkbankProtokoll), 2 pinned dependencies
Sources/Werkbank/         the shell itself — windows, sidebar, terminal panes, the editor
Sources/WerkbankProtokoll/  the wire protocol the shell and the core speak to each other
Sources/awbmac-ctl/       a dependency-free CLI that talks to the running shell over a socket,
                          the Mac counterpart to the core's own awb-ctl
assets/                   the drawn app icon, source for the rendered .icns
bin/                      4 scripts: build, install, start, and the control client
                          wrapper — nothing here runs without them
INSTALL.md                how to put all of it on your machine
```

63 Swift files in total.

## What is deliberately not in here

None of this is missing by accident, and none of it is needed to build or run the shell:

- **Tests** (`Tests/`, and the two `testTarget` entries `Package.swift` would otherwise carry) —
  they live in the source tree this repository is built from, and a `Tests/`-less package would
  not resolve them anyway.
- **The headless core** (`app/`) — it is a separate program with its own build, shared with the
  Electron window, and lives in
  **[agent-workbench](https://github.com/<your-github-user>/agent-workbench)**.
- **Acceptance and demo tooling** (`abnahme-welten`, `demo-welt`, `demo-skills`) — they check or
  show a *running* shell; they are not part of running one.
- **Agent rules, skills, hooks, the knowledge base** — the wider setup around the workbench family,
  in **[agent-setup](https://github.com/<your-github-user>/agent-setup)**.

## What you have after installing

- **A real application bundle**, `/Applications/Werkbank.app`, launchable from Spotlight, the Dock
  or a double-click in the Finder — not a wrapper around a source checkout.
- **The shell starts its own core.** Point it at a built agent-workbench checkout once, and a
  launch from the Finder brings the core up with it; no terminal has to be open first.
- **A control channel**, `awbmac-ctl`, for scripting and for checks that drive the shell without a
  human clicking through it.

## Requirements

| Needed | Why |
|---|---|
| macOS 26 | `Package.swift` pins the platform; the shell uses current SwiftUI and AppKit |
| Xcode or the Swift 6.2 toolchain | `swift build` is enough — a full Xcode install is not required |
| A network connection, the first build | SwiftPM fetches SwiftTerm and Highlightr from GitHub |
| A built core from agent-workbench (`werkbank` scope) | this repository drives it; it does not carry it |

## Honest limitations

- **The comments are in German.** They work as they are; translating `Sources/` is a mechanical
  pass for any agent, same as the other two repositories in this family.
- **Nothing here works without a core.** Build agent-workbench first — INSTALL.md says where it
  has to sit relative to this checkout for the shell to find it on its own, and how to point it at
  a different location if that layout does not suit you.
- **macOS only.** This is a native AppKit and SwiftUI program; there is no equivalent on Linux or
  Windows. Use agent-workbench there — the Electron window runs the same sessions.
- **Any file that names a tool this repository does not carry says so** in a note at the end, added
  while the repository was built. Nothing has to be cross-checked by hand.

## Getting started

Read [INSTALL.md](INSTALL.md). Handing that file to a coding agent and telling it to work through
the steps is a reasonable way to do it.

## License

AGPL-3.0-only. See [LICENSE](LICENSE).
