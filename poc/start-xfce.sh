#!/bin/bash
set -euo pipefail

if (( $# == 0 )); then
    echo "An application executable is required." >&2
    exit 1
fi

vnc_pid=
wm_pid=
settings_pid=
panel_pid=
websockify_pid=
app_pid=

cleanup() {
    trap - EXIT INT TERM
    kill ${app_pid:-} ${websockify_pid:-} ${panel_pid:-} ${settings_pid:-} \
        ${wm_pid:-} ${vnc_pid:-} 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Publish the session bus address for control shells (podman exec).
printf '%s\n' "${DBUS_SESSION_BUS_ADDRESS-}" > "$XDG_RUNTIME_DIR/bus-address"

bus_has_name() {
    dbus-send \
        --session \
        --dest=org.freedesktop.DBus \
        --type=method_call \
        --print-reply \
        / \
        org.freedesktop.DBus.ListNames 2>/dev/null |
        grep -Fq "string \"$1\""
}

Xvnc "$DISPLAY" \
    -AlwaysShared \
    -depth 24 \
    -geometry 1280x800 \
    -localhost yes \
    -SecurityTypes None &
vnc_pid=$!

for _ in {1..50}; do
    [[ -S /tmp/.X11-unix/X0 ]] && break
    kill -0 "$vnc_pid" 2>/dev/null || exit 1
    sleep 0.1
done
[[ -S /tmp/.X11-unix/X0 ]]

# Minimal native environment: only the components that render the
# application, no desktop session, file manager or desktop background.
xfwm4 --compositor=off &
wm_pid=$!
xfsettingsd &
settings_pid=$!
xfce4-panel &
panel_pid=$!

# The panel's systray plugin provides org.kde.StatusNotifierWatcher.
watcher_ready=false
for _ in {1..50}; do
    if bus_has_name org.kde.StatusNotifierWatcher; then
        watcher_ready=true
        break
    fi
    kill -0 "$panel_pid" 2>/dev/null || exit 1
    sleep 0.2
done
[[ "$watcher_ready" == true ]]

websockify --web=/usr/share/novnc 6080 localhost:5900 &
websockify_pid=$!

"$@" &
app_pid=$!

printf 'Linux Preview is ready at http://127.0.0.1:6080/vnc.html?autoconnect=1\n'
wait -n "$vnc_pid" "$wm_pid" "$settings_pid" "$panel_pid" "$websockify_pid" "$app_pid"
