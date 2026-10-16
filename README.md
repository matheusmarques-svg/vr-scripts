# VR Server Manager — Etapa 1

Painel de monitoramento para Ubuntu Server, Ubuntu Desktop e sessões SSH
interativas. A distribuição consiste somente em `vr-server-manager.sh`.

Esta implementação substitui o protótipo anterior pela arquitetura da primeira
etapa. Os seis módulos exibem **Em desenvolvimento**. Não há descoberta de
containers, chamadas Docker, instalações, logs em disco ou acesso a arquivos
`.vr`. O arquivo independente `install-alwayson.sh` não faz parte do painel.

## Executar

No diretório do script, como usuário comum:

```bash
bash vr-server-manager.sh --check
bash vr-server-manager.sh
```

O lançamento com `bash` funciona sem alterar permissões. Não é necessário usar
`sudo`. Para distribuir, basta copiar esse único arquivo para o servidor.
Os arquivos de documentação e testes não são dependências de execução.

```bash
bash vr-server-manager.sh --help
bash vr-server-manager.sh --version
```

Requisitos: Linux com `/proc`, Bash 4.4 ou posterior, terminal ANSI com UTF-8,
`stty` e GNU `timeout`. Esses comandos fazem parte do ambiente padrão Ubuntu.
GNU `df` fornece o disco raiz; se estiver ausente ou falhar, o painel informa que
essa métrica está indisponível. Recursos ausentes nunca são instalados pelo
script. `--check` funciona sem terminal e não modifica seu estado.

## Painel e teclado

A parte superior mostra hostname, usuário, distribuição, uptime, CPU, RAM,
swap, disco raiz, carga média e o horário/contador de atualização. CPU, RAM,
swap e disco têm barras verdes, amarelas a partir de 70% e vermelhas a partir
de 90%. Os rodapés mostram status, alertas e atalhos.

| Tecla | Ação |
| --- | --- |
| Cima / baixo | Navegar nos seis módulos; rolar a ajuda |
| Enter | Abrir módulo ou acionar o controle com foco |
| Tab | Alternar entre módulos e ajuda; entre voltar e ajuda no módulo |
| Esc | Voltar ao menu ou fechar a ajuda |
| F1 | Abrir/fechar ajuda, preservando tela e foco anteriores |
| R | Solicitar coleta imediata |
| Q | Sair |
| Ctrl+C | Sair com código 130 e restaurar o terminal |

A seleção e o foco não mudam durante as atualizações automáticas. A ajuda e as
telas dos módulos continuam recebendo métricas. O menu usa uma janela de itens
quando não cabe inteiro, mantendo a seleção visível. O mínimo utilizável é
32 colunas por 16 linhas; abaixo disso, há um aviso para ampliar o terminal e
o atalho Q continua disponível. Redimensionamentos são tratados por SIGWINCH.

G, M e T representam GiB, MiB e TiB. No layout compacto, `U` significa disco
usado e `L`, disponível; `L` na linha de uptime identifica a carga média de
1, 5 e 15 minutos. Textos extensos são cortados à largura disponível.

## Arquitetura

- `initialize_state`, `read_identity` e `initialize_terminal` preparam os dados
  estáticos e salvam o estado original do terminal.
- Um coprocesso Bash finito lê `/proc/stat`, `/proc/meminfo`, `/proc/uptime` e
  `/proc/loadavg`, além de consultar `df` com limite de um segundo. Ele envia
  um registro por pipe; nenhuma coleta grava arquivos temporários.
- O processo principal lê o pipe com prazo curto, preservando registros
  parciais, e permanece disponível para o teclado. Há somente uma coleta ativa
  por vez e um watchdog descarta uma coleta sem resposta.
- CPU usa duas amostras agregadas: soma de user até steal; idle inclui iowait.
  guest/guest_nice não são somados novamente. A primeira amostra, deltas nulos,
  regressões ou leituras inválidas não produzem um falso 0%.
- RAM utilizada é `MemTotal - MemAvailable`. Swap zero é **Desativada**;
  ausência de dados é **Indisponível**. Falhas descartam a métrica anterior.
- Um único laço agenda coletas a cada 2 segundos, processa teclas e renderiza a
  tela atual. A organização permite acrescentar diálogos sem parar o monitor.
- O renderizador compara texto e estilo de cada linha. Só as linhas alteradas
  são escritas; a limpeza completa ocorre na entrada e no redimensionamento.
- `EXIT`, `INT`, `TERM`, `HUP` e `QUIT` encerram o coletor e restauram o estado
  de `stty`, cores, cursor e tela alternativa. Não se usa `set -e`: falhas de
  métricas são estados recuperáveis, com mensagens no painel.

Nenhum conteúdo de `/etc/os-release` é executado. Os dados do host têm
caracteres de controle removidos antes da exibição.

## Verificar a entrega

```bash
bash -n vr-server-manager.sh
bash tests/test-dashboard.sh
bash tests/test-terminal.sh
```

A primeira suíte testa a lógica, a decodificação de teclas e a comunicação real
entre processos com dados de teste controlados. A segunda deve ser executada
no Ubuntu como usuário comum: usa o `script` do util-linux para testar um
pseudoterminal real, incluindo Ctrl+C e comparação exata de `stty` antes/depois.
Nenhuma suíte instala pacotes. Seus arquivos temporários ficam restritos a um
diretório próprio de teste, removido ao final.

Os resultados efetivamente obtidos e os itens **não testados** estão em
[TESTES.md](TESTES.md).

## Limitações desta etapa

- Validação com métricas e terminal reais no Ubuntu/SSH está pendente; o
  ambiente de desenvolvimento disponível é Windows com Git Bash, sem WSL.
- Bash 4.4 usa o relógio `SECONDS`, com resolução de um segundo. Bash 5+ usa
  `EPOCHREALTIME` em milissegundos para agendar o intervalo de 2 segundos.
- A primeira porcentagem válida de CPU aparece após a segunda coleta.
- As métricas são as fornecidas pelo `/proc` visível ao processo. Em um
  container, podem representar uma visão diferente dos limites de cgroup.
- É necessário terminal ANSI com suporte a UTF-8 e tela alternativa. Não há
  interface para pipes, `TERM=dumb` ou ambientes Windows; nesses casos, use
  `--check` para diagnóstico.
- SIGKILL e perda abrupta do terminal não permitem executar handlers de saída.
- Os seis módulos são somente telas de desenvolvimento. A Etapa 2 depende de
  aprovação posterior; nenhuma função administrativa foi implementada.

## Códigos de saída

| Código | Significado |
| --- | --- |
| 0 | Encerramento normal, ajuda/versão ou compatibilidade sem falhas obrigatórias |
| 1 | Falha de compatibilidade ou inicialização |
| 2 | Argumentos inválidos ou terminal inadequado para iniciar a interface |
| 129 / 130 / 131 / 143 | HUP / INT / QUIT / TERM, respectivamente |

No `--check`, recursos opcionais indisponíveis geram avisos; não tornam a
checagem obrigatória uma falha. A suíte TTY retorna 77 quando não pode ser
executada no ambiente atual.
