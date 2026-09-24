#!/usr/bin/env bash
# AW resolve + helpers tmux. Servidor falso local (determinista).

H="$TDO_HUB"
fail=0
PORT=18923

cat > "$H/.env" <<EOF2
HUB_ROOT="$H"
NOTES_DIR="$TDO_TMP/vault"
SESSION="tdo-test-session"
AW_SERVER_URL="http://127.0.0.1:9"
AW_DEFAULT_SERVER="http://127.0.0.1:9"
AW_FALLBACK_URL="http://127.0.0.1:9"
AW_FALLBACK_SERVER="http://127.0.0.1:$PORT"
EOF2

# Fake AW: cualquier path devuelve 200
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
FAKE_PID=$!

# Esperar a que el puerto escuche de verdad (evita race)
ready=0
for _ in $(seq 1 40); do
    if curl -sL --connect-timeout 1 -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 0.25
done
if [[ "$ready" != "1" ]]; then
    echo "  ✗ fake AW no levantó en :$PORT"
    kill "$FAKE_PID" 2>/dev/null
    echo "RESULT fail=1"
    exit 1
fi

got=$(bash -c "source '$H/core.sh' >/dev/null 2>&1; resolve_aw_api 2>/dev/null")
kill "$FAKE_PID" 2>/dev/null

if [[ "$got" == "http://127.0.0.1:$PORT" ]]; then
    echo "  ✓ resolve salta muertos y elige el vivo"
else
    echo "  ✗ resolve salta muertos y elige el vivo (got: $got)"; fail=$((fail + 1))
fi

# _started_by_gui: en este shell el padre es bash → false
if bash -c "source '$H/core.sh' >/dev/null 2>&1; _started_by_gui"; then
    echo "  ✗ _started_by_gui en shell manual"; fail=$((fail + 1))
else
    echo "  ✓ _started_by_gui en shell manual"
fi

echo "RESULT fail=$fail"
exit $((fail > 0))
