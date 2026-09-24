#!/usr/bin/env bash
# ==========================================================
# 🔐 INSTALADOR SUDOERS TDO HUB
# Genera /etc/sudoers.d/tdo-hub resolviendo __USER__ y
# __HUB_ROOT__ con los valores reales del sistema.
# Nada hardcodeado: usuario y rutas se obtienen en runtime.
# ==========================================================

set -e

HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$HUB_ROOT/scripts/system/sudoers-tdo"
TARGET="/etc/sudoers.d/tdo-hub"
TMP_FILE="/tmp/sudoers-tdo-hub.$$"

if [[ "$(id -u)" -eq 0 ]]; then
    USER_NAME="${SUDO_USER:-$(id -un)}"
else
    USER_NAME="$(id -un)"
fi

# Escapar backslashes para sed si fuese necesario (HUB_ROOT no suele tenerlos)
TEMPLATE_ESC=$(printf '%s\n' "$TEMPLATE" | sed 's/[.[\*^$()\/]/\\&/g')

# Sustituir placeholders
sed -e "s/__USER__/$USER_NAME/g" -e "s|__HUB_ROOT__|$HUB_ROOT|g" "$TEMPLATE" > "$TMP_FILE"

# Validación mínima de sintaxis (sudo -V no valida rules; usamos visudo -cf)
if command -v visudo &>/dev/null; then
    visudo -cf "$TMP_FILE" >/dev/null 2>&1 || {
        echo "❌ Sintaxis inválida en el sudoers generado" >&2
        rm -f "$TMP_FILE"
        exit 1
    }
fi

if [[ "$(id -u)" -eq 0 ]]; then
    cp "$TMP_FILE" "$TARGET"
else
    sudo -n cp "$TMP_FILE" "$TARGET" 2>/dev/null || {
        echo "ℹ Ejecuta este script con sudo: sudo bash $HUB_ROOT/scripts/system/install-sudoers.sh" >&2
        echo "   (o copia a mano: sudo cp $TMP_FILE $TARGET && sudo chmod 440 $TARGET)" >&2
        rm -f "$TMP_FILE"
        exit 1
    }
fi

chmod 440 "$TARGET" 2>/dev/null || true
rm -f "$TMP_FILE"

echo "✓ sudoers instalado para usuario: $USER_NAME"
echo "  → $TARGET"
echo "  → backup de hosts: $HUB_ROOT/hosts.bak"