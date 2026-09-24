#!/usr/bin/env bash
# ==========================================================
# ⏱️ TIME - Resumen de timewarrior en tmux
# Uso directo (atajo) o desde hub.sh
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"

run_in_tmux "timew summary" "timew"
