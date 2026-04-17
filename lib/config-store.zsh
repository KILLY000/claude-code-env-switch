_ensure_order_file() {
    _ensure_env_dir
    if [[ ! -f "$CLAUDE_ENVS_ORDER_FILE" ]]; then
        local -a configs
        configs=($(find "$CLAUDE_ENVS_DIR" -maxdepth 1 -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
        printf "%s\n" "${configs[@]}" > "$CLAUDE_ENVS_ORDER_FILE" 2>/dev/null
    fi
}

_write_order_file() {
    local names=("$@")
    printf "%s\n" "${names[@]}" > "$CLAUDE_ENVS_ORDER_FILE"
}

_remove_from_order() {
    local name="$1"
    [[ ! -f "$CLAUDE_ENVS_ORDER_FILE" ]] && return

    local tmp=()
    local line=""
    while IFS= read -r line; do
        [[ "$line" == "$name" || -z "$line" ]] && continue
        tmp+=("$line")
    done < "$CLAUDE_ENVS_ORDER_FILE"

    _write_order_file "${tmp[@]}"
}

_append_to_order() {
    local name="$1"
    _ensure_order_file

    if grep -qxF "$name" "$CLAUDE_ENVS_ORDER_FILE" 2>/dev/null; then
        return
    fi

    echo "$name" >> "$CLAUDE_ENVS_ORDER_FILE"
}

_list_configs() {
    _ensure_order_file

    local -a on_disk=()
    local conf_file=""
    for conf_file in "$CLAUDE_ENVS_DIR"/*.conf(N); do
        on_disk+=("${conf_file:t:r}")
    done

    local result=()
    local line=""
    if [[ -s "$CLAUDE_ENVS_ORDER_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ -f "$(_config_file_path "$line")" ]]; then
                result+=("$line")
            fi
        done < "$CLAUDE_ENVS_ORDER_FILE"
    fi

    local orphan=""
    for orphan in "${on_disk[@]}"; do
        if ! grep -qxF "$orphan" "$CLAUDE_ENVS_ORDER_FILE" 2>/dev/null; then
            result+=("$orphan")
            echo "$orphan" >> "$CLAUDE_ENVS_ORDER_FILE"
        fi
    done

    print -r -- "${result[@]}"
}
