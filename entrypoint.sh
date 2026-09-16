#!/bin/bash
set -e

SPEEDIFY=/usr/share/speedify
SPEEDIFY_UI=/usr/share/speedifyui/speedify_ui

cleanup() {
    echo "Stopping Speedify..."

    pkill -f speedify_ui_webkit60 2>/dev/null || true
    "$SPEEDIFY/SpeedifyShutdown.sh" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

cd "$SPEEDIFY"

echo "Starting Speedify..."
./SpeedifyStartup.sh

echo "Waiting for daemon..."
sleep 3

echo "Initial state:"
./speedify_cli state

echo "Starting Speedify UI..."

"$SPEEDIFY_UI" &

echo "Connecting Speedify..."
./speedify_cli connect >/dev/null

echo "Waiting for VPN..."

CONNECTED=false

for i in {1..120}; do
    STATE=$(./speedify_cli state 2>/dev/null || true)

    CURRENT=$(printf '%s\n' "$STATE" |
        sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    printf 'Speedify state: %s\n' "${CURRENT:-UNKNOWN}"

    if [ "$CURRENT" = "CONNECTED" ]; then
        echo "VPN connected."

        sleep 10

        STATE=$(./speedify_cli state 2>/dev/null || true)

        CURRENT=$(printf '%s\n' "$STATE" |
            sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

        if [ "$CURRENT" = "CONNECTED" ]; then
            CONNECTED=true
            echo "VPN remained connected for 10 seconds."
            break
        fi

        echo "Connection dropped back to $CURRENT; continuing to wait..."
    fi

    sleep 1
done

if [ "$CONNECTED" != true ]; then
    echo "ERROR: Speedify failed to establish a stable VPN connection."
    exit 1
fi

echo "Starting Firefox..."

# Firefox deliberately remains in the foreground.
# Its lifetime controls the lifetime of the container.
firefox-esr
