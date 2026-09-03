# omarchy-globalprotect — GlobalProtect for the Omarchy bar

A bar indicator for a GlobalProtect VPN: connect, disconnect and switch profiles
without opening a terminal, with live state and a notification when the tunnel
drops.

## Requires the backend

This repo is **only the widget**. Every bit of real work — the SAML login, the
tunnel, the systemd unit, the polkit rule — is done by the `gpvpn` CLI, which
lives on its own:

**[Unnunoctio/gpvpn](https://github.com/Unnunoctio/gpvpn)**, version `0.1.0` or newer.

The widget implements no VPN logic, touches no systemd, and reads none of the
backend's files. It talks to the CLI **by process**: `gpvpn status --json` for
state, and the subcommands to act. That JSON schema is documented in the
backend's README and is the contract between the two.

If `gpvpn` is missing or older than the minimum, the panel says so instead of
failing in strange ways.

## Installation

```bash
./install.sh
omarchy plugin enable unnunoctio.globalprotect right
```

`install.sh` copies the QML and reports whether the backend is missing or out of
date. The widget can also be installed straight from git, which copies only the
QML:

```bash
omarchy plugin add https://github.com/Unnunoctio/omarchy-globalprotect
```

> The shell reloads QML on save but does **not** re-instantiate widgets already
> mounted in the bar. Structural changes need `omarchy restart shell`.

## What it does

- **Bar icon.** The shield is filled while the VPN is up, a faint outline when it
  is down, and pulses while negotiating. Hovering shows profile, IP and uptime
  without opening anything.
- **Mouse.** Left click opens the panel, right click connects or disconnects,
  middle click refreshes.
- **One switch per profile.** Flipping the active profile's switch takes the
  tunnel down; flipping another one switches to it. The filled dot marks the
  active profile. The switch turns on as soon as the connection is requested,
  not only once the tunnel is up.
- **Profile management.** `+` in the header creates a profile; the pencil on each
  row opens it for editing, preloaded. Each row can also be set as default or
  deleted, with confirmation. The connected profile offers no delete — take it
  down first.
- **Connection details.** While connected the panel shows server (or portal and
  gateway, in portal mode), interface, IP and how long it has been up.
- **Notifications** on connect, on failure, and when the tunnel drops by itself.
  A disconnect you asked for, or a profile switch, stays quiet. So does a slow
  negotiation: the backend reports that as *in progress*, not as a failure.

## Keyboard

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move the cursor |
| `enter` | Activate the row under the cursor |
| `n` | New profile |
| `e` | Edit the profile under the cursor |
| `d` | Set it as default |
| `x` | Delete it, with confirmation |
| `t` | Connect / disconnect |
| `r` | Refresh |
| `g` | Open the tunnel logs |
| `esc` | Close the form, the dialog, or the panel |

`h`/`j`/`k`/`l` are consumed by the panel's keyboard navigator as arrows, which
is why the logs live on `g`.

## Settings

In `shell.json`, under the widget's entry:

| Key | Default | What it does |
|---|---|---|
| `refreshIntervalSec` | `15` | How often the panel polls `gpvpn status` |
| `notifyOnDisconnect` | `true` | Notify when the tunnel drops on its own |

## What the widget deliberately does not do

These live in the backend, on purpose:

| | Where |
|---|---|
| A profile's `interface` and `extraArgs` | `~/.config/gpvpn/profiles.json`, or `gpvpn profile edit` |
| Installing the systemd unit and polkit rule | `gpvpn setup`, or the package |
| Anything that needs root | The `gpvpn@<uid>` unit, via polkit |

The panel's form covers what gets changed often; the rest is an escape hatch that
does not deserve a row.

## Components

| File | What it does |
|---|---|
| `plugin/Panel.qml` | The bar widget and the panel: rows, form, dialogs, keyboard |
| `plugin/Service.qml` | State and actions: polls the CLI, decides when to notify |
| `plugin/ShieldIcon.qml` | The shield, drawn as a `Shape` (small SVGs render poorly in the bar) |
| `plugin/manifest.json` | Plugin metadata and the declared backend dependency |

## Requirements

Omarchy with its Quickshell shell, and
[`gpvpn`](https://github.com/Unnunoctio/gpvpn) `>= 0.1.0`.

Optional: `libnotify` for desktop notifications, `foot` for the logs shortcut.
Both are used by the widget, not by the backend.

## License

MIT. See [LICENSE](LICENSE).
