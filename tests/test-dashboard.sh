#!/usr/bin/env bash
# Testes de logica e integracao do coletor. Nao requer Docker, root ou pacotes.
set -u
set -o pipefail
export LC_ALL=C.UTF-8
cd -- "${BASH_SOURCE[0]%/*}/.." || exit 1
source ./vr-server-manager.sh
passed=0
failed=0
fixture_dir=$(mktemp -d) || exit 1
finish_tests() {
    [[ -z ${worker_pid:-} ]] || { kill -KILL "$worker_pid" 2>/dev/null || :; close_worker; }
    # Apenas os arquivos conhecidos criados por esta suite no diretorio temporario.
    rm -f -- "$fixture_dir/stat" "$fixture_dir/meminfo" "$fixture_dir/uptime" \
        "$fixture_dir/loadavg" "$fixture_dir/frame" "$fixture_dir/trace"
    rmdir -- "$fixture_dir"
}
trap finish_tests EXIT
assert() {
    local description=$1
    shift
    if "$@"; then printf 'OK   %s\n' "$description"; ((passed += 1))
    else printf 'FAIL %s\n' "$description"; ((failed += 1)); fi
}
equal() { [[ $1 == "$2" ]]; }
contains() { [[ $1 == *"$2"* ]]; }

initialize_state
PROC_ROOT=$fixture_dir
printf 'cpu 100 20 30 400 50 10 5 5 80 10\n' > "$fixture_dir/stat"
read_cpu_sample
assert 'CPU ignora guest/guest_nice duplicados' equal "$cpu_total" 620
assert 'CPU considera idle + iowait' equal "$cpu_idle" 450
calculate_cpu "$cpu_total" "$cpu_idle"
assert 'Primeira amostra nao inventa 0%%' equal "$cpu_percent" -1
calculate_cpu 720 500
assert 'CPU usa deltas entre amostras (50%%)' equal "$cpu_percent" 50
calculate_cpu 720 500
assert 'Delta nulo indica indisponibilidade' equal "$cpu_percent" -1
calculate_cpu 800 490
assert 'Regressao de idle indica indisponibilidade' equal "$cpu_percent" -1
calculate_cpu 900 540
assert 'CPU recupera depois de amostra invalida' equal "$cpu_percent" 50
calculate_cpu 100 50
assert 'Regressao de contadores nao vira 0%%' equal "$cpu_percent" -1
calculate_cpu -1 -1
assert 'Ausencia de CPU reinicia a base' equal "$cpu_previous_total" -1
printf 'cpu 100 ruim 30 400\n' > "$fixture_dir/stat"
read_cpu_sample
assert 'Contador CPU malformado e rejeitado' equal "$cpu_total" -1
printf 'cpu 100 020 030 400\n' > "$fixture_dir/stat"
read_cpu_sample
assert 'Contadores com zeros iniciais sao decimais' equal "$cpu_total" 550

printf 'MemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$fixture_dir/meminfo"
read_memory_sample
assert 'RAM usa MemAvailable' equal "$((mem_total - mem_available))" 600
assert 'Swap ausente e estado valido' equal "$swap_total" 0
render_indicators
assert 'Swap ausente mostra Desativada' contains "${FRAME[7]}" Desativada
printf 'MemTotal: 1000 kB\nMemAvailable: 2000 kB\nSwapTotal: 100 kB\nSwapFree: 101 kB\n' > "$fixture_dir/meminfo"
read_memory_sample
assert 'RAM inconsistente fica indisponivel' equal "$mem_total" -1
assert 'Swap inconsistente fica indisponivel' equal "$swap_total" -1
printf 'MemTotal: 1000 kB\nSwapTotal: 100 kB\nSwapFree: 25 kB\n' > "$fixture_dir/meminfo"
read_memory_sample
assert 'MemAvailable ausente nao simula RAM' equal "$mem_total" -1
assert 'Swap utilizada calculada corretamente' equal "$((swap_total - swap_free))" 75

have_df=0
disk_total=999
read_disk_sample
assert 'df ausente descarta valor antigo' equal "$disk_total" -1
have_df=1
timeout() { printf '1k-blocks Used Avail Use%%\n1000 600 350 64%%\n'; }
read_disk_sample
assert 'Disco usa valores reais retornados pelo df' equal "$disk_used/$disk_available/$disk_percent" 600/350/64
timeout() { return 124; }
read_disk_sample
assert 'Timeout de df nao simula disco vazio' equal "$disk_percent" -1
timeout() { printf 'header\n1000 INVALIDO 0 10%%\n'; }
read_disk_sample
assert 'Disco malformado fica indisponivel' equal "$disk_total" -1
unset -f timeout

printf '90061.51 12345.0\n' > "$fixture_dir/uptime"
printf '1.20 0.50 0.30 1/100 1\n' > "$fixture_dir/loadavg"
read_system_sample
assert 'Uptime lido sem comando externo' equal "$uptime_seconds" 90061
assert 'Load de 1/5/15 minutos' equal "$load_average" 1.20/0.50/0.30
clean_text $'host\033[31m\r\n'
assert 'Identidade do host remove controles' equal "$CLEAN_TEXT" 'host[31m'

