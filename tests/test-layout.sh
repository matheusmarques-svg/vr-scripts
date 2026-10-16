#!/usr/bin/env bash
# Regressoes visuais deterministicas, sem TTY, Docker, Python ou pacotes extras.
set -u
set -o pipefail
export LC_ALL=C.UTF-8
cd -- "${BASH_SOURCE[0]%/*}/.." || exit 1
source ./vr-server-manager.sh

passed=0
failed=0
context=''
frame_file=$(mktemp) || exit 1
trap 'rm -f -- "$frame_file"' EXIT
assert() {
    local description=$1
    shift
    if "$@"; then
        ((passed += 1))
    else
        printf 'FAIL %s: %s\n' "$context" "$description"
        ((failed += 1))
    fi
}
equal() { [[ $1 == "$2" ]]; }
contains() { [[ $1 == *"$2"* ]]; }
not_contains() { [[ $1 != *"$2"* ]]; }
matches() { [[ $1 =~ $2 ]]; }

fixture() {
    initialize_state
    host_name='servidor-producao-com-nome-bastante-longo'
    user_name='administrador-com-nome-bastante-longo'
    distribution='Ubuntu Server de demonstracao com identificacao longa'
    cpu_description='entre amostras'
    uptime_seconds=90061
    load_average='1.20/0.50/0.30'
    last_update=23:59:58
    update_count=12345678
    status_message='Somente monitoramento. Selecione um módulo.'
}

state_fixture() {
    local state=$1 percent
    mem_total=8388608; swap_total=2097152
    disk_total=21474836480
    case $state in
        unavailable)
            cpu_percent=-1; cpu_description='Indisponível'
            mem_total=-1; mem_available=-1; swap_total=-1; swap_free=-1
            disk_total=-1; disk_used=-1; disk_available=-1; disk_percent=-1
            ;;
        swapoff)
            cpu_percent=25; mem_available=6291456; swap_total=0; swap_free=0
            disk_used=5368709120; disk_available=16106127360; disk_percent=25
            ;;
        large)
            # 4 TiB de RAM e 10 TiB de disco: detalhes maiores que os usuais.
            cpu_percent=90; mem_total=4294967296; mem_available=1073741824
            swap_total=1073741824; swap_free=268435456
            disk_total=10995116277760; disk_used=8246337208320
            disk_available=2748779069440; disk_percent=75
            ;;
        *)
            percent=$state; cpu_percent=$percent
            # Totais divisiveis por 100 evitam que a fixture de 70% vire 69%
            # ao converter a quantidade inteira de kB de volta em percentual.
            mem_total=10000000; swap_total=2000000
            mem_available=$((mem_total - mem_total * percent / 100))
            swap_free=$((swap_total - swap_total * percent / 100))
            disk_used=$((disk_total * percent / 100))
            disk_available=$((disk_total - disk_used)); disk_percent=$percent
            ;;
    esac
}

capture_frame() {
    render_frame > "$frame_file"
    RENDERED=$(< "$frame_file")
}

