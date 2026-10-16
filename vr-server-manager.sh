#!/usr/bin/env bash
# VR Server Manager - Etapa 1. Somente leitura; nao usa Docker nem grava arquivos.
# Bash 4.4+, /proc, GNU coreutils e terminal ANSI. Distribuir apenas este arquivo.

initialize_state() {
    VERSION=0.1.0
    REFRESH_SECONDS=2
    PROC_ROOT=/proc
    MIN_COLUMNS=32
    MIN_ROWS=16
    ESC=$'\033'
    RESET=$'\033[0m'
    BOLD=$'\033[1;36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    DIM=$'\033[90m'
    SELECTED=$'\033[1;7m'
    MODULES=('Containers Docker' 'Projetos Compose' 'Logs e Eventos'
             'Diagnóstico' 'Exportações' 'Configurações')
    screen=menu; previous_screen=menu
    selected_module=0; focus=0; previous_focus=0; help_offset=0
    running=1; dirty=1; resize_pending=1
    terminal_active=0; terminal_saved=''; terminal_fd=''
    worker_pid=''; metrics_fd=''; metric_buffer=''; worker_started=0; next_refresh=0
    update_count=0; last_update='aguardando'
    status_message='Somente monitoramento. Selecione um módulo.'
    collector_failed=0
    cpu_previous_total=-1; cpu_previous_idle=-1
    cpu_percent=-1; cpu_description='Amostrando...'
    cpu_total=-1; cpu_idle=-1
    mem_total=-1; mem_available=-1; swap_total=-1; swap_free=-1
    disk_total=-1; disk_used=-1; disk_available=-1; disk_percent=-1
    uptime_seconds=-1; load_average='Indisponível'
    host_name='Indisponível'; user_name='Indisponível'; distribution='Indisponível'
    columns=80; rows=24; have_df=0
    FRAME=(); STYLES=(); LAST_FRAME=(); LAST_STYLES=()
}

is_uint() { [[ $1 =~ ^[0-9]{1,16}$ ]]; }
is_linux() { [[ $OSTYPE == linux* ]]; }

now_milliseconds() {
    local instant=${EPOCHREALTIME:-}
    if [[ $instant == *.* ]]; then
        local fraction=${instant#*.}
        NOW_MS=$((${instant%.*} * 1000 + 10#$fraction / 1000))
    else
        # Compatibilidade com Bash 4.4: resolucao de um segundo.
        NOW_MS=$((SECONDS * 1000))
    fi
}

clean_text() {
    # Dados do host nunca podem injetar sequencias de controle no terminal.
    CLEAN_TEXT=${1//[[:cntrl:]]/}
}

read_identity() {
    local line key value
    if [[ -r $PROC_ROOT/sys/kernel/hostname ]] && IFS= read -r line < "$PROC_ROOT/sys/kernel/hostname" 2>/dev/null; then
        clean_text "$line"; host_name=$CLEAN_TEXT
    fi
    user_name=${USER:-${LOGNAME:-UID:$UID}}
    if command -v id >/dev/null 2>&1; then
        value=$(timeout --signal=KILL 1s id -un 2>/dev/null) && user_name=$value
    fi
    clean_text "$user_name"; user_name=$CLEAN_TEXT
    if [[ -r /etc/os-release ]]; then
        while IFS='=' read -r key value; do
            [[ $key == PRETTY_NAME ]] || continue
            value=${value#\"}; value=${value%\"}
            value=${value#\'}; value=${value%\'}
            clean_text "$value"; distribution=$CLEAN_TEXT
            break
        done < /etc/os-release
    fi
}

read_cpu_sample() {
    local label value i total=0 idle=0
    local -a counters=()
    cpu_total=-1; cpu_idle=-1
    [[ -r $PROC_ROOT/stat ]] || return 1
    read -r -a counters < "$PROC_ROOT/stat" 2>/dev/null || return 1
    label=${counters[0]:-}
    counters=("${counters[@]:1}")
    [[ $label == cpu && ${#counters[@]} -ge 4 ]] || return 1
    # Somar apenas user..steal. guest e guest_nice ja estao em user/nice.
    for ((i=0; i<8; i++)); do
        value=${counters[i]:-0}
        is_uint "$value" || return 1
        value=$((10#$value))
        ((total += value))
        ((i == 3 || i == 4)) && ((idle += value))
    done
    cpu_total=$total; cpu_idle=$idle
    return 0
}

calculate_cpu() {
    local total=$1 idle=$2 delta_total delta_idle
    cpu_percent=-1; cpu_description='Indisponível'
    if ! is_uint "$total" || ! is_uint "$idle" || ((idle > total)); then
        cpu_previous_total=-1; cpu_previous_idle=-1
        return
    fi
    if ((cpu_previous_total >= 0)); then
        delta_total=$((total - cpu_previous_total))
        delta_idle=$((idle - cpu_previous_idle))
        if ((delta_total > 0 && delta_idle >= 0 && delta_idle <= delta_total)); then
            cpu_percent=$(((delta_total - delta_idle) * 100 / delta_total))
            cpu_description='entre amostras'
        fi
    else
        cpu_description='Amostrando...'
    fi
    # Uma amostra invalida nunca vira 0%. Atualizar a base permite recuperar.
    cpu_previous_total=$total; cpu_previous_idle=$idle
}

read_memory_sample() {
    local key value unit
    mem_total=-1; mem_available=-1; swap_total=-1; swap_free=-1
    [[ -r $PROC_ROOT/meminfo ]] || return 1
    while read -r key value unit; do
        is_uint "$value" && [[ $unit == kB ]] || continue
        value=$((10#$value))
        case $key in
            MemTotal:) mem_total=$value ;;
            MemAvailable:) mem_available=$value ;;
            SwapTotal:) swap_total=$value ;;
            SwapFree:) swap_free=$value ;;
        esac
    done < "$PROC_ROOT/meminfo"
    if ((mem_total <= 0 || mem_available < 0 || mem_available > mem_total)); then
        mem_total=-1; mem_available=-1
    fi
    if ((swap_total < 0 || swap_free < 0 || swap_free > swap_total)); then
        swap_total=-1; swap_free=-1
    fi
}

read_disk_sample() {
    local output total used available percent remainder
    disk_total=-1; disk_used=-1; disk_available=-1; disk_percent=-1
    ((have_df)) || return
    # df nao sincroniza discos; a coleta ocorre fora do processo da interface.
    output=$(LC_ALL=C timeout --signal=KILL 1s df -B1 --output=size,used,avail,pcent / 2>/dev/null) || return
    output=${output#*$'\n'}
    read -r total used available percent remainder <<< "$output"
    percent=${percent%\%}
    is_uint "$total" && is_uint "$used" && is_uint "$available" && is_uint "$percent" || return
    total=$((10#$total)); used=$((10#$used)); available=$((10#$available)); percent=$((10#$percent))
    ((total > 0 && used <= total && available <= total && percent <= 100)) || return
    disk_total=$total; disk_used=$used; disk_available=$available; disk_percent=$percent
}

read_system_sample() {
    local uptime_value rest load1 load5 load15
    uptime_seconds=-1; load_average='Indisponível'
    if [[ -r $PROC_ROOT/uptime ]] && read -r uptime_value rest < "$PROC_ROOT/uptime" 2>/dev/null; then
        uptime_value=${uptime_value%%.*}
        is_uint "$uptime_value" && uptime_seconds=$((10#$uptime_value))
    fi
    if [[ -r $PROC_ROOT/loadavg ]] && read -r load1 load5 load15 rest < "$PROC_ROOT/loadavg" 2>/dev/null; then
        if [[ $load1 =~ ^[0-9]+([.][0-9]+)?$ && $load5 =~ ^[0-9]+([.][0-9]+)?$ && $load15 =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            load_average="$load1/$load5/$load15"
        fi
    fi
}

collect_snapshot() {
    read_cpu_sample
    read_memory_sample
    read_system_sample
    read_disk_sample
    # Registro unico, sem eval/source, sem arquivos temporarios e sem dados ANSI.
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$cpu_total" "$cpu_idle" "$mem_total" "$mem_available" \
        "$swap_total" "$swap_free" "$disk_total" "$disk_used" \
        "$disk_available" "$disk_percent" "$uptime_seconds" "$load_average"
}

close_worker() {
    if [[ -n $metrics_fd ]]; then exec {metrics_fd}<&-; metrics_fd=''; fi
    if [[ -n $worker_pid ]]; then
        wait "$worker_pid" 2>/dev/null || :
        worker_pid=''
    fi
}

start_collection() {
    [[ -z $worker_pid ]] || return
    local read_fd write_fd
    metric_buffer=''
    # Coprocesso finito: a interface nunca espera por df ou por uma segunda CPU.
    coproc VR_METRICS {
        trap - EXIT INT TERM HUP QUIT WINCH
        IFS= read -r request && collect_snapshot
    } 2>/dev/null
    worker_pid=$VR_METRICS_PID
    read_fd=${VR_METRICS[0]}; write_fd=${VR_METRICS[1]}
    exec {metrics_fd}<&"$read_fd"
    exec {read_fd}<&-
    # A barreira evita que um coletor rapido termine antes de copiarmos seus FDs.
    printf 'collect\n' >&"$write_fd"
    exec {write_fd}>&-
    worker_started=$SECONDS
    now_milliseconds
    next_refresh=$((NOW_MS + REFRESH_SECONDS * 1000))
}

unavailable_snapshot() {
    calculate_cpu -1 -1
    mem_total=-1; mem_available=-1; swap_total=-1; swap_free=-1
    disk_total=-1; disk_used=-1; disk_available=-1; disk_percent=-1
    uptime_seconds=-1; load_average='Indisponível'
    collector_failed=1; dirty=1
}

poll_collection() {
    local record='' total idle read_status
    [[ -n $worker_pid ]] || return
    if IFS= read -r -t 0.01 -u "$metrics_fd" record; then
        record=$metric_buffer$record
        IFS='|' read -r total idle mem_total mem_available swap_total swap_free \
            disk_total disk_used disk_available disk_percent uptime_seconds load_average <<< "$record"
        calculate_cpu "$total" "$idle"
        printf -v last_update '%(%H:%M:%S)T' -1
        ((update_count += 1))
        collector_failed=0
        close_worker
        dirty=1
    else
        read_status=$?
        # read com prazo pode consumir parte da linha antes de expirar.
        # Preservar esse trecho evita perder amostras em SSH/hosts ocupados.
        metric_buffer+=$record
        if ((read_status == 1)); then
            unavailable_snapshot
            close_worker
        elif ((SECONDS - worker_started >= 3)); then
            kill -KILL "$worker_pid" 2>/dev/null || :
            unavailable_snapshot
            close_worker
        fi
    fi
}

read_geometry() {
    local size height width
    size=$(stty size <&"$terminal_fd" 2>/dev/null) || size='24 80'
    read -r height width <<< "$size"
    is_uint "$height" && ((height > 0)) || height=24
    is_uint "$width" && ((width > 0)) || width=80
    rows=$height; columns=$width
    # Limites de trabalho; o terminal pode ser maior sem custo proporcional.
    ((rows > 100)) && rows=100
    ((columns > 300)) && columns=300
    LAST_FRAME=(); LAST_STYLES=()
    printf '%s[2J' "$ESC"
    resize_pending=0; dirty=1
}

enter_terminal() {
    terminal_active=1
    stty -echo -icanon isig -ixon min 1 time 0 <&"$terminal_fd" || return 1
    printf '%s[?1049h%s[?25l%s[0m' "$ESC" "$ESC" "$ESC"
    resize_pending=1
}

cleanup() {
    local saved_status=$?
    trap - EXIT INT TERM HUP QUIT WINCH
    if [[ -n $worker_pid ]]; then
        kill -KILL "$worker_pid" 2>/dev/null || :
        close_worker
    fi
    if [[ -n $terminal_saved && -n $terminal_fd ]]; then
        stty "$terminal_saved" <&"$terminal_fd" 2>/dev/null || :
    fi
    if ((terminal_active)); then
        printf '%s[0m%s[?25h%s[?1049l' "$ESC" "$ESC" "$ESC"
    fi
    if [[ -n $terminal_fd ]]; then exec {terminal_fd}>&-; fi
    return "$saved_status"
}

initialize_terminal() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf 'A interface requer entrada e saída interativas. Use: bash %s --check\n' "$0" >&2
        return 2
    fi
    if [[ ${TERM:-dumb} == dumb ]]; then
        printf 'Terminal ANSI indisponível (TERM vazio ou dumb). Use --check.\n' >&2
        return 2
    fi
    exec {terminal_fd}<>/dev/tty || return 1
    terminal_saved=$(stty -g <&"$terminal_fd") || return 1
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    trap 'exit 131' QUIT
    trap 'resize_pending=1' WINCH
    enter_terminal
}

format_size() {
    # Entrada em bytes, saida compacta binaria (G = GiB, M = MiB).
    local value=$1 divisor=1 suffix=B
    if ((value >= 1099511627776)); then divisor=1099511627776; suffix=T
    elif ((value >= 1073741824)); then divisor=1073741824; suffix=G
    elif ((value >= 1048576)); then divisor=1048576; suffix=M
    elif ((value >= 1024)); then divisor=1024; suffix=K
    fi
    printf -v FORMATTED_SIZE '%d.%d%s' "$((value / divisor))" "$((value % divisor * 10 / divisor))" "$suffix"
}

set_line() {
    local row=$1
    ((row >= 1 && row <= rows)) || return
    FRAME[row]=$2; STYLES[row]=${3:-}
}

metric_line() {
    local row=$1 label=$2 percent=$3 details=$4 width filled empty bar pct color=$GREEN text
    width=$((columns - 14 - ${#details}))
    ((width < 4)) && width=4
    ((width > 24)) && width=24
    if ((percent < 0)); then
        printf -v bar '%*s' "$width" ''; bar=${bar// /?}
        pct=' --%'; color=$DIM
    else
        ((percent > 100)) && percent=100
        filled=$((percent * width / 100)); empty=$((width - filled))
        printf -v bar '%*s' "$filled" ''; bar=${bar// /#}
        printf -v pct '%*s' "$empty" ''; bar+=${pct// /-}
        printf -v pct '%3d%%' "$percent"
        ((percent >= 70)) && color=$YELLOW
        ((percent >= 90)) && color=$RED
    fi
    printf -v text '%-4s [%s] %s %s' "$label" "$bar" "$pct" "$details"
    set_line "$row" "$text" "$color"
}

render_indicators() {
    local used total available details percent uptime_text host_width
    set_line 1 "VR SERVER MANAGER  v$VERSION" "$BOLD"
    host_width=$(((columns - 17) / 2))
    set_line 2 "Host: ${host_name:0:host_width} | Usuário: ${user_name:0:host_width}"
    set_line 3 "$distribution" "$DIM"
    if ((uptime_seconds >= 0)); then
        printf -v uptime_text '%dd%dh%dm' "$((uptime_seconds / 86400))" \
            "$((uptime_seconds / 3600 % 24))" "$((uptime_seconds / 60 % 60))"
    else uptime_text='--'; fi
    if ((columns < 50)); then
        if ((uptime_seconds >= 86400)); then
            uptime_text="$((uptime_seconds / 86400))d$((uptime_seconds / 3600 % 24))h"
        fi
        set_line 4 "Up $uptime_text | L $load_average"
    else set_line 4 "Up $uptime_text | Load $load_average"; fi
    metric_line 5 CPU "$cpu_percent" "$cpu_description"
    percent=-1; details='Indisponível'
    if ((mem_total > 0)); then
        used=$((mem_total - mem_available)); percent=$((used * 100 / mem_total))
        format_size "$((used * 1024))"; used=$FORMATTED_SIZE
        format_size "$((mem_total * 1024))"; total=$FORMATTED_SIZE
        details="$used/$total"
        ((columns >= 90)) && details+=' usados/total'
    fi
    metric_line 6 RAM "$percent" "$details"
    percent=-1; details='Indisponível'
    if ((swap_total == 0)); then
        percent=0; details='Desativada'
    elif ((swap_total > 0)); then
        used=$((swap_total - swap_free)); percent=$((used * 100 / swap_total))
        format_size "$((used * 1024))"; used=$FORMATTED_SIZE
        format_size "$((swap_total * 1024))"; total=$FORMATTED_SIZE
        details="$used/$total"
    fi
    metric_line 7 Swap "$percent" "$details"
    details='Indisponível'
    if ((disk_total > 0)); then
        format_size "$disk_used"; used=$FORMATTED_SIZE
        format_size "$disk_available"; available=$FORMATTED_SIZE
        details="U$used L$available"
        ((columns >= 90)) && details="$used usados | $available disponíveis (/)"
    fi
    metric_line 8 / "$disk_percent" "$details"
    local -a spinner=('|' '/' '-' '\')
    set_line 9 "${spinner[update_count % 4]} Atualiza: 2s | $last_update #$update_count" "$DIM"
}

render_menu() {
    local first_row=11 last_row=$((rows - 4)) slots start i row style text
    slots=$((last_row - first_row + 1))
    ((slots > 6)) && slots=6
    start=0
    ((selected_module >= slots)) && start=$((selected_module - slots + 1))
    set_line 10 'MÓDULOS | Enter: abrir | Tab: ajuda' "$BOLD"
    for ((i=start, row=first_row; i<6 && row<=last_row; i++, row++)); do
        style=''; text="  $((i + 1)). ${MODULES[i]}"
        if ((i == selected_module)); then
            text="> $((i + 1)). ${MODULES[i]}"
            ((focus == 0)) && style=$SELECTED
        fi
        set_line "$row" "$text" "$style"
    done
    if ((last_row >= 18)); then set_line 18 'Todos os módulos: Em desenvolvimento' "$DIM"; fi
    style=$DIM; ((focus == 1)) && style=$SELECTED
    set_line "$((rows - 3))" '[ Ajuda (F1) ]' "$style"
}

render_module() {
    set_line 10 "${MODULES[selected_module]}" "$BOLD"
    set_line 11 'Em desenvolvimento' "$YELLOW"
    if ((rows >= 20)); then
        set_line 13 'Etapa 1: monitoramento do servidor.'
        set_line 14 'Este módulo ainda não executa ações.' "$DIM"
    fi
    local style=$SELECTED
    ((focus == 1)) && style=$DIM
    set_line "$((rows - 3))" '[ Voltar (Esc) ]' "$style"
    if ((focus == 1)); then set_line "$((rows - 3))" '[ Voltar (Esc) ]   > Ajuda (Enter)' "$SELECTED"; fi
}

render_help() {
    local first_row=11 last_row=$((rows - 4)) row line
    set_line 10 'AJUDA | F1 ou Esc: voltar' "$BOLD"
    local -a help_lines=(
        'Cima/Baixo: navegar | Enter: abrir'
        'Tab: alternar foco | Esc: voltar'
        'R: atualizar métricas | Q: sair'
        'F1: abrir/fechar esta ajuda'
        'Barras: verde <70%, amarelo <90%'
        'Vermelho >=90%; ??? = indisponível'
        'RAM: total menos MemAvailable'
        'CPU: delta de /proc/stat; inclui steal'
        'Load: médias de 1, 5 e 15 minutos'
        'G/M/T: GiB/MiB/TiB | U: usado L: livre'
        'Atualização segue ativa em cada tela'
        'Sem Docker, instalações ou gravações'
    )
    local slots=$((last_row - first_row + 1)) max_offset
    max_offset=$((${#help_lines[@]} - slots))
    ((max_offset < 0)) && max_offset=0
    ((help_offset > max_offset)) && help_offset=$max_offset
    for ((row=first_row; row<=last_row && row-first_row+help_offset<${#help_lines[@]}; row++)); do
        line=${help_lines[row-first_row+help_offset]}
        set_line "$row" "$line"
    done
    set_line "$((rows - 3))" '[ Esc: voltar ]  Cima/Baixo: rolar' "$DIM"
}

build_alerts() {
    local -a alerts=()
    ((collector_failed)) && alerts+=('coleta falhou')
    ((cpu_percent < 0)) && alerts+=("CPU: $cpu_description")
    ((mem_total < 0)) && alerts+=('RAM indisponível')
    ((swap_total < 0)) && alerts+=('swap indisponível')
    ((disk_total < 0)) && alerts+=('disco indisponível')
    ((uptime_seconds < 0)) && alerts+=('uptime indisponível')
    [[ $load_average == Indisponível ]] && alerts+=('load indisponível')
    ((cpu_percent >= 90)) && alerts+=('CPU >=90%')
    if ((mem_total > 0 && (mem_total - mem_available) * 100 / mem_total >= 90)); then alerts+=('RAM >=90%'); fi
    ((disk_percent >= 90)) && alerts+=('disco >=90%')
    if ((${#alerts[@]})); then
        local IFS=';'
        ALERT_TEXT="Alertas: ${alerts[*]}"; ALERT_STYLE=$YELLOW
    else ALERT_TEXT='Alertas: nenhum | Somente leitura'; ALERT_STYLE=$DIM; fi
}

render_frame() {
    local row text style output=''
    FRAME=(); STYLES=()
    if ((columns < MIN_COLUMNS || rows < MIN_ROWS)); then
        set_line 1 "VR SERVER MANAGER v$VERSION" "$BOLD"
        set_line 2 "Terminal: ${columns}x${rows} (pequeno)" "$YELLOW"
        set_line 3 "Mínimo: ${MIN_COLUMNS}x${MIN_ROWS}. Amplie a janela."
        set_line 4 'Q: sair | Monitoramento ativo'
    else
        render_indicators
        case $screen in
            menu) render_menu ;;
            module) render_module ;;
            help) render_help ;;
        esac
        set_line "$((rows - 2))" "$status_message"
        build_alerts
        set_line "$((rows - 1))" "$ALERT_TEXT" "$ALERT_STYLE"
        if ((columns >= 72)); then
            set_line "$rows" 'Cima/Baixo: navegar | Enter | Tab | Esc: voltar | F1: ajuda | R | Q: sair' "$DIM"
        else set_line "$rows" 'F1 ajuda | R atualiza | Q sai' "$DIM"; fi
    fi
    # Comparacao por linha: sem clear/erase total durante atualizacoes normais.
    for ((row=1; row<=rows; row++)); do
        text=${FRAME[row]:-}; style=${STYLES[row]:-}
        text=${text:0:columns-1}
        if [[ ${LAST_FRAME[row]-__unset__} != "$text" || ${LAST_STYLES[row]-__unset__} != "$style" ]]; then
            output+="$ESC[${row};1H$style$text$RESET$ESC[K"
            LAST_FRAME[row]=$text; LAST_STYLES[row]=$style
        fi
    done
    [[ -z $output ]] || printf '%s' "$output"
    dirty=0
}

read_key() {
    local char tail='' part count
    KEY=''
    IFS= read -r -s -n 1 -t 0.1 -u "$terminal_fd" char || return 1
    case $char in
        "$ESC")
            # Prazo curto apenas para distinguir Esc das sequencias do teclado.
            for ((count=0; count<8; count++)); do
                IFS= read -r -s -n 1 -t 0.03 -u "$terminal_fd" part || break
                tail+=$part
                case $tail in
                    '[A'|'OA') KEY=UP; break ;;
                    '[B'|'OB') KEY=DOWN; break ;;
                    'OP'|'[11~'|'[[A') KEY=HELP; break ;;
                    '['|'O'|'[['|'[1'|'[11') ;;
                    *) break ;;
                esac
            done
            [[ -n $KEY ]] || { [[ -z $tail ]] && KEY=BACK; }
            ;;
        $'\t') KEY=TAB ;;
        ''|$'\n'|$'\r') KEY=ENTER ;;
        r|R) KEY=REFRESH ;;
        q|Q) KEY=QUIT ;;
    esac
    return 0
}

toggle_help() {
    if [[ $screen == help ]]; then screen=$previous_screen; focus=$previous_focus
    else previous_screen=$screen; previous_focus=$focus; screen=help; help_offset=0; fi
}

handle_key() {
    case $KEY in
        QUIT) running=0 ;;
        REFRESH)
            if [[ -z $worker_pid ]]; then start_collection; status_message='Atualização solicitada.'
            else status_message='Coleta em andamento...'; fi
            ;;
        HELP) toggle_help ;;
        BACK)
            if [[ $screen == help ]]; then toggle_help
            elif [[ $screen == module ]]; then screen=menu; focus=0; fi
            ;;
        TAB) [[ $screen == help ]] || focus=$((1 - focus)) ;;
        UP|DOWN)
            if [[ $screen == menu ]]; then
                focus=0
                if [[ $KEY == UP ]]; then selected_module=$(((selected_module + 5) % 6))
                else selected_module=$(((selected_module + 1) % 6)); fi
            elif [[ $screen == help ]]; then
                if [[ $KEY == DOWN ]]; then ((help_offset += 1))
                elif ((help_offset > 0)); then ((help_offset -= 1)); fi
            fi
            ;;
        ENTER)
            if [[ $screen == menu ]]; then
                if ((focus == 1)); then toggle_help
                else screen=module; focus=0; status_message='Em desenvolvimento. Nenhuma ação executada.'; fi
            elif [[ $screen == module ]]; then
                if ((focus == 1)); then toggle_help
                else screen=menu; focus=0; fi
            fi
            ;;
        '') return ;;
    esac
    dirty=1
}

check_compatibility() {
    local failed=0 command_name
    printf 'VR SERVER MANAGER v%s — verificação somente leitura\n' "$VERSION"
    if is_linux; then printf '[OK] Sistema Linux\n'
    else printf '[FALHA] Requer Linux/Ubuntu; ambiente atual: %s\n' "$OSTYPE"; failed=1; fi
    if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then
        printf '[OK] Bash %s\n' "$BASH_VERSION"
    else printf '[FALHA] Necessário Bash 4.4 ou posterior\n'; failed=1; fi
    for command_name in stty timeout; do
        if command -v "$command_name" >/dev/null 2>&1; then printf '[OK] %s disponível\n' "$command_name"
        else printf '[FALHA] Comando padrão ausente: %s\n' "$command_name"; failed=1; fi
    done
    if command -v df >/dev/null 2>&1; then
        have_df=1; printf '[OK] df disponível\n'
        if command -v timeout >/dev/null 2>&1; then
            read_disk_sample
            if ((disk_total > 0)); then printf '[OK] Leitura do disco raiz\n'
            else printf '[AVISO] Disco raiz indisponível; painel continuará sem essa métrica\n'; fi
        fi
    else printf '[AVISO] df ausente; disco ficará indisponível\n'; fi
    if read_cpu_sample; then printf '[OK] CPU: /proc/stat legível (uso exige duas amostras)\n'
    else printf '[AVISO] CPU indisponível; painel indicará a ausência\n'; fi
    read_memory_sample
    if ((mem_total > 0)); then printf '[OK] RAM: /proc/meminfo legível\n'
    else printf '[AVISO] RAM indisponível\n'; fi
    if ((swap_total == 0)); then printf '[OK] Swap desativada\n'
    elif ((swap_total > 0)); then printf '[OK] Swap configurada\n'
    else printf '[AVISO] Swap indisponível\n'; fi
    read_system_sample
    if ((uptime_seconds >= 0)) && [[ $load_average != Indisponível ]]; then printf '[OK] Uptime e carga média legíveis\n'
    else printf '[AVISO] Uptime ou carga média indisponível\n'; fi
    if [[ -t 0 && -t 1 && ${TERM:-dumb} != dumb ]]; then printf '[OK] Terminal interativo ANSI (TERM=%s)\n' "$TERM"
    else printf '[AVISO] Sem terminal ANSI interativo; --check funciona sem TTY\n'; fi
    printf '[INFO] Docker não é utilizado nesta etapa. Root não é necessário.\n'
    printf '[INFO] Nenhum pacote instalado, arquivo gravado ou configuração alterada.\n'
    return "$failed"
}

show_usage() {
    printf 'VR Server Manager v%s\n' "$VERSION"
    printf 'Uso: bash vr-server-manager.sh [--check | --help | --version]\n'
    printf 'Sem argumentos: painel interativo, somente leitura, atualização a cada 2s.\n'
    printf 'Mínimo: terminal ANSI %sx%s, Linux, Bash 4.4+, stty e timeout.\n' "$MIN_COLUMNS" "$MIN_ROWS"
}

main() {
    set -u
    set -o pipefail
    initialize_state
    # C.UTF-8 faz parte do Ubuntu: largura correta para textos em portugues.
    export LC_ALL=C.UTF-8
    if (($# > 1)); then show_usage >&2; return 2; fi
    case ${1:-} in
        --check) check_compatibility; return $? ;;
        --help|-h) show_usage; return 0 ;;
        --version) printf '%s\n' "$VERSION"; return 0 ;;
        '') ;;
        *) printf 'Opção inválida: %s\n' "$1" >&2; show_usage >&2; return 2 ;;
    esac
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf 'A interface requer entrada e saída interativas. Use --check.\n' >&2
        return 2
    fi
    if ! is_linux; then printf 'Requer Linux/Ubuntu. Use --check para verificar compatibilidade.\n' >&2; return 1; fi
    if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
        printf 'Necessário Bash 4.4 ou posterior. Use --check.\n' >&2; return 1
    fi
    local command_name
    for command_name in stty timeout; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Comando padrão ausente: %s. Nada foi instalado. Use --check.\n' "$command_name" >&2
            return 1
        fi
    done
    command -v df >/dev/null 2>&1 && have_df=1
    read_identity
    initialize_terminal || return $?
    start_collection
    while ((running)); do
        ((resize_pending)) && read_geometry
        poll_collection
        now_milliseconds
        if [[ -z $worker_pid ]] && ((NOW_MS >= next_refresh)); then start_collection; fi
        ((dirty)) && render_frame
        if read_key; then handle_key; fi
    done
    return 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
    exit $?
fi
