#!/usr/bin/env bash
# ==========================================================
# 🧪 TDO Hub - Suite mínima de tests (headless, sandbox /tmp)
# Uso: bash tests/run_tests.sh
# Cada test/test-*.sh sale 0 (OK) o 1 (FAIL).
# Los tests copian el repo a /tmp para no tocar nada real:
# .env, vault y sesiones tmux son de mentira.
# ==========================================================

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

T="$(mktemp -d)"
export TDO_TMP="$T"
trap 'rm -rf "$T"' EXIT

# Copia aislada (sin .git) para que .env/vault sean fixtures
mkdir -p "$T/hub"
tar cf - --exclude=.git . | tar xf - -C "$T/hub"
export TDO_HUB="$T/hub"

fail=0
count=0

# Tripwire: nada real puede cambiar (repo hub + vault de notas).
# Se compara git status antes/después; si difiere, FAIL.
trip_before_repo=$(git status --porcelain 2>/dev/null)
trip_before_notes=$(git -C ~/notes status --porcelain 2>/dev/null)

for t in tests/test-*.sh; do
    count=$((count + 1))
    echo "== $t"
    # Entorno hermético: sin él, vars exportadas del shell (set -a del
    # .env real) contaminan los fixtures. Solo pasa lo necesario.
    # LC_ALL UTF-8: en locale C los rangos multibyte de sed fallan.
    if env -i HOME="$T/fakehome" PATH=/usr/bin:/bin TERM=dumb LANG=C.utf8 LC_ALL=C.utf8 TDO_TMP="$T" TDO_HUB="$T/hub" bash "$t"; then
        echo "   OK"
    else
        echo "   *** FAIL: $t"
        fail=$((fail + 1))
    fi
done

echo "———————————————"
echo "Suites: $count, fallidas: $fail"

if [[ "$(git status --porcelain 2>/dev/null)" != "$trip_before_repo" ]]; then
    echo "*** FAIL tripwire: un test modificó el repo real"
    git status --porcelain
    fail=$((fail + 1))
else
    echo "✓ tripwire repo: limpio"
fi
if [[ "$(git -C ~/notes status --porcelain 2>/dev/null)" != "$trip_before_notes" ]]; then
    echo "*** FAIL tripwire: un test modificó ~/notes"
    git -C ~/notes status --porcelain
    fail=$((fail + 1))
else
    echo "✓ tripwire notes: limpio"
fi

exit $((fail > 0))