inspect_metric() {
    local line=$1 after_open before_open before_percent
    METRIC_BAR=''; METRIC_START=-1; METRIC_PERCENT_END=-1
    [[ $line == *'['*']'*'%'* ]] || return 1
    before_open=${line%%\[*}; after_open=${line#*\[}
    METRIC_START=${#before_open}
    METRIC_BAR=${after_open%%\]*}
    [[ -n $METRIC_BAR && $METRIC_BAR != *[!#?\-]* ]] || return 1
    before_percent=${line%%\%*}; METRIC_PERCENT_END=${#before_percent}
    return 0
}

assert_geometry() {
    local row line first_start=-1 first_width=-1 first_percent=-1 label
    local -a labels=(CPU RAM SWAP DISCO)
    for ((row=1; row<=rows; row++)); do
        line=${LAST_FRAME[row]:-}
        assert "linha $row cabe na margem direita" test "${#line}" -le "$((columns - 1))"
        assert "linha $row preserva texto sem ANSI" not_contains "$line" "$ESC"
        assert "frame logico da linha $row preserva texto sem ANSI" not_contains "${FRAME[row]:-}" "$ESC"
    done
    for ((row=5; row<=8; row++)); do
        line=${LAST_FRAME[row]:-}; label=${labels[row-5]}
        assert "indicador $label identificado" matches "$line" "^$label[[:space:]]+\\["
        if inspect_metric "$line"; then
            ((passed += 1))
            if ((first_start < 0)); then
                first_start=$METRIC_START; first_width=${#METRIC_BAR}
                first_percent=$METRIC_PERCENT_END
            fi
            assert "$label alinha inicio da barra" equal "$METRIC_START" "$first_start"
            assert "$label usa mesma largura de barra" equal "${#METRIC_BAR}" "$first_width"
            assert "$label alinha percentual" equal "$METRIC_PERCENT_END" "$first_percent"
            assert "$label reserva uma barra legivel" test "${#METRIC_BAR}" -ge 3
        else
            assert "$label tem barra e percentual visiveis" false
        fi
    done
    BAR_GEOMETRY="$first_start/$first_width/$first_percent"
    assert 'header mantem prefixo e inicio do host' contains "${LAST_FRAME[2]:-}" 'Host: s'
    assert 'header mantem prefixo e inicio do usuario' contains "${LAST_FRAME[2]:-}" 'Usuário: a'
    assert 'atualizacao mantem horario completo' contains "${LAST_FRAME[9]:-}" 23:59:58
    assert 'atualizacao mantem contador completo' contains "${LAST_FRAME[9]:-}" '#12345678'
    for label in Enter Tab Esc F1 R Q; do
        assert "rodape mantem atalho $label" matches "${LAST_FRAME[rows]:-}" "(^|[^[:alnum:]])$label([^[:alnum:]]|$)"
    done
}

# Observa o texto final e compara estados; nao replica o calculo da largura.
for width in 32 40 48 64 80 100 120; do
    for height in 16 20 24 30; do
        reference_geometry=''
        for state in 0 69 70 89 90 100 unavailable swapoff large; do
            fixture; columns=$width; rows=$height; state_fixture "$state"
            context="${width}x${height}, estado=$state"
            capture_frame
            assert_geometry
            if [[ -z $reference_geometry ]]; then reference_geometry=$BAR_GEOMETRY; fi
            assert 'geometria das barras permanece entre estados' equal "$BAR_GEOMETRY" "$reference_geometry"
            capture_frame
            assert 'frame identico nao emite redesenho' test ! -s "$frame_file"
        done
    done
done

# Numeros conhecidos comprovam que o modo compacto preserva os dois dados.
for width in 32 40 48; do
    fixture; columns=$width; rows=16; state_fixture swapoff
    context="detalhes compactos ${width}x16"
    capture_frame
    assert 'RAM mostra 2 GiB usados de 8 GiB totais' matches "${LAST_FRAME[6]}" '2([.]0)?G/8([.]0)?G'
    assert 'disco mostra 5 GiB usados' matches "${LAST_FRAME[8]}" 'U5([.]0)?G'
    assert 'disco mostra 15 GiB disponiveis' matches "${LAST_FRAME[8]}" 'L15([.]0)?G'
    assert 'swap sem area informa Desativada por inteiro' contains "${LAST_FRAME[7]}" Desativada
done

# Le as sequencias ANSI emitidas e acompanha a cor de cada caractere visivel.
# Brackets podem compartilhar a cor da barra; labels e detalhes devem usar a
# cor padrao do terminal. Isto cobre tambem terminais de fundo claro.
assert_metric_style() {
    local row=$1 expected=$2 plain=${LAST_FRAME[$1]} segment char sequence code
    local position=0 color='' opening closing valid=1 bar_colored=1
    inspect_metric "$plain" || { assert 'metrica estilizada tem barra' false; return; }
    opening=$METRIC_START; closing=$((opening + ${#METRIC_BAR} + 1))
    segment=${RENDERED#*"$ESC[$row;1H"}
    [[ $segment != "$RENDERED" ]] || { assert 'linha estilizada foi emitida' false; return; }
    segment=${segment%%"$ESC[K"*}
    while [[ -n $segment ]]; do
        if [[ $segment == "$ESC["* ]]; then
            sequence=${segment#"$ESC["}; sequence=${sequence%%m*}
            [[ $sequence != "$segment" && $segment == "$ESC[${sequence}m"* ]] || { valid=0; break; }
            segment=${segment#"$ESC[${sequence}m"}
            sequence=${sequence//;/ }
            for code in $sequence; do
                case $code in
                    0|39) color='' ;;
                    3[0-7]|9[0-7]) color=$code ;;
                esac
            done
        else
            char=${segment:0:1}; segment=${segment:1}
            if ((position < opening || position > closing)); then
                [[ -z $color ]] || valid=0
            elif ((position > opening && position < closing)); then
                [[ $color == "$expected" ]] || bar_colored=0
            fi
            ((position += 1))
        fi
    done
    assert "linha $row colore somente a barra" equal "$valid" 1
    assert "linha $row usa cor correspondente ao estado" equal "$bar_colored" 1
}

for state in 0 69 70 89 90 100 unavailable; do
    fixture; columns=80; rows=24; state_fixture "$state"
    context="cores, estado=$state"
    case $state in 0|69) expected_color=32;; 70|89) expected_color=33;; 90|100) expected_color=31;; unavailable) expected_color='';; esac
    capture_frame
    for row in 5 6 7 8; do assert_metric_style "$row" "$expected_color"; done
done

context='navegacao e atualizacao 32x16'
fixture; columns=32; rows=16; state_fixture 69
selected_module=5
capture_frame
assert 'menu curto mantem ultimo item selecionado visivel' contains "${LAST_FRAME[*]}" '6. Configurações'
menu_navigation="${LAST_FRAME[10]:-} ${LAST_FRAME[rows-3]:-}"
assert 'menu curto mostra posicao ou indicacao de rolagem' matches "$menu_navigation" '([1-6].*/6|[Rr]ol|↑|↓|Cima/Baixo)'
before_selection=$selected_module
before_focus=$focus
cpu_percent=70; last_update=23:59:59; ((update_count += 1))
capture_frame
assert 'atualizacao preserva selecao e foco do menu' equal "$selected_module/$focus" "$before_selection/$before_focus"
assert 'atualizacao normal nao limpa tela inteira' not_contains "$RENDERED" "$ESC[2J"
assert 'atualizacao redesenha linhas que mudaram' test -s "$frame_file"
KEY=TAB; handle_key
capture_frame
assert 'Tab transfere destaque para ajuda' equal "${LAST_STYLES[rows-3]:-}" "$SELECTED"
KEY=HELP; handle_key
capture_frame
assert 'ajuda compacta mostra rolagem' matches "${LAST_FRAME[10]:-} ${LAST_FRAME[rows-3]:-}" '([0-9]+/[0-9]+|[Rr]ol|↑|↓|Cima/Baixo)'
help_before=${LAST_FRAME[11]:-}
KEY=DOWN; handle_key
capture_frame
assert 'rolagem muda conteudo de ajuda' not_contains "${LAST_FRAME[11]:-}" "$help_before"
help_position=$help_offset
cpu_percent=89; ((update_count += 1))
capture_frame
assert 'atualizacao preserva rolagem da ajuda' equal "$help_offset" "$help_position"
KEY=BACK; handle_key
capture_frame
assert 'fechar ajuda restaura selecao e foco' equal "$screen/$selected_module/$focus" menu/5/1
assert 'foco restaurado continua visivel' equal "${LAST_STYLES[rows-3]:-}" "$SELECTED"
KEY=TAB; handle_key
KEY=ENTER; handle_key
capture_frame
assert 'modulo preserva informacao Em desenvolvimento' contains "${LAST_FRAME[*]}" 'Em desenvolvimento'
before_selection=$selected_module; before_focus=$focus
cpu_percent=90; ((update_count += 1))
capture_frame
assert 'atualizacao preserva tela e foco do modulo' equal "$screen/$selected_module/$focus" "module/$before_selection/$before_focus"
KEY=BACK; handle_key
capture_frame
assert 'voltar preserva modulo selecionado' equal "$screen/$selected_module" menu/5

# Todos os alertas devem ser acessiveis mesmo quando a linha nao comporta a lista.
context='rotacao de alertas 32x16'
fixture; columns=32; rows=16; state_fixture unavailable
collector_failed=1; uptime_seconds=-1; load_average=Indisponível
visible_alerts=''
for ((update_count=0; update_count<8; update_count++)); do
    capture_frame
    visible_alerts+=" ${LAST_FRAME[rows-1]:-}"
    assert 'alerta compacto informa posicao e total' matches "${LAST_FRAME[rows-1]:-}" '[0-9]+/[0-9]+'
done
for indicator in coleta CPU RAM swap disco uptime load; do
    assert "rotacao permite ler alerta de $indicator" contains "$visible_alerts" "$indicator"
done

# Falhas consecutivas tambem devem percorrer todos os alertas, mesmo sem
# qualquer coleta bem-sucedida ou mudanca no horario da ultima atualizacao.
context='rotacao durante falhas persistentes 32x16'
fixture; columns=32; rows=16; state_fixture 25
update_count=0; last_update=aguardando
visible_alerts=''
for ((attempt=0; attempt<8; attempt++)); do
    unavailable_snapshot
    capture_frame
    visible_alerts+=" ${LAST_FRAME[rows-1]:-}"
    assert 'falha nao incrementa contador de coletas bem-sucedidas' equal "$update_count" 0
    assert 'falha nao inventa horario de ultima coleta' equal "$last_update" aguardando
    assert 'contador de sucesso permanece visivel como zero' contains "${LAST_FRAME[9]:-}" '#0'
    assert 'alerta de falha informa posicao e total' matches "${LAST_FRAME[rows-1]:-}" '[0-9]+/[0-9]+'
done
for indicator in coleta CPU RAM swap disco uptime load; do
    assert "falhas persistentes permitem ler alerta de $indicator" contains "$visible_alerts" "$indicator"
done

# Simula somente a resposta de stty; nao afirma validar um TTY/SSH real.
context='resize preserva estado'
fixture; columns=80; rows=24; state_fixture 70
selected_module=5; focus=1; screen=help; help_offset=8
capture_frame
exec {terminal_fd}<>/dev/null
stty() { printf '%s\n' "$resize_geometry"; }
for resize_geometry in '16 32' '30 120' '16 32'; do
    before_navigation="$screen/$selected_module/$focus"
    read_geometry > "$frame_file"
    assert 'resize permite uma limpeza completa' contains "$(< "$frame_file")" "$ESC[2J"
    capture_frame
    assert 'render apos resize nao repete limpeza completa' not_contains "$RENDERED" "$ESC[2J"
    assert 'resize preserva tela, selecao e foco' equal "$screen/$selected_module/$focus" "$before_navigation"
    assert_geometry
    capture_frame
    assert 'frame apos resize tambem evita redesenho identico' test ! -s "$frame_file"
done
unset -f stty
exec {terminal_fd}>&-
terminal_fd=''

printf 'Layout: %d verificacoes passaram; %d falharam.\n' "$passed" "$failed"
((failed == 0))