# Decodificacao real dos bytes de entrada, sem precisar de um TTY nesta suite.
decode_key() {
    exec {terminal_fd}< <(printf '%s' "$1")
    read_key
    exec {terminal_fd}<&-
    terminal_fd=''
}
decode_key $'\e[A'; assert 'Seta acima CSI' equal "$KEY" UP
decode_key $'\eOB'; assert 'Seta abaixo SS3' equal "$KEY" DOWN
decode_key $'\eOP'; assert 'F1 SS3' equal "$KEY" HELP
decode_key $'\e[11~'; assert 'F1 CSI' equal "$KEY" HELP
decode_key $'\e[[A'; assert 'F1 console Linux' equal "$KEY" HELP
decode_key $'\e'; assert 'Esc isolado' equal "$KEY" BACK
decode_key $'\n'; assert 'Enter' equal "$KEY" ENTER
decode_key $'\t'; assert 'Tab' equal "$KEY" TAB
decode_key Q; assert 'Atalho Q' equal "$KEY" QUIT
decode_key r; assert 'Atalho R' equal "$KEY" REFRESH
decode_key $'\e[99~'; assert 'Escape desconhecido nao seleciona modulo' equal "$KEY" ''

initialize_state
KEY=DOWN; handle_key
assert 'Navegacao seleciona segundo modulo' equal "$selected_module" 1
KEY=ENTER; handle_key
assert 'Enter abre tela do modulo' equal "$screen" module
render_module
assert 'Modulo informa Em desenvolvimento' equal "${FRAME[11]}" 'Em desenvolvimento'
KEY=TAB; handle_key
KEY=ENTER; handle_key
assert 'Tab e Enter abrem ajuda contextual' equal "$screen" help
KEY=BACK; handle_key
assert 'Ajuda devolve foco e tela' equal "$screen/$focus/$selected_module" module/1/1
KEY=BACK; handle_key
assert 'Esc retorna ao menu preservando selecao' equal "$screen/$selected_module" menu/1
KEY=UP; handle_key
KEY=UP; handle_key
assert 'Seta acima circula pelos seis modulos' equal "$selected_module" 5
KEY=QUIT; handle_key
assert 'Q encerra o laco' equal "$running" 0

