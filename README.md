# Linux Preview (DistroStage)

A local Storybook-style proof of concept for running, viewing and validating
Linux desktop applications in an isolated graphical environment.

See [APP_TOUR.md](APP_TOUR.md) for the complete application, component, API,
runtime, and troubleshooting tour.

## Phase 1 — revised

The phase 1 audit found and fixed these divergences from the specification:

| Finding | Change |
| --- | --- |
| `startxfce4` started a full desktop session (`xfce4-session`, `xfdesktop`, Thunar, session and power services) that does not render the application | The session now starts only `Xvnc`, `xfwm4`, `xfsettingsd` and `xfce4-panel`, experimentally verified to render the application and its tray |
| The stock panel configuration loaded 11 plugins; only `systray` renders the tested application | The image ships a minimal panel: one expanding separator plus the native systray plugin, committed in the image so the environment is reproducible |
| The stock panel config was generated at first start, not reproducible | The panel config is part of the image |
| The preview had no mechanism to change test conditions | Manual control through `podman exec` is now documented and verified |
| DevLinger discovers containers through a Docker socket, and mounting the host socket is not acceptable | The preview provisions an isolated rootless container engine with private storage and its own socket, verified against the Docker API |

### Verified rendering behavior

- Xfce renders the application natively: StatusNotifierItem icons, DBusMenu
  menus, windows, popups and tooltips.
- Individual components (`xfce4-panel` without a desktop session) work; the
  panel's integrated systray provides `org.kde.StatusNotifierWatcher`.
- The application is never re-created in HTML/CSS; the browser only shows the
  native rendering through VNC.

## Run

Build the application in its own repository, then run the preview:

```sh
cd /home/andre/Projects/dev-linger
CGO_ENABLED=0 go build -o devlinger .

cd /home/andre/Projects/distro-stage
scripts/run-poc.sh /home/andre/Projects/dev-linger/devlinger
```

The application binary must be an executable built for Debian 12. If its
repository is mid-edit, build from a clean checkout instead (`git archive HEAD`
into a scratch directory) — the preview mounts the file read-only and never
touches the source repository.

Open the workbench at <http://127.0.0.1:6081/>. It keeps the native noVNC
rendering of the application beside controls for every fixture server and the
isolated test containers. Start and stop workloads there, then interact with
the application tray, menus and actions in the same page.

Stop the preview with `Ctrl+C`. The script stops test containers, the test
engine, the preview container and its graphic processes; no orphans remain.

## Environment control

The workbench is the primary control surface. It starts with the preview,
shows which fixtures are active, and provides start/stop actions for every
server type plus add/remove actions for isolated test containers.

The same control path remains available from the terminal. The fixture helper
`scripts/preview-fixture.sh` starts and stops test workloads the application
is expected to detect: it finds the running preview and the session's test
engine automatically.

### Fixture servers

The application detects processes by command line plus a TCP listener. The
image ships one generic HTTP server installed under each command-line layout
the application recognizes, so a full detection catalog can be exercised:

```sh
scripts/preview-fixture.sh types                # list types, ports, commands
scripts/preview-fixture.sh start vite           # start (default port)
scripts/preview-fixture.sh start python-http 9000  # custom port
scripts/preview-fixture.sh stop vite
```

Types and default ports: `python-http` 8000, `django` 8001, `uvicorn` 8002,
`gunicorn` 8003, `flask` 5000, `php` 8080, `next` 3000, `nuxt` 3001,
`nestjs` 3002, `remix` 3003, `astro` 4321, `angular` 4200, `vite` 5173,
`storybook` 6006, `expo` 8081.

`start` waits until the port is actually listening and prints the fixture's
log (`/tmp/fixture-<type>.log` inside the preview) when it is not.

### Test containers

```sh
scripts/preview-fixture.sh docker start probe   # busybox in the isolated engine
scripts/preview-fixture.sh docker ls
scripts/preview-fixture.sh docker stop probe
```

Containers run in the preview's isolated rootless engine — never the host
Docker socket — and are automatically removed with the preview session.

### Manual control

| Action | Command |
| --- | --- |
| Open a control shell | `podman exec -it linux-preview-poc bash` |
| Start an auxiliary process | `podman exec -d linux-preview-poc python3 -m http.server 8000` |
| Stop an auxiliary process | use the interactive shell: `Ctrl+C` or `kill %1` |
| Open a browser | inside the shell: `netsurf-gtk http://127.0.0.1:8000 &` |
| Reach the session bus | inside the shell, `DBUS_SESSION_BUS_ADDRESS` is already exported by `/etc/profile.d/preview-session-bus.sh`; run `bash -l` or `exec bash` |
| Call a D-Bus service | `dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames` |
| Reset the environment | stop the preview and run the script again |

## Reference scenarios (DevLinger)

Verified end to end, observing the tray `Title` property and the DBusMenu
layout over D-Bus:

1. Start DevLinger: registered as a StatusNotifierItem on the isolated bus.
2. Five server types at once (`python-http`, `vite`, `next`, `django`,
   `php`): count 0 → 5, one menu entry per service (path + port).
3. Stop `vite`: 5 → 4.
4. Test container `busybox` in the isolated engine: 4 → 5; remove it: 5 → 4.
5. Stop the remaining fixtures: 4 → 0.
6. Browser `netsurf-gtk` fetching a fixture: process runs, app unaffected
   (verified earlier).
7. Stop the preview: no orphan processes, containers or sockets remain.

Menu interaction and icon rendering were additionally checked by hand through
the browser.

## Isolation

- Own Xvnc display, own D-Bus session bus, own `XDG_RUNTIME_DIR`, own
  `~/.config`; the host desktop session and host session bus are untouched.
- The preview engine is a separate `podman system service` with private
  `--root`, `--runroot` and the `vfs` driver. It is distinct from the host
  Podman store and from the host Docker socket, which is never mounted.
- HTTP is published only on `127.0.0.1:6080`; the VNC server binds to
  localhost inside the container.
- Known limitations, verified during the audit:
  - The application sees only processes inside the preview container; host
    dev servers are invisible (they live in a different network namespace).
  - Containers created by the host Podman or Docker are invisible; only the
    isolated engine's containers are observed.
  - The test engine socket is `chmod 666` so the unprivileged preview user can
    reach it; it exposes only the session's test store.
  - Image size is ~687 MB (GTK stack, noVNC, netsurf, Node.js and PHP);
    not yet minimized.

## Requirements

- Linux x86-64
- Podman
- An executable compatible with Debian 12

## Out of scope in this phase

Definitive dashboard, definitive CLI, stories, plugins, visual comparison,
visual regression, hot reload, concurrent sessions, multi-distribution
support, and abstractions for unproven future requirements.

## Roadmap

- Phase 2 (Core): Go CLI and HTTP API replacing the shell script, process and
  session management, logs, restart.
- Phase 3 (Environments): LXQt profile using the same minimal-component
  approach (one compositor, one panel, one applet host), side-by-side
  rendering differences.
- Deferred until needed: profile files, snapshot/restore of environment
  state, richer browsers than netsurf.
