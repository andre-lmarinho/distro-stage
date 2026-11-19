#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <executable> [arguments...]" >&2
    exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
    echo "Podman is required to run Linux Preview." >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required to run the control UI." >&2
    exit 1
fi

app_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
app="$app_dir/$(basename -- "$1")"
shift

if [ ! -f "$app" ] || [ ! -x "$app" ]; then
    echo "Application must be an executable file: $app" >&2
    exit 1
fi

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=linux-preview-poc
name=linux-preview-poc
session=${TMPDIR:-/tmp}/distrostage-$$
sock=$session/docker.sock

# Isolated rootless container engine for the containers the tested
# application should observe. Storage and socket are private to this
# preview session; the host Docker socket is never used.
engine_pid=
ui_pid=
run_pid=
cleanup() {
    [ -z "$ui_pid" ] || kill "$ui_pid" 2>/dev/null || true
    [ -z "$ui_pid" ] || wait "$ui_pid" 2>/dev/null || true
    if [ -n "$engine_pid" ] && [ -S "$sock" ]; then
        containers=$(CONTAINER_HOST="unix://$sock" podman ps -q 2>/dev/null || true)
        [ -z "$containers" ] ||
            CONTAINER_HOST="unix://$sock" podman rm -f $containers >/dev/null 2>&1 || true
    fi
    [ -z "$engine_pid" ] || kill "$engine_pid" 2>/dev/null || true
    [ -z "$engine_pid" ] || wait "$engine_pid" 2>/dev/null || true
    rm -rf "$session"
    if [ -n "$run_pid" ]; then
        # pid 1 (dbus-run-session) ignores TERM; cap the wait before SIGKILL.
        podman stop --time 2 "$name" >/dev/null 2>&1 || true
        podman rm -f "$name" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

podman build --file "$repo/poc/Containerfile" --tag "$image" "$repo"
if podman container exists "$name"; then
    owner=$(podman inspect \
        --format '{{ index .Config.Labels "io.distrostage.preview" }}' "$name")
    if [ "$owner" != true ]; then
        echo "Container name '$name' is already used outside DistroStage." >&2
        exit 1
    fi
    podman rm -f "$name" >/dev/null
fi

mkdir -p "$session/root" "$session/runroot"
podman --root "$session/root" --runroot "$session/runroot" --storage-driver vfs \
    system service --time=0 "unix://$sock" &
engine_pid=$!

socket_ready=false
for _ in $(seq 1 50); do
    if [ -S "$sock" ]; then
        # Localhost POC: the container user needs to connect to the socket.
        chmod 666 "$sock"
        socket_ready=true
        break
    fi
    kill -0 "$engine_pid" 2>/dev/null || exit 1
    sleep 0.1
done
[ "$socket_ready" = true ] || {
    echo "Test engine socket did not start." >&2
    exit 1
}

# Run in background and wait with the builtin: a signal received while
# bash waits for an external command would only run the trap after it.
podman run --rm --name "$name" \
    --label io.distrostage.preview=true \
    --publish 127.0.0.1:6080:6080 \
    --security-opt label=disable \
    --volume "$app:/opt/linux-preview/app:ro" \
    --volume "$sock:/home/preview/.run/docker.sock" \
    "$image" \
    /opt/linux-preview/app "$@" &
run_pid=$!

"$repo/scripts/preview-ui" >"$session/control-ui.log" 2>&1 &
ui_pid=$!
ui_ready=false
for _ in $(seq 1 50); do
    if python3 -c \
        'import urllib.request; urllib.request.urlopen("http://127.0.0.1:6081/", timeout=.2)' \
        >/dev/null 2>&1; then
        ui_ready=true
        break
    fi
    kill -0 "$ui_pid" 2>/dev/null || {
        cat "$session/control-ui.log" >&2
        exit 1
    }
    sleep 0.1
done
[ "$ui_ready" = true ] || {
    echo "Control UI did not start." >&2
    exit 1
}

echo "Workbench:      http://127.0.0.1:6081/"
echo "Native preview: http://127.0.0.1:6080/vnc.html?autoconnect=1"
echo "Control shell:  podman exec -it $name bash"
echo "Test engine:    CONTAINER_HOST=unix://$sock podman ps"

wait "$run_pid"
