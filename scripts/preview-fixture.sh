#!/bin/sh
# Start and stop test workloads for the application running in the preview.
# Fixture servers are generic HTTP servers; only their command lines and
# ports differ. Test containers run in the preview's isolated engine.
set -eu

name=linux-preview-poc

usage() {
    echo "Usage: $0 types" >&2
    echo "       $0 start <type> [port]" >&2
    echo "       $0 stop <type>" >&2
    echo "       $0 docker start [name] | docker stop <name> | docker ls" >&2
    exit 1
}

[ "$#" -ge 1 ] || usage
command="$1"
shift

require_session() {
    podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name" || {
        echo "Preview is not running. Start it with scripts/run-poc.sh first." >&2
        exit 1
    }
}

engine_sock() {
    local s
    s=$(ls -td "${TMPDIR:-/tmp}"/distrostage-*/docker.sock 2>/dev/null | head -1)
    [ -n "$s" ] || { echo "No preview engine found. Is the preview running?" >&2; exit 1; }
    printf '%s' "$s"
}

types() {
    cat <<'EOF'
python-http  8000   python3 -m http.server <port>
django       8001   python3 /opt/fixtures/manage.py runserver
flask        5000   python3 /bin/flask run
uvicorn      8002   python3 /bin/uvicorn <port>
gunicorn     8003   python3 /bin/gunicorn <port>
php          8080   php -S 0.0.0.0:<port>
next         3000   node /opt/fixtures/node_modules/next/dist/bin/next dev
nuxt         3001   node /opt/fixtures/node_modules/nuxt/bin/nuxt.mjs dev
nestjs       3002   node /opt/fixtures/node_modules/@nestjs/cli/bin/nest.js start
remix        3003   node /opt/fixtures/node_modules/@remix-run/dev/dist/cli.js dev
astro        4321   node /opt/fixtures/node_modules/astro/astro.js dev
angular      4200   node /opt/fixtures/node_modules/@angular/cli/bin/ng.js serve
vite         5173   node /opt/fixtures/node_modules/vite/bin/vite.js dev
storybook    6006   node /opt/fixtures/node_modules/storybook/dist/bin/dispatcher.js dev
expo         8081   node /opt/fixtures/node_modules/expo/bin/cli start
EOF
}

start_command() {
    # echo "<default port>|<stop pattern>|<command template>"
    # The pipe separator is required: patterns may contain spaces
    # ("php -S", "-m http.server").
    case "$1" in
        python-http) echo "8000|-m http.server|python3 -m http.server {port}";;
        django) echo "8001|/opt/fixtures/manage.py|python3 /opt/fixtures/manage.py runserver";;
        flask) echo "5000|/bin/flask|python3 /bin/flask run";;
        uvicorn) echo "8002|/bin/uvicorn|python3 /bin/uvicorn {port}";;
        gunicorn) echo "8003|/bin/gunicorn|python3 /bin/gunicorn {port}";;
        php) echo "8080|php -S|php -S 0.0.0.0:{port}";;
        next) echo "3000|dist/bin/next|node /opt/fixtures/node_modules/next/dist/bin/next dev";;
        nuxt) echo "3001|nuxt/bin/nuxt.mjs|node /opt/fixtures/node_modules/nuxt/bin/nuxt.mjs dev";;
        nestjs) echo "3002|cli/bin/nest.js|node /opt/fixtures/node_modules/@nestjs/cli/bin/nest.js start";;
        remix) echo "3003|remix-run/dev/dist/cli.js|node /opt/fixtures/node_modules/@remix-run/dev/dist/cli.js dev";;
        astro) echo "4321|astro/astro.js|node /opt/fixtures/node_modules/astro/astro.js dev";;
        angular) echo "4200|cli/bin/ng.js|node /opt/fixtures/node_modules/@angular/cli/bin/ng.js serve";;
        vite) echo "5173|vite/bin/vite.js|node /opt/fixtures/node_modules/vite/bin/vite.js dev";;
        storybook) echo "6006|storybook/dist/bin/dispatcher.js|node /opt/fixtures/node_modules/storybook/dist/bin/dispatcher.js dev";;
        expo) echo "8081|expo/bin/cli|node /opt/fixtures/node_modules/expo/bin/cli start";;
        *) echo "Unknown type: $1. See: $0 types" >&2; exit 1;;
    esac
}

kill_by_pattern() {
    # The pattern is passed as an argument: patterns contain spaces, and a
    # case glob built by string interpolation would break on them. The kill
    # shell excludes itself: /proc globs sort lexicographically, so it can
    # appear before its targets.
    podman exec "$name" bash -c '
        pat=$1
        for d in /proc/[0-9]*; do
            p=${d##*/}; [ "$p" = "$$" ] && continue
            c=$(tr "\0" " " <"$d/cmdline" 2>/dev/null || true)
            case "$c" in *"$pat"*) kill "$p" 2>/dev/null;; esac
        done' _ "$1" || true
}

case "$command" in
    types)
        types
        ;;
    start)
        [ "$#" -ge 1 ] || usage
        type_="$1"; port="${2:-}"
        spec=$(start_command "$type_")
        default_port=$(echo "$spec" | cut -d'|' -f1)
        pattern=$(echo "$spec" | cut -d'|' -f2)
        template=$(echo "$spec" | cut -d'|' -f3-)
        case "${port:-$default_port}" in
            '' | *[!0-9]*) echo "Invalid port: $port" >&2; exit 1;;
        esac
        port="${port:-$default_port}"
        require_session
        # stop a previous instance of the same type first
        kill_by_pattern "$pattern"
        podman exec -d -e FIXTURE_PORT="$port" "$name" sh -c \
            "$(echo "$template" | sed "s/{port}/$port/g") >/tmp/fixture-$type_.log 2>&1"
        # the listener is what the application detects; wait for it
        listening=false
        for _ in $(seq 1 50); do
            if podman exec "$name" awk -v p="$port" '
                BEGIN { hex = sprintf("%04X", p) }
                NR > 1 && $4 == "0A" && $2 ~ (":" hex "$") { found = 1 }
                END { exit !found }' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
                listening=true
                break
            fi
            sleep 0.2
        done
        if [ "$listening" = true ]; then
            echo "Started $type_ on port $port."
        else
            echo "Warning: $type_ is not listening on $port; log follows." >&2
            podman exec "$name" cat "/tmp/fixture-$type_.log" 2>/dev/null >&2 || true
            exit 1
        fi
        ;;
    stop)
        [ "$#" -ge 1 ] || usage
        type_="$1"
        pattern=$(start_command "$type_" | cut -d'|' -f2)
        require_session
        kill_by_pattern "$pattern"
        echo "Stopped $type_."
        ;;
    docker)
        [ "$#" -ge 1 ] || usage
        action="$1"; shift
        s=$(engine_sock)
        case "$action" in
            start)
                cname="${1:-probe}"
                CONTAINER_HOST="unix://$s" podman run --detach \
                    --name "$cname" busybox sleep 600
                echo "Test container '$cname' started."
                ;;
            stop)
                [ -n "${1:-}" ] || usage
                CONTAINER_HOST="unix://$s" podman rm -f "$1" >/dev/null
                echo "Test container '$1' removed."
                ;;
            ls)
                CONTAINER_HOST="unix://$s" podman ps \
                    --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
                ;;
            *) usage;;
        esac
        ;;
    *) usage;;
esac
