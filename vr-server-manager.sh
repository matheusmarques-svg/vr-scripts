#!/usr/bin/env bash
# VR Server Manager v1.0.0 | Bash only | Ubuntu
# No Python, pip, venv, Textual, or external package installation.
set -uo pipefail
export LC_ALL=C
VERSION=1.0.0
VR_HOME="${VR_HOME:-$HOME/.vr}"
APP_DIR="${APP_DIR:-$HOME/.local/state/vr-server-manager}"
LOG_FILE="$APP_DIR/audit.log"
REFRESH="${REFRESH:-3}"
mkdir -p "$APP_DIR" 2>/dev/null || true
if [[ -t 1 ]]; then GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'; else GREEN=''; RED=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''; fi
info(){ printf '%s\n' "$*"; }
warn(){ printf '%sAviso: %s%s\n' "$YELLOW" "$*" "$RESET"; }
audit(){ printf '%s | user=%s | %s\n' "$(date -Is)" "$(id -un)" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
pause(){ read -r -p 'Enter para continuar...' _ || true; }
clear_screen(){ [[ -t 1 ]] && clear || true; }
canon(){ realpath -m -- "$1" 2>/dev/null; }
inside_vr(){ local p root; p=$(canon "$1") || return 1; root=$(canon "$VR_HOME") || return 1; [[ "$p" == "$root" || "$p" == "$root/"* ]]; }
docker_ok(){ command -v docker >/dev/null 2>&1 && docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; }
compose_ok(){ docker compose version >/dev/null 2>&1; }
header(){ printf '%s%sVR SERVER MANAGER%s  v%s   | host: %s\n' "$BOLD" "$CYAN" "$RESET" "$VERSION" "$(hostname)"; printf 'Ambiente: %s   | usuário: %s\n' "$VR_HOME" "$(id -un)"; printf '%s\n' '------------------------------------------------------------'; }
percent_bar(){ local v="${1:-0}" n=0 i; [[ "$v" =~ ^[0-9]+$ ]] && n=$v; ((n>100)) && n=100; printf '['; for ((i=0;i<20;i++)); do if ((i<n/5)); then printf '#'; else printf '.'; fi; done; printf '] %3d%%' "$n"; }
mem_info(){ awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}/^SwapTotal:/{st=$2}/^SwapFree:/{sf=$2}END{if(t>0)printf "RAM: %.1f / %.1f GiB (%d%%)\n",(t-a)/1048576,t/1048576,100*(t-a)/t; if(st>0)printf "SWAP: %.1f / %.1f GiB (%d%%)\n",(st-sf)/1048576,st/1048576,100*(st-sf)/st;else print "SWAP: desativada"}' /proc/meminfo; }
cpu_sample(){ local u1 n1 s1 u2 n2 s2; read -r _ u1 n1 s1 _ < /proc/stat; local idle1 total1 idle2 total2; read -ra a < /proc/stat; idle1=${a[4]:-0}; total1=0; for ((i=1;i<${#a[@]};i++)); do ((total1+=${a[i]:-0})); done; sleep 0.25; read -ra a < /proc/stat; idle2=${a[4]:-0}; total2=0; for ((i=1;i<${#a[@]};i++)); do ((total2+=${a[i]:-0})); done; local dt=$((total2-total1)) di=$((idle2-idle1)); if ((dt>0)); then echo $(((dt-di)*100/dt)); else echo 0; fi; }
# Use Compose's own config-file labels as the authority, never just name prefix.
declare -a IDS=() NAMES=() STATES=() KINDS=() PROJECTS=() SERVICES=() CONFIGS=()
refresh_containers(){
 IDS=(); NAMES=(); STATES=(); KINDS=(); PROJECTS=(); SERVICES=(); CONFIGS=()
 docker_ok || return 0
 local id name status project service configs mounts path match cname allowed
 while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  name=$(docker inspect -f '{{.Name}}' "$id" 2>/dev/null) || continue; name=${name#/}
  status=$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null) || continue
  project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id" 2>/dev/null || true)
  service=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$id" 2>/dev/null || true)
  configs=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$id" 2>/dev/null || true)
  [[ "$project" == '<no value>' ]] && project=''; [[ "$service" == '<no value>' ]] && service=''; [[ "$configs" == '<no value>' ]] && configs=''
  allowed=0
  if [[ -n "$project" && -n "$service" && -n "$configs" ]]; then
    IFS=',' read -r -a cfiles <<< "$configs"
    for path in "${cfiles[@]}"; do inside_vr "$path" && allowed=1; done
    if ((allowed)); then KINDS+=(compose); else continue; fi
  else
    # Standalone docker-run containers are allowed only if an actual bind source is in ~/.vr
    # and the name is in a constrained known inventory.
    case "$name" in vr-agente|vr-agente-updater|vr-agente-versao|vrmaster-atualizacao|vrmasterartifactserver) ;; *) continue;; esac
    mounts=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{println .Source}}{{end}}{{end}}' "$id" 2>/dev/null || true)
    while IFS= read -r path; do [[ -n "$path" ]] && inside_vr "$path" && allowed=1; done <<< "$mounts"
    ((allowed)) || continue
    KINDS+=(standalone)
  fi
  IDS+=("$id"); NAMES+=("$name"); STATES+=("$status"); PROJECTS+=("$project"); SERVICES+=("$service"); CONFIGS+=("$configs")
 done < <(docker ps -aq --no-trunc 2>/dev/null)
}
select_container(){
 refresh_containers
 if ((${#IDS[@]}==0)); then warn 'Nenhum container autorizado encontrado dentro de ~/.vr (ou Docker indisponível).'; return 1; fi
 printf '\n%-4s %-28s %-12s %-12s %s\n' 'N' 'CONTAINER' 'ESTADO' 'ORIGEM' 'SERVIÇO'
 local i opt
 for ((i=0;i<${#IDS[@]};i++)); do printf '%-4s %-28.28s %-12s %-12s %s\n' "$((i+1))" "${NAMES[i]}" "${STATES[i]}" "${KINDS[i]}" "${SERVICES[i]:--}"; done
 read -r -p 'Selecione número (0 volta): ' opt || return 1
 [[ "$opt" =~ ^[0-9]+$ ]] && ((opt>=1 && opt<=${#IDS[@]})) || return 1
 SELECTED=$((opt-1)); return 0
}
critical(){ case "$1" in vrrabbitmq|vrredis|vrintegrador-db|vrservicecontainer|vrservicemanager|vrmaster-atualizacao|vrmasterartifactserver|vr-agente) return 0;; *) return 1;; esac; }
confirm_action(){ local action="$1" name="$2" typed; echo; warn "Ação '$action' pode interromper serviços e usuários. Container: $name"; critical "$name" && warn 'COMPONENTE CRÍTICO: verifique dependências e janela de manutenção.'; read -r -p "Para confirmar, digite exatamente o nome '$name': " typed || return 1; [[ "$typed" == "$name" ]]; }
perform(){
 local action="$1" idx="$2" id="${IDS[idx]}" name="${NAMES[idx]}" kind="${KINDS[idx]}" rc=0
 docker_ok || { warn 'Docker inacessível. Não foi feita nenhuma alteração.'; return 1; }
 # Re-evaluate scope immediately before modifying anything.
 refresh_containers
 local found=-1 i
 for ((i=0;i<${#IDS[@]};i++)); do [[ "${IDS[i]}" == "$id" ]] && found=$i; done
 ((found>=0)) || { warn 'Container saiu do escopo ou não existe mais.'; return 1; }
 idx=$found; kind="${KINDS[idx]}"; name="${NAMES[idx]}"
 confirm_action "$action" "$name" || { info 'Cancelado.'; return 0; }
 audit "REQUEST $action $name id=$id type=$kind"
 if [[ "$kind" == compose ]]; then
   # Use verified absolute compose files and service. Do not use `down`.
   compose_ok || { warn 'Docker Compose indisponível.'; return 1; }
   local -a cmd=(docker compose) cfiles=(); local p
   IFS=',' read -r -a cfiles <<< "${CONFIGS[idx]}"
   for p in "${cfiles[@]}"; do inside_vr "$p" || { warn 'Arquivo Compose fora de .vr. Cancelado.'; return 1; }; [[ -f "$p" ]] || { warn "Compose não encontrado: $p"; return 1; }; cmd+=(-f "$p"); done
   [[ "${SERVICES[idx]}" =~ ^[a-zA-Z0-9_.-]+$ && "${PROJECTS[idx]}" =~ ^[a-zA-Z0-9_.-]+$ ]] || { warn 'Labels Compose inválidas.'; return 1; }
   cmd=(docker compose -p "${PROJECTS[idx]}"); for p in "${cfiles[@]}"; do cmd+=(-f "$p"); done
   cmd+=("$action" "${SERVICES[idx]}")
   "${cmd[@]}" || rc=$?
 else
   docker "$action" "$id" || rc=$?
 fi
 audit "RESULT $action $name rc=$rc"; return "$rc"
}
container_menu(){ local idx choice; while true; do clear_screen; header; select_container || { pause; return; }; idx=$SELECTED; clear_screen; header; printf 'Selecionado: %s (%s)\n' "${NAMES[idx]}" "${KINDS[idx]}"; printf '1) Logs recentes\n2) Detalhes e volumes\n3) Iniciar\n4) Parar\n5) Reiniciar\n0) Voltar\n'; read -r -p 'Opção: ' choice || return; case "$choice" in 1) docker logs --tail 80 --timestamps "${IDS[idx]}" 2>&1 | tail -n 85; pause;; 2) docker inspect --format 'Nome={{.Name}} | Status={{.State.Status}} | Restart={{.RestartCount}}{{range .Mounts}}{{printf "\nVolume: %s -> %s" .Source .Destination}}{{end}}' "${IDS[idx]}"; pause;; 3) perform start "$idx"; pause;; 4) perform stop "$idx"; pause;; 5) perform restart "$idx"; pause;; 0) return;; *) warn 'Opção inválida'; sleep 1;; esac; done; }
find_projects(){ [[ -d "$VR_HOME" ]] || { warn 'Pasta .vr não encontrada'; return; }; local f; while IFS= read -r -d '' f; do case "$(basename "$f")" in docker-compose*.yml|docker-compose*.yaml|compose.yml|compose.yaml) printf '%s\n' "$f";; esac; done < <(find "$VR_HOME" -type f \( -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \) -print0 2>/dev/null); }
projects_menu(){
 local -a projects=(); local f i opt service answer root
 while IFS= read -r f; do [[ -n "$f" ]] && projects+=("$f"); done < <(find_projects)
 clear_screen; header
 if ((${#projects[@]}==0)); then warn 'Nenhum arquivo Compose localizado dentro de ~/.vr'; pause; return; fi
 printf '%s\n' 'PROJETOS COMPOSE (inclusive ainda não iniciados):'
 for ((i=0;i<${#projects[@]};i++)); do printf '%2d) %s\n' "$((i+1))" "${projects[i]}"; done
 read -r -p 'Selecione projeto (0 volta): ' opt || return
 [[ "$opt" =~ ^[0-9]+$ ]] && ((opt>=1 && opt<=${#projects[@]})) || return
 f="${projects[opt-1]}"
 inside_vr "$f" && [[ -f "$f" ]] || { warn 'Projeto fora do escopo ou não encontrado.'; pause; return; }
 compose_ok && docker_ok || { warn 'Docker Compose sem acesso.'; pause; return; }
 local -a cmd=(docker compose --project-directory "$(dirname "$f")" -f "$f") services=()
 while IFS= read -r service; do [[ "$service" =~ ^[a-zA-Z0-9_.-]+$ ]] && services+=("$service"); done < <("${cmd[@]}" config --services 2>/dev/null)
 if ((${#services[@]}==0)); then warn 'Não foi possível validar os serviços do Compose (variáveis ou configuração ausentes).'; pause; return; fi
 printf 'Serviços disponíveis em %s:\n' "$f"
 for ((i=0;i<${#services[@]};i++)); do printf '%2d) %s\n' "$((i+1))" "${services[i]}"; done
 read -r -p 'Número do serviço para subir (0 volta): ' opt || return
 [[ "$opt" =~ ^[0-9]+$ ]] && ((opt>=1 && opt<=${#services[@]})) || return
 service="${services[opt-1]}"
 warn "Subir '$service' pode criar containers, iniciar dependências e afetar serviços. Confira o Compose antes."
 read -r -p "Digite SUBIR para executar docker compose up -d --no-deps $service: " answer || return
 if [[ "$answer" == 'SUBIR' ]]; then
  audit "REQUEST compose up service=$service file=$f"
  "${cmd[@]}" up -d --no-deps "$service"; local rc=$?
  audit "RESULT compose up rc=$rc service=$service file=$f"
 else info 'Cancelado.'; fi
 pause
}

stats_menu(){ clear_screen; header; refresh_containers; if ((${#IDS[@]})); then local id; printf '%s\n' 'Uso atual dos containers gerenciados:'; for id in "${IDS[@]}"; do docker stats --no-stream --format 'NOME={{.Name}} | CPU={{.CPUPerc}} | RAM={{.MemUsage}} | REDE={{.NetIO}}' "$id" 2>/dev/null || true; done; else warn 'Sem containers gerenciados acessíveis.'; fi; pause; }
dashboard(){ local opt cpu disk used total; while true; do clear_screen; header; printf '\n%sMONITORAMENTO DO HOST%s\n' "$BOLD" "$RESET"; cpu=$(cpu_sample); printf 'CPU   '; percent_bar "$cpu"; echo; mem_info; df -h / "$VR_HOME" 2>/dev/null | awk 'NR==1 || !seen[$1]++ {print}' | head -n 4; printf 'LOAD: %s  | UPTIME: %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)" "$(uptime -p 2>/dev/null || echo '?')"; echo; if docker_ok; then refresh_containers; local running=0 i; for ((i=0;i<${#IDS[@]};i++)); do [[ "${STATES[i]}" == running ]] && ((running+=1)); done; printf 'Docker: disponível | Containers .vr: %s (%s rodando)\n' "${#IDS[@]}" "$running"; else warn 'Docker indisponível ou sem permissão. Monitoramento Linux permanece ativo.'; fi; printf '\n1) Containers  2) Projetos Compose  3) Estatísticas Docker  4) Diagnóstico  0) Sair\n'; read -r -t "$REFRESH" -p 'Opção (atualiza automaticamente): ' opt || opt=''; case "$opt" in 1) container_menu;; 2) projects_menu;; 3) stats_menu;; 4) check; pause;; 0|q|Q) break;; esac; done; }
check(){ header; printf 'Bash: %s\n' "$BASH_VERSION"; printf 'Docker CLI: '; command -v docker || echo 'não instalado'; printf 'Docker daemon: '; docker_ok && echo OK || echo 'sem acesso'; printf 'Compose: '; compose_ok && echo OK || echo 'não disponível'; printf '.vr: '; [[ -d "$VR_HOME" ]] && echo encontrada || echo 'não encontrada'; info 'Dependências Python: nenhuma'; }
case "${1:-}" in --check) check;; --help|-h) echo 'Uso: vr-server-manager.sh [--check|--demo|--help]';; --demo) info 'Modo demonstração sem alterações: verifique o monitoramento do host com --check. Para o painel use sem argumentos.'; check;; '') dashboard;; *) echo 'Opção inválida'; exit 2;; esac
