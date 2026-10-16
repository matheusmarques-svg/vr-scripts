#!/usr/bin/env bash
# Aceitacao real no Ubuntu: util-linux script cria um pseudoterminal.
# Nenhum pacote e instalado. Arquivos temporarios pertencem apenas a esta suite.
set -u
set -o pipefail
export LC_ALL=C.UTF-8
cd -- "${BASH_SOURCE[0]%/*}/.." || exit 1
if [[ $OSTYPE != linux* ]]; then
    printf 'NÃO TESTADO: esta suíte requer Linux/Ubuntu e um pseudoterminal.\n'
    exit 77
fi
for tool in script timeout stty; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'NÃO TESTADO: %s ausente. Nada foi instalado.\n' "$tool"
        exit 77
    fi
done
if ((UID == 0)); then
    printf 'NÃO TESTADO: execute esta suíte como usuário comum, sem sudo.\n'
    exit 77
fi
fixture_dir=$(mktemp -d) || exit 1
cleanup_tests() {
    rm -f -- "$fixture_dir/inner.sh" "$fixture_dir/normal" "$fixture_dir/compact" \
        "$fixture_dir/small" "$fixture_dir/interrupt"
    rmdir -- "$fixture_dir"
}
trap cleanup_tests EXIT
cat > "$fixture_dir/inner.sh" <<'INNER'
#!/usr/bin/env bash
trap ':' INT
stty rows "$VR_TEST_ROWS" cols "$VR_TEST_COLS"
before=$(stty -g)
# Qualquer chamada Docker causa falha rastreavel, mesmo se houver daemon local.
docker() { printf '__DOCKER_CALLED__\n' >&2; return 99; }
export -f docker
bash ./vr-server-manager.sh
rc=$?
after=$(stty -g)
if [[ $before == "$after" ]]; then printf '\n__RESTORED__:yes\n'
else printf '\n__RESTORED__:NO\n'; exit 42; fi
printf '__EXIT__:%s\n' "$rc"
exit "$rc"
INNER
passed=0; failed=0
assert_output() {
    local description=$1 content=$2 expected=$3
    if [[ $content == *"$expected"* ]]; then
        printf 'OK   %s\n' "$description"; ((passed += 1))
    else printf 'FAIL %s\n' "$description"; ((failed += 1)); fi
}
normal_keys() {
    sleep 0.8; printf '\033[B\r'
    sleep 2.3; printf '\033OP'
    sleep 2.3; printf '\033'; sleep 0.15
    printf '\t'; sleep 0.15
    printf '\033'; sleep 0.15
    printf 'r'; sleep 0.15; printf 'q'
}
compact_keys() { sleep 0.8; printf '\033[A\r'; sleep 0.4; printf 'q'; }
small_keys() { sleep 0.8; printf 'q'; }
interrupt_keys() { sleep 1; printf '\003'; sleep 0.4; }
run_case() {
    local name=$1 height=$2 width=$3 producer=$4 expected_rc=$5 result output
    export VR_TEST_ROWS=$height VR_TEST_COLS=$width
    # %q conserva caminhos com espacos ou aspas; script recebe um comando fixo.
    local inner_command
    printf -v inner_command 'bash %q' "$fixture_dir/inner.sh"
    "$producer" | TERM=xterm-256color timeout --signal=KILL 15s \
        script --quiet --return --flush --command "$inner_command" /dev/null > "$fixture_dir/$name" 2>&1
    result=${PIPESTATUS[1]}
    output=$(< "$fixture_dir/$name")
    assert_output "$name: stty restaurado exatamente" "$output" '__RESTORED__:yes'
    assert_output "$name: cursor visivel ao sair" "$output" $'\e[?25h'
    assert_output "$name: tela alternativa encerrada" "$output" $'\e[?1049l'
    assert_output "$name: codigo de saida interno" "$output" "__EXIT__:$expected_rc"
    if [[ $result == "$expected_rc" ]]; then ((passed += 1))
    else printf 'FAIL %s: codigo externo %s, esperado %s\n' "$name" "$result" "$expected_rc"; ((failed += 1)); fi
    if [[ $output != *'__DOCKER_CALLED__'* ]]; then ((passed += 1))
    else printf 'FAIL %s: Docker foi chamado\n' "$name"; ((failed += 1)); fi
}
bash -n vr-server-manager.sh || exit 1
bash ./vr-server-manager.sh --check || exit 1
run_case normal 30 100 normal_keys 0
normal_output=$(< "$fixture_dir/normal")
assert_output 'Seta e Enter abrem Projetos Compose' "$normal_output" 'Projetos Compose'
assert_output 'Modulo mostra estado real de desenvolvimento' "$normal_output" 'Em desenvolvimento'
assert_output 'F1 abre ajuda' "$normal_output" 'AJUDA'
assert_output 'CPU real atualiza apos segunda amostra' "$normal_output" 'entre amostras'
assert_output 'Atualizacao continua na ajuda' "$normal_output" '#3'
run_case compact 16 32 compact_keys 0
compact_output=$(< "$fixture_dir/compact")
assert_output 'Terminal 32x16 permite chegar ao sexto modulo' "$compact_output" 'Configurações'
run_case small 8 20 small_keys 0
small_output=$(< "$fixture_dir/small")
assert_output 'Terminal 20x8 informa tamanho minimo' "$small_output" 'Mínimo: 32x16'
run_case interrupt 24 80 interrupt_keys 130
printf '\nResultado TTY: %d passaram; %d falharam.\n' "$passed" "$failed"
((failed == 0))
