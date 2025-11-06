#!/usr/bin/env bash
# Journal: crea sesión si falta +Ventana journal + archivo desde template.
# Sesión detached con nombre único (se elimina al final).

H="$TDO_HUB"
V="$TDO_TMP/vault"
fail=0
SESS="tdo-test-journal-$$"

mkdir -p "$V/templates"
printf -- '---\ndate: {{date}}\n---\n\n# FIXTURE-JOURNAL-444 {{title}}\n' > "$V/templates/entry.md"

cat > "$H/.env" <<EOF
HUB_ROOT="$H"
NOTES_DIR="$V"
JOURNAL_DIR="\$NOTES_DIR/journal"
TEMPLATES_DIR="\$NOTES_DIR/templates"
SESSION="$SESS"
AW_DEFAULT_SERVER="http://127.0.0.1:9"
AW_FALLBACK_SERVER="http://127.0.0.1:9"
EOF

trap 'tmux kill-session -t "$SESS" 2>/dev/null' EXIT
bash "$H/scripts/journal.sh" >/dev/null 2>&1

TD=$(date +%Y-%m-%d)
if [[ -f "$V/journal/$(date +%Y)/$(date +%m)/$TD.md" ]] && grep -q "FIXTURE-JOURNAL-444" "$V/journal/$(date +%Y)/$(date +%m)/$TD.md"; then
    echo "  ✓ journal creado desde template"
else
    echo "  ✗ journal creado desde template"; fail=$((fail + 1))
fi

if tmux list-windows -t "$SESS" -F '#{window_name}' 2>/dev/null | grep -q "^journal$"; then
    echo "  ✓ ventana journal en sesión $SESS"
else
    echo "  ✗ ventana journal en sesión $SESS"; fail=$((fail + 1))
fi

echo "RESULT fail=$fail"
exit $((fail > 0))
