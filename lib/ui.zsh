_ccenv_restore_terminal() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
}

_ccenv_drain_input_buffer() {
    read -rsk -t 0.01 2>/dev/null || true
}

_ccenv_select() {
    _ensure_env_dir

    local selected=1
    local claude_args=("$@")

    while true; do
        clear

        local configs=($(_list_configs))
        if [[ ${#configs[@]} -eq 0 ]]; then
            echo "No configurations found."
            echo "(a: add, q: quit)"
            echo
            local empty_key=""
            while true; do
                read -rsk1 empty_key
                case "$empty_key" in
                    "a"|"A")
                        _ccenv_add
                        break
                        ;;
                    "q"|"Q")
                        return 0
                        ;;
                esac
            done
            continue
        fi

        local display_lines=()
        local conf=""
        for conf in "${configs[@]}"; do
            display_lines+=("$(_get_config_display_line "$conf")")
        done

        local total=${#configs[@]}
        ((selected > total)) && selected=$total
        ((selected < 1)) && selected=1

        local has_args=0
        [[ ${#claude_args[@]} -gt 0 ]] && has_args=1

        local shortcuts_line="(↑/↓:move  Enter:start  a:add  e:edit  d:delete  v:view  o:reorder  w:settings  s:args  q:quit)"
        local term_width
        term_width=$(tput cols)
        local shortcuts_len=${#shortcuts_line}
        local shortcuts_rows=$(( (shortcuts_len + term_width - 1) / term_width ))
        local list_start_row=$((5 + shortcuts_rows + has_args))

        _ccenv_restore() {
            _ccenv_restore_terminal
        }

        trap '_ccenv_restore; return 130' INT
        stty -echo
        tput civis

        _ccenv_render() {
            if [[ "$1" == "1" ]]; then
                echo "Claude Code Environment Switch"
                echo "Manage multiple authentication configurations"
                echo
                echo "Configurations:"
                echo "$shortcuts_line"
                if [[ $has_args -eq 1 ]]; then
                    echo "Args: ${claude_args[*]}"
                fi
                echo
            else
                tput cup $list_start_row 0
            fi

            local i=0
            for i in $(seq 1 $total); do
                if [[ $i -eq $selected ]]; then
                    printf "\e[2K  \e[7m %s \e[0m\n" "${display_lines[$i]}"
                else
                    printf "\e[2K   %s\n" "${display_lines[$i]}"
                fi
            done
        }

        _ccenv_render 1

        local action=""
        local key=""
        while true; do
            read -rsk1 key
            case "$key" in
                $'\x1b')
                    read -rsk2 key
                    case "$key" in
                        "[A") ((selected > 1)) && ((selected--)) || selected=$total ;;
                        "[B") ((selected < total)) && ((selected++)) || selected=1 ;;
                    esac
                    ;;
                $'\n')
                    action="use"
                    break
                    ;;
                "a"|"A")
                    action="add"
                    break
                    ;;
                "e"|"E")
                    action="edit"
                    break
                    ;;
                "d"|"D")
                    action="delete"
                    break
                    ;;
                "v"|"V")
                    action="view"
                    break
                    ;;
                "o"|"O")
                    action="reorder"
                    break
                    ;;
                "w"|"W")
                    action="settings"
                    break
                    ;;
                "s"|"S")
                    action="args"
                    break
                    ;;
                "q"|"Q")
                    action="quit"
                    break
                    ;;
            esac
            _ccenv_render 0
        done

        _ccenv_restore
        trap - INT

        case "$action" in
            "use")
                clear
                _ccenv_use "${configs[$selected]}" "${claude_args[@]}"
                return $?
                ;;
            "add")
                clear
                _ccenv_add
                ;;
            "edit")
                clear
                _ccenv_edit "${configs[$selected]}"
                ;;
            "delete")
                clear
                _ccenv_delete "${configs[$selected]}"
                ;;
            "view")
                clear
                _ccenv_view "${configs[$selected]}"
                echo
                echo "(Press any key to return)"
                read -rsk1
                _ccenv_drain_input_buffer
                ;;
            "reorder")
                clear
                _ccenv_reorder
                ;;
            "settings")
                clear
                local settings_status=0
                _ccenv_settings_set "${configs[$selected]}"
                settings_status=$?
                echo
                echo "(Press any key to exit)"
                read -rsk1
                _ccenv_drain_input_buffer
                return $settings_status
                ;;
            "args")
                clear
                echo "Current args: ${claude_args[*]:-(none)}"
                echo
                echo "Enter new args for claude (space-separated, empty to clear):"
                local new_args_str=""
                read "new_args_str?"
                if [[ -z "$new_args_str" ]]; then
                    claude_args=()
                else
                    claude_args=(${=new_args_str})
                fi
                ;;
            "quit")
                return 0
                ;;
        esac
    done
}

