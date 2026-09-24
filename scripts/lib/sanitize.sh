#!/usr/bin/env bash
# ==========================================================
# 🛡️ SANITIZE - Input sanitization library
# Previene inyección en sed, regex, shell, SQL, paths
# ==========================================================

# Sanitizar para uso en sed (replacement y pattern)
# Escapa: / \ & [ ] . * ^ $ ( ) { } | ? + -
sanitize_for_sed() {
    local input="$1"
    printf '%s\n' "$input" | sed 's/[[\/.*^$(){}|?+\\&\\-]/\\&/g'
}

# Sanitizar para uso en regex (grep -E, awk, etc)
# Escapa metacaracteres regex
sanitize_for_regex() {
    local input="$1"
    printf '%s\n' "$input" | sed 's/[[\/.*^$(){}|?+\\\\\\-]/\\&/g'
}

# Sanitizar para uso en shell (eval, command substitution)
# Escapa: $ ` " ' \ espacio newline tab
sanitize_for_shell() {
    local input="$1"
    printf '%q' "$input"
}

# Sanitizar nombre de archivo (path traversal, chars especiales)
# Permite: alfanuméricos, _, -, ., espacios
sanitize_filename() {
    local input="$1"
    printf '%s\n' "$input" | sed 's/[^a-zA-Z0-9_. -]//g' | sed 's/  */ /g' | sed 's/^ *//; s/ *$//'
}

# Sanitizar para SQL (básico - usa prepared statements en producción)
sanitize_for_sql() {
    local input="$1"
    printf '%s\n' "$input" | sed "s/'/''/g"
}

# Validar que input no contiene patrones peligrosos
# Retorna 0 si seguro, 1 si sospechoso
validate_safe_input() {
    local input="$1"
    local context="${2:-general}"
    
    case "$context" in
        path)
            # Detectar path traversal
            [[ "$input" =~ \.\. ]] && return 1
            [[ "$input" =~ ^/ ]] && return 1
            [[ "$input" =~ [^a-zA-Z0-9_./-] ]] && return 1
            ;;
        filename)
            [[ "$input" =~ [^a-zA-Z0-9_.\\-] ]] && return 1
            ;;
        alphanum)
            [[ "$input" =~ [^a-zA-Z0-9] ]] && return 1
            ;;
        *)
            # General: sin caracteres de control, sin $() ``
            [[ "$input" =~ [\$\`\\\\] ]] && return 1
            ;;
    esac
    return 0
}

# Sanitizar y validar en una llamada
# Uso: safe_var=$(sanitize_and_validate "$user_input" "filename") || exit 1
sanitize_and_validate() {
    local input="$1"
    local context="$2"
    local sanitized
    
    case "$context" in
        sed)        sanitized=$(sanitize_for_sed "$input") ;;
        regex)      sanitized=$(sanitize_for_regex "$input") ;;
        shell)      sanitized=$(sanitize_for_shell "$input") ;;
        filename)   sanitized=$(sanitize_filename "$input") ;;
        sql)        sanitized=$(sanitize_for_sql "$input") ;;
        *)          sanitized="$input" ;;
    esac
    
    if validate_safe_input "$sanitized" "$context"; then
        printf '%s\n' "$sanitized"
        return 0
    else
        log_err "SANITIZE" "Input rechazado (contexto: $context): $input"
        return 1
    fi
}

# Escapar para JSON (uso en notify-send, jq, etc)
sanitize_for_json() {
    local input="$1"
    printf '%s\n' "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\//\\\//g; s/\b/\\b/g; s/\f/\\f/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'
}

# Sanitizar para uso en URL (query params)
sanitize_for_url() {
    local input="$1"
    # Versión simple - para producción usar python urllib.parse.quote
    printf '%s\n' "$input" | sed 's/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/%/%25/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/\*/%2A/g; s/+/%2B/g; s/,/%2C/g; s/-/%2D/g; s/\./%2E/g; s/\//%2F/g; s/:/%3A/g; s/;/%3B/g; s//%3E/g; s/?/%3F/g; s/@/%40/g; s/\[/%5B/g; s/\\/%5C/g; s/\]/%5D/g; s/\^/%5E/g; s/_/%5F/g; s/`/%60/g; s/{/%7B/g; s/|/%7C/g; s/}/%7D/g; s/~/%7E/g'
}