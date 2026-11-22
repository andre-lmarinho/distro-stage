# DistroStage

DistroStage runs a Linux application in a graphical test session. It shows the
native display in a local browser and lets you change test workloads.

## Current state

DistroStage is a proof of concept. It uses a Debian 12 image with a minimal
Xfce panel and system tray.

The current preview tests whether an application detects fixture processes and
test containers. Fixture servers use generic HTTP code with process names and
ports from the detection catalog. They do not run the real frameworks.

The preview supports one session and one Debian 12 profile. It does not support
concurrent sessions or other distributions.

See [APP_TOUR.md](APP_TOUR.md) for the full UI, component, API, runtime, and
troubleshooting guide.

## Architecture

- `scripts/run-poc.sh` builds the preview image and starts its container through
  the host Podman engine.
- The runner mounts the application executable read-only in the preview.
- Xvnc and minimal Xfce components render the application. noVNC serves that
  display on `127.0.0.1:6080`.
- The Python workbench listens on `127.0.0.1:6081`. It controls fixture
  processes and test containers.
- A separate rootless Podman service stores test containers in the session
  directory. The preview does not use the host Docker socket.

## Requirements

- A Linux host with Podman.
- Python 3.
- An executable that runs in Debian 12.

## Run

From the DistroStage repository, run:

```sh
cd /path/to/distro-stage
scripts/run-poc.sh /path/to/application [arguments...]
```

The script builds the preview image and starts the session. Open the workbench
at <http://127.0.0.1:6081/>. It shows the native preview beside the workload
controls.

You can also open the native preview directly at
<http://127.0.0.1:6080/vnc.html?autoconnect=1>.

Press `Ctrl+C` in the terminal that runs the script to stop the session. The
runner stops the workbench, test containers, test engine, and preview
container. It also removes the session directory.

## Workload controls

Run these commands from the repository root while the preview is active:

```sh
scripts/preview-fixture.sh types
scripts/preview-fixture.sh start vite
scripts/preview-fixture.sh start python-http 9000
scripts/preview-fixture.sh docker start probe
scripts/preview-fixture.sh docker stop probe
```

The fixture helper lists the available types and ports. It can start a fixture
on its default port or on a custom port. The workbench can also start and stop
fixtures and test containers.

## Isolation and limits

- The tested application sees processes in the preview container, not host
  development servers.
- It sees containers in the session's test engine, not containers in the host
  Podman or Docker engine.
- The preview container runs through host Podman. The test engine has separate
  storage and a session-specific socket.
- The workbench has no authentication and binds to `127.0.0.1`.
- The runner sets the test engine socket mode to `0666` so the preview user can
  use it.
- The runner uses ports `6081` and `6080` and the container name
  `linux-preview-poc`.
- The runner refuses to remove a container with that name unless it has the
  DistroStage ownership label.

The project does not provide a multi-distribution test matrix, concurrent
sessions, or real framework workloads. See [APP_TOUR.md](APP_TOUR.md) for the
full list of current limits and implementation details.