_ccenv_reorder() {
    _ensure_order_file

    local configs=($(_list_configs))
    if [[ ${#configs[@]} -le 1 ]]; then
        echo "Need at least 2 configurations to reorder."
        return 0
    fi

    local -a display_lines
    local conf=""
    for conf in "${configs[@]}"; do
        display_lines+=("$(_get_config_display_line "$conf")")
    done

    local selected=1
    local total=${#configs[@]}
    local changed=0

    _ccenv_restore() {
        _ccenv_restore_terminal
    }

    trap '_ccenv_restore; return 130' INT
    stty -echo
    tput civis

    _ccenv_reorder_render() {
        if [[ "$1" == "1" ]]; then
            echo "Reorder configurations:"
            echo "(↑/↓ move cursor, u/d move item up/down, Enter save, q cancel)"
            echo
        else
            tput cup 3 0
        fi

        local i=0
        for i in $(seq 1 $total); do
            if [[ $i -eq $selected ]]; then
                printf "\e[2K  \e[7m %d. %s \e[0m\n" "$i" "${display_lines[$i]}"
            else
                printf "\e[2K   %d. %s\n" "$i" "${display_lines[$i]}"
            fi
        done
    }

    _ccenv_reorder_render 1

    local key=""
    while true; do
        read -rsk1 key
        case "$key" in
            $'\x1b')
                read -rsk2 key
                case "$key" in
                    "[A")
                        ((selected > 1)) && ((selected--)) || selected=$total
                        ;;
                    "[B")
                        ((selected < total)) && ((selected++)) || selected=1
                        ;;
                esac
                ;;
            "u"|"U"|"k"|"K")
                if ((selected > 1)); then
                    local prev=$((selected - 1))
                    local tmp="${configs[$selected]}"
                    configs[$selected]="${configs[$prev]}"
                    configs[$prev]="$tmp"
                    tmp="${display_lines[$selected]}"
                    display_lines[$selected]="${display_lines[$prev]}"
                    display_lines[$prev]="$tmp"
                    ((selected--))
                    changed=1
                fi
                ;;
            "d"|"D"|"j"|"J")
                if ((selected < total)); then
                    local next=$((selected + 1))
                    local tmp="${configs[$selected]}"
                    configs[$selected]="${configs[$next]}"
                    configs[$next]="$tmp"
                    tmp="${display_lines[$selected]}"
                    display_lines[$selected]="${display_lines[$next]}"
                    display_lines[$next]="$tmp"
                    ((selected++))
                    changed=1
                fi
                ;;
            $'\n')
                break
                ;;
            "q"|"Q")
                _ccenv_restore
                trap - INT
                echo
                echo "Cancelled, order unchanged."
                return 0
                ;;
        esac
        _ccenv_reorder_render 0
    done

    _ccenv_restore
    trap - INT
    echo

    if ((changed)); then
        _write_order_file "${configs[@]}"
        echo "Order saved successfully!"
    else
        echo "No changes made."
    fi
}
