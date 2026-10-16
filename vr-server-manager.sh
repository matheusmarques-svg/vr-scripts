#!/usr/bin/env bash
# VR Server Manager | Instalador e inicializador em arquivo único
# Ubuntu 22.04/24.04 | O monitoramento usa Textual e Docker CLI.
# Distribuição via link HTTPS: download uma vez, execute quantas vezes precisar.
set -Eeuo pipefail

VERSION='0.2.0'
PAYLOAD_SHA256='ee6413e64f6b289522c51644deb4dd3900a8fcc5ae6f9c3c8e2ef250f204e475'
APP_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/vr-server-manager"
VENV="$APP_HOME/.venv"
MODE="${1:-}"

info() { printf '[VR Server Manager] %s\n' "$*"; }
fail() { printf '[VR Server Manager] ERRO: %s\n' "$*" >&2; exit 1; }
usage() {
cat <<'HELP'
Uso: vr-server-manager.sh [--demo|--check|--install-only|--version|--help]

Sem argumentos    Abre o painel real (leitura de containers em ~/.vr).
--demo           Abre o painel com dados fictícios; não opera no Docker.
--check          Verifica os requisitos e a permissão de acesso ao Docker.
--install-only   Instala/atualiza componentes sem abrir o painel.
--version        Exibe a versão do lançador.
--help           Exibe esta ajuda.

Se instalado em /opt/vr, executar como usuário normal:
    /opt/vr/vr-server-manager.sh

Requisitos: Ubuntu com Python >= 3.10, módulo python3-venv, rede para
instalar dependências na primeira execução, Docker Engine e Docker Compose.
A ferramenta não altera containers ao abrir. Operações pedem confirmação.
HELP
}

check_python() {
    command -v python3 >/dev/null 2>&1 || fail 'Python3 ausente. Instale pelo apt: sudo apt install python3 python3-venv'
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' || fail 'É necessário Python >= 3.10 (Ubuntu 22.04/24.04).'
}

check_env() {
    info "Versão: $VERSION"
    info "Ambiente: ${VRSM_ROOT:-$HOME/.vr}"
    if command -v python3 >/dev/null; then python3 --version; else info 'Python3: ausente'; fi
    if command -v docker >/dev/null; then
        docker --version || true
        if docker info >/dev/null 2>&1; then info 'Docker: acesso autorizado'; else info 'Docker: sem acesso; confira o daemon e permissões do usuário'; fi
        if docker compose version >/dev/null 2>&1; then docker compose version; else info 'Docker Compose plugin: não encontrado'; fi
    else info 'Docker: ausente'; fi
    if [ -d "${VRSM_ROOT:-$HOME/.vr}" ]; then info 'Diretório .vr: encontrado'; else info 'Diretório .vr: ausente'; fi
}

extract_payload() {
    local temp
    temp="$(mktemp -d)" || fail 'Não consegui criar pasta temporária.'
    trap 'rm -rf "$temp"' RETURN
    cat <<'PAYLOAD_EOF' | base64 --decode > "$temp/payload.tar.gz" || fail 'Falha ao decodificar componentes.'
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
f//8wegfnofn4Xl4Hp6H59f//A8+ivc6AFAAAA==
PAYLOAD_EOF
    printf '%s  %s\n' "$PAYLOAD_SHA256" "$temp/payload.tar.gz" | sha256sum --check --status || fail 'Integridade do pacote inválida.'
    tar -tzf "$temp/payload.tar.gz" >/dev/null || fail 'Pacote interno inválido.'
    tar -xzf "$temp/payload.tar.gz" -C "$temp" --no-same-owner --no-same-permissions || fail 'Falha ao extrair.'
    mkdir -p "$APP_HOME"
    for file in app.py backend.py requirements.txt; do
        [ -f "$temp/$file" ] || fail "Arquivo ausente: $file"
        cp "$temp/$file" "$APP_HOME/$file"
    done
    printf '%s\n' "$PAYLOAD_SHA256" > "$APP_HOME/.payload.sha256"
}

ensure_runtime() {
    check_python
    if [ ! -f "$APP_HOME/.payload.sha256" ] || [ "$(cat "$APP_HOME/.payload.sha256")" != "$PAYLOAD_SHA256" ] || [ ! -f "$APP_HOME/app.py" ]; then
        info 'Preparando arquivos do painel...'
        extract_payload
    fi
    if [ ! -x "$VENV/bin/python" ]; then
        info 'Criando ambiente Python privado (não altera o Python do Ubuntu)...'
        if ! python3 -m venv "$VENV"; then
            fail 'Não foi possível criar ambiente virtual. Rode sudo apt install python3-venv e execute novamente.'
        fi
    fi
    if [ ! -f "$VENV/.vrsm-ready-$PAYLOAD_SHA256" ]; then
        info 'Instalando bibliotecas necessárias na primeira execução...'
        "$VENV/bin/python" -m pip install --disable-pip-version-check -r "$APP_HOME/requirements.txt" || fail 'Não foi possível instalar Textual. Verifique a internet/PyPI.'
        : > "$VENV/.vrsm-ready-$PAYLOAD_SHA256"
    fi
}

case "$MODE" in
    --help|-h) usage; exit 0 ;;
    --version|-v) printf 'VR Server Manager v%s\n' "$VERSION"; exit 0 ;;
    --check) check_env; exit 0 ;;
    ''|--demo|--install-only|--extract-only) ;;
    *) usage >&2; exit 2 ;;
esac
if [ "$MODE" = '--extract-only' ]; then extract_payload; info "Componentes extraídos em $APP_HOME"; exit 0; fi
ensure_runtime
if [ "$MODE" = '--install-only' ]; then info 'Instalação concluída.'; exit 0; fi
if [ "$MODE" = '--demo' ]; then
    info 'Abrindo painel DEMO: nenhuma ação Docker será executada.'
    exec "$VENV/bin/python" "$APP_HOME/app.py" --demo
fi
if ! command -v docker >/dev/null 2>&1; then
    fail 'Docker CLI não encontrado. Use --demo para testar, ou instale Docker.'
fi
if ! docker info >/dev/null 2>&1; then
    fail 'Sem acesso ao Docker. Confira o daemon e a permissão do usuário. Não execute com sudo por padrão.'
fi
exec "$VENV/bin/python" "$APP_HOME/app.py"