initialize_state
columns=32; rows=16; selected_module=5
render_frame > "$fixture_dir/frame"
assert 'Layout 32x16 mantem item selecionado visivel' contains "${LAST_FRAME[*]}" '6. Configurações'
assert 'Layout compacto preserva CPU/RAM/swap/disco' equal "${FRAME[5]:0:3}/${FRAME[6]:0:3}/${FRAME[7]:0:4}/${FRAME[8]:0:1}" CPU/RAM/Swap//
longest=0
for line in "${LAST_FRAME[@]}"; do ((${#line} > longest)) && longest=${#line}; done
assert 'Linhas compactas nao ultrapassam margem direita' test "$longest" -le 31
render_frame > "$fixture_dir/frame"
assert 'Frame identico nao e redesenhado' test ! -s "$fixture_dir/frame"
columns=20; rows=8
render_frame > "$fixture_dir/frame"
assert 'Terminal pequeno mostra aviso' contains "${FRAME[*]}" 'Mínimo: 32x16'
assert 'Resize nao altera selecao' equal "$selected_module" 5

# O coletor usa pipes e processos reais. A fixture muda entre as duas coletas.
initialize_state
PROC_ROOT=$fixture_dir
have_df=0
selected_module=3; screen=help; previous_screen=module; focus=1
printf 'cpu 100 0 0 100 0 0 0 0\n' > "$fixture_dir/stat"
printf 'MemTotal: 1000 kB\nMemAvailable: 800 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$fixture_dir/meminfo"
now_milliseconds; began=$NOW_MS
start_collection
KEY=BACK; handle_key
assert 'Teclado responde enquanto coletor esta ativo' equal "$screen" module
deadline=$((SECONDS + 5))
while [[ -n $worker_pid ]] && ((SECONDS < deadline)); do poll_collection; sleep 0.02; done
assert 'Coprocesso entrega primeira amostra' equal "$update_count" 1
assert 'CPU inicial continua indisponivel' equal "$cpu_percent" -1
assert 'Coleta nao muda selecao ou foco' equal "$selected_module/$focus" 3/0
printf 'cpu 200 0 0 200 0 0 0 0\n' > "$fixture_dir/stat"
printf 'MemTotal: 1000 kB\nMemAvailable: 300 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$fixture_dir/meminfo"
while :; do
    now_milliseconds
    ((NOW_MS >= next_refresh)) && break
    sleep 0.02
done
second_start=$NOW_MS
start_collection
deadline=$((SECONDS + 5))
while [[ -n $worker_pid ]] && ((SECONDS < deadline)); do poll_collection; sleep 0.02; done
assert 'Intervalo padrao e 2 segundos' equal "$REFRESH_SECONDS" 2
assert 'Segundo disparo respeita 2s (Bash 5)' test "$((second_start - began))" -ge 1950
assert 'CPU atualiza na segunda coleta' equal "$cpu_percent" 50
assert 'RAM atualiza na segunda coleta' equal "$((mem_total - mem_available))" 700
assert 'Atualizacao em outra tela preserva foco' equal "$screen/$selected_module/$focus" module/3/0

# Coleta lenta nao bloqueia o teclado; um coletor travado e descartado.
collect_snapshot() { sleep 1; printf '200|100|1000|500|0|0|-1|-1|-1|-1|100|0/0/0\n'; }
now_milliseconds; began=$NOW_MS
start_collection
KEY=HELP; handle_key
now_milliseconds
assert 'Coleta lenta nao bloqueia abertura de ajuda' test "$((NOW_MS - began))" -lt 500
deadline=$((SECONDS + 5))
while [[ -n $worker_pid ]] && ((SECONDS < deadline)); do poll_collection; sleep 0.02; done
assert 'Metricas chegam mesmo com ajuda aberta' equal "$screen/$update_count" help/3
collect_snapshot() {
    printf '300|150|1000|'
    sleep 0.05
    printf '400|0|0|-1|-1|-1|-1|100|0/0/0\n'
}
start_collection
deadline=$((SECONDS + 5))
while [[ -n $worker_pid ]] && ((SECONDS < deadline)); do poll_collection; sleep 0.02; done
assert 'Registro dividido entre leituras nao perde dados' equal "$update_count/$mem_available/$cpu_percent" 4/400/50
collect_snapshot() { sleep 1; }
start_collection
worker_started=$((SECONDS - 3))
poll_collection
assert 'Watchdog descarta coletor sem resposta' equal "$collector_failed/$worker_pid/$cpu_percent" 1//-1

output=$(bash ./vr-server-manager.sh 2>&1); result=$?
assert 'Saida nao interativa e rejeitada' equal "$result" 2
assert 'Saida nao interativa orienta --check' contains "$output" --check
assert 'Saida nao interativa nao emite ANSI' equal "${output//$'\e'/}" "$output"
output=$(bash ./vr-server-manager.sh --help); result=$?
assert 'Ajuda funciona sem TTY' equal "$result" 0
output=$(bash ./vr-server-manager.sh --opcao-invalida 2>&1); result=$?
assert 'Argumento invalido retorna 2' equal "$result" 2
output=$(bash ./vr-server-manager.sh --check extra 2>&1); result=$?
assert 'Argumentos extras nao sao ignorados' equal "$result" 2

# Qualquer tentativa de Docker deixa uma evidencia. Funcoes exportadas sao
# herdadas pelo Bash filho, mesmo se Docker nao estiver instalado no sistema.
TRACE_FILE=$fixture_dir/trace
export TRACE_FILE
docker() { printf 'Docker chamado\n' >> "$TRACE_FILE"; return 1; }
export -f docker
output=$(HOME="$fixture_dir" bash ./vr-server-manager.sh --check 2>&1)
assert '--check nao chama Docker' test ! -e "$TRACE_FILE"
assert '--check nao cria pasta .vr' test ! -e "$fixture_dir/.vr"
assert '--check nao cria estado ou logs' test ! -e "$fixture_dir/.local"
assert '--check nao emite ANSI' equal "${output//$'\e'/}" "$output"
unset -f docker

command() {
    if [[ ${1:-} == -v && ${2:-} == stty ]]; then return 1; fi
    builtin command "$@"
}
export -f command
output=$(bash ./vr-server-manager.sh --check 2>&1)
assert 'Dependencia ausente gera mensagem clara' contains "$output" 'Comando padrão ausente: stty'
unset -f command

# Verifica os handlers e as sequencias de restauracao sem alegar um TTY real.
simulate_exit() (
    initialize_state
    terminal_active=1; terminal_saved='estado-original'
    exec {terminal_fd}<>/dev/null
    stty() { printf '%s\n' "$1" > "$fixture_dir/trace"; }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    case $1 in
        normal) exit 0 ;;
        failure) exit 7 ;;
        INT) kill -INT "$BASHPID" ;;
        TERM) kill -TERM "$BASHPID" ;;
    esac
)
for case_name in normal failure INT TERM; do
    case $case_name in normal) expected=0;; failure) expected=7;; INT) expected=130;; TERM) expected=143;; esac
    output=$(simulate_exit "$case_name"); result=$?
    assert "Handler $case_name preserva codigo de saida" equal "$result" "$expected"
    assert "Handler $case_name restaura estado salvo via stty (simulado)" equal "$(< "$fixture_dir/trace")" estado-original
    assert "Handler $case_name restaura cursor e tela" contains "$output" $'\e[0m\e[?25h\e[?1049l'
done

printf '\nResultado: %d passaram; %d falharam.\n' "$passed" "$failed"
((failed == 0))
