# Validação da Etapa 1 — Issue #1

Data: **16/10/2026**. Ambiente disponível: Windows, Git Bash
5.2.37(1)-release (`x86_64-pc-msys`). Não há Ubuntu/WSL instalado nem Docker
disponível nesse ambiente. Nenhum pacote foi instalado para esta entrega.

**Resultado local da v0.1.1: 86 verificações de dashboard e 26.518 verificações
de layout passaram; nenhuma falhou.**

O branch `feat/dashboard-etapa1` parte de `90552a6` (main v1.0.0), sem alterações
diretas em `main`. A entrega v0.1.0 foi importada no commit `65eff7e` após conferir
os seis arquivos byte a byte com a pasta do Drive indicada na Issue #1.
O SHA-256 do script original é
`606c121100f61616836509f4b97eb2325c2a4c49a3c17c33ba7de7b67d758a95`.

## Evidência manual já registrada no Ubuntu

Conforme relato do responsável na
[Issue #1](https://github.com/matheusmarques-svg/vr-scripts/issues/1), a **v0.1.0**
abriu no Ubuntu `pdv-linux-servicos`, como usuário comum `vr`; a CPU atualizou
na segunda amostra, F1/Esc preservaram seleção e Q encerrou, com o terminal
aceitando comandos. Essa evidência foi fornecida pelo usuário; não é uma nova
execução feita pelo Codex e não comprova Ctrl+C nem igualdade de `stty -g`.

A **v0.1.1 refinada** ainda precisa de homologação visual nesse servidor/SSH.
Os testes locais abaixo não comprovam comportamento de um kernel Ubuntu, de
um terminal físico ou de uma sessão SSH. A checagem Ubuntu por CI é separada.

## Comandos efetivamente executados

| Comando | Resultado |
| --- | --- |
| `bash -n vr-server-manager.sh` | Aprovado, código 0 |
| `bash -n tests/test-dashboard.sh` | Aprovado, código 0 |
| `bash -n tests/test-layout.sh` | Aprovado, código 0 |
| `bash -n tests/test-terminal.sh` | Aprovado, código 0 |
| `bash tests/test-dashboard.sh` | 86 passaram, 0 falharam, código 0 |
| `bash tests/test-layout.sh` | 26.518 passaram, 0 falharam, código 0 |
| `bash tests/test-terminal.sh` | **Não testado**: retornou 77 com mensagem de incompatibilidade do ambiente |
| `bash vr-server-manager.sh --check` | Retornou 1, identificando corretamente que MSYS/Windows não é Linux |
| `bash vr-server-manager.sh` sem TTY | Retornou 2 com orientação para usar `--check`, sem ANSI |
| `git diff --check` | Aprovado, sem erros de whitespace |

## Testes obrigatórios da tarefa

Escopo desta tabela: execuções locais da **v0.1.1**. O relato manual da v0.1.0
está registrado acima; não foi reclassificado como teste automatizado.

| Requisito | Evidência e resultado |
| --- | --- |
| 1. Sintaxe Bash | **Aprovado** com `bash -n` |
| 2. Execução como usuário comum | **Não testado no Ubuntu.** O script não consulta autorização de root, não usa sudo e não exige acesso ao daemon Docker. A suíte TTY exige UID diferente de zero. |
| 3. Sem Docker disponível | **Aprovado no escopo local.** Docker não está instalado; `--check`, lógica e coletor foram exercitados. Uma função Docker instrumentada também comprova ausência de chamadas. Interface Ubuntu sem Docker: **não testada**. |
| 4. Terminal reduzido | **Aprovado no renderizador**, em matriz de 32/40/48/64/80/100/120 colunas × 16/20/24/30 linhas, além de 20x8 (aviso). Resize com stty simulado preserva foco e limpa uma vez. Redimensionamento/PTY local real: **não testado**. |
| 5. CPU e RAM a cada 2 segundos | **Aprovado com fixtures e processos reais**: dois disparos, intervalo medido, CPU 50% e RAM alterada de 200 para 700 kB. Leituras reais no kernel Ubuntu: **não testadas**. |
| 6. Setas e Enter | **Aprovado** na decodificação dos bytes CSI/SS3 e no gerenciador de telas. Teclado em TTY Ubuntu/SSH: **não testado**. |
| 7. Q para sair | **Aprovado** na decodificação e no encerramento do laço. Saída da interface em TTY Ubuntu: **não testada**. |
| 8. Ctrl+C | **Aprovado o handler de SIGINT**, com código 130 e emissão de restauração. Ctrl+C gerado pelo driver de terminal Ubuntu: **não testado**. |
| 9. Restauração do terminal | **Aprovada em simulação** de `stty` para saída normal, falha, INT e TERM; cursor e tela alternativa também verificados. Comparação de `stty -g` em TTY real: **não testada**. |
| 10. Nenhuma instalação/modificação no servidor | **Aprovada a revisão do script**, sem comandos de instalação, administração Docker, mudança de permissões, arquivos de estado ou acesso a `.vr`. `--check` não criou `.vr` ou `.local` em HOME controlado. Auditoria de syscalls em servidor Ubuntu: **não executada**. |

## Cobertura adicional da suíte local

- CPU: primeira amostra, guest/guest_nice sem duplicação, idle+iowait, cálculo
  por delta, delta nulo, regressão de contadores, recuperação, entrada malformada
  e números decimais com zeros iniciais.
- RAM/swap: MemAvailable, ausência de swap, memória inconsistente, campos
  ausentes e swap utilizada. Ausência de leitura não é convertida em 0%.
- Disco: retorno de `df`, indisponibilidade do comando, timeout e resposta
  malformada, sem conservar valores antigos como se fossem atuais.
- Uptime e médias de carga; remoção de caracteres de controle da identidade.
- Setas CSI/SS3, F1 SS3/CSI/console Linux, Enter, Tab, Esc, R, Q e sequência
  desconhecida; foco ao abrir/fechar ajuda e seleção circular dos seis módulos.
- Módulos com **Em desenvolvimento**, rolagem do menu compacto, corte de linhas
  sem ultrapassar a margem e ausência de redesenho quando o frame não muda.
- Comunicação por coprocesso, leitura parcial do registro, coleta lenta sem
  impedir navegação, atualização em outra tela e descarte pelo watchdog.
- Argumentos inválidos/extras, ajuda sem TTY, checagem sem ANSI e mensagens de
  dependência ausente.
- Códigos de saída preservados e sequências de restauração em saída normal,
  falha, SIGINT e SIGTERM, usando uma função `stty` simulada.
- Layout: barras e percentuais alinhados entre CPU/RAM/SWAP/disco e entre
  estados; números grandes, 0/69/70/89/90/100%, indisponibilidade e swap zero.
  Dados de RAM/disco, horário, contador, host/usuário e atalhos permanecem
  legíveis no modo compacto. ANSI fica fora de FRAME/LAST_FRAME e somente a
  barra recebe cor. Alertas longos são acessíveis por rotação, inclusive durante
  falhas persistentes do coletor, sem simular coletas bem-sucedidas.

Os dados artificiais ficam exclusivamente em `tests/`. O script distribuído
não possui modo demo nem exibe amostras de teste como se fossem dados reais.

## Validação contínua no Ubuntu

O workflow `.github/workflows/dashboard-checks.yml` executa sintaxe e as suítes
de dashboard, layout e terminal em Ubuntu 24.04, com usuário comum do runner.
As execuções e seus resultados ficam nos checks do commit/PR no GitHub.
O workflow não usa sudo, não instala pacotes, não altera permissões e não executa
Docker.
O checkout oficial é fixado por SHA e não persiste credenciais no repositório.

Os testes de PTY usam um kernel/driver de terminal Ubuntu real no runner.
Isso é distinto do teste visual no servidor do usuário e de uma sessão SSH.

## Aceitação no servidor Ubuntu/SSH

Executar em Ubuntu como usuário comum, dentro do diretório do repositório:

```bash
bash vr-server-manager.sh --check
bash tests/test-dashboard.sh
bash tests/test-layout.sh
bash tests/test-terminal.sh
bash vr-server-manager.sh
```

A suíte TTY preparada cobre 100x30, 32x16 e 20x8, navegação, ajuda, atualização
de CPU real, Q, Ctrl+C, ausência de chamadas Docker e comparação exata de
`stty -g` antes/depois. Ela usa somente comandos já presentes; se algum faltar,
retorna 77 e informa **não testado**, sem instalar nada.

Na interface aberta, confirmar também que a RAM acompanha o consumo real,
alterar o tamanho da janela para validar SIGWINCH e repetir a execução em SSH.
Para verificar a restauração manualmente, na mesma sessão de terminal:

```bash
estado_antes=$(stty -g)
bash vr-server-manager.sh
estado_depois=$(stty -g)
test "$estado_antes" = "$estado_depois" && printf 'Terminal restaurado\n'
```

Repetir uma vez saindo com Q e outra com Ctrl+C. Ubuntu Server/Desktop no
servidor do usuário, SSH, resize nesse servidor e a comparação real de estado
da **v0.1.1** são **não testados localmente nesta entrega**. O relato da v0.1.0
não é usado como aprovação automática da nova versão. A Etapa 2 não foi iniciada.
