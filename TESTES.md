# Validação da Etapa 1

Data: **16/10/2026**. Ambiente disponível: Windows, Git Bash
5.2.37(1)-release (`x86_64-pc-msys`). Não há Ubuntu/WSL instalado nem Docker
disponível nesse ambiente. Nenhum pacote foi instalado para esta entrega.

**Resultado local: 86 verificações passaram; nenhuma falhou.**

O código e a documentação estão entregues na cópia local do repositório. O
critério de conclusão em Ubuntu real permanece **pendente de validação**.
Os testes locais não comprovam comportamento de um kernel Ubuntu, de um
terminal físico ou de uma sessão SSH.

## Comandos efetivamente executados

| Comando | Resultado |
| --- | --- |
| `bash -n vr-server-manager.sh` | Aprovado, código 0 |
| `bash -n tests/test-dashboard.sh` | Aprovado, código 0 |
| `bash -n tests/test-terminal.sh` | Aprovado, código 0 |
| `bash tests/test-dashboard.sh` | 86 passaram, 0 falharam, código 0 |
| `bash tests/test-terminal.sh` | **Não testado**: retornou 77 com mensagem de incompatibilidade do ambiente |
| `bash vr-server-manager.sh --check` | Retornou 1, identificando corretamente que MSYS/Windows não é Linux |
| `bash vr-server-manager.sh` sem TTY | Retornou 2 com orientação para usar `--check`, sem ANSI |
| `git diff --check` | Aprovado, sem erros de whitespace |

## Testes obrigatórios da tarefa

| Requisito | Evidência e resultado |
| --- | --- |
| 1. Sintaxe Bash | **Aprovado** com `bash -n` |
| 2. Execução como usuário comum | **Não testado no Ubuntu.** O script não consulta autorização de root, não usa sudo e não exige acesso ao daemon Docker. A suíte TTY exige UID diferente de zero. |
| 3. Sem Docker disponível | **Aprovado no escopo local.** Docker não está instalado; `--check`, lógica e coletor foram exercitados. Uma função Docker instrumentada também comprova ausência de chamadas. Interface Ubuntu sem Docker: **não testada**. |
| 4. Terminal reduzido | **Aprovado no renderizador**, com 32x16 (rolagem e limite de largura) e 20x8 (aviso). Redimensionamento/PTY real: **não testado**. |
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

Os dados artificiais ficam exclusivamente em `tests/`. O script distribuído
não possui modo demo nem exibe amostras de teste como se fossem dados reais.

## Aceitação pendente no Ubuntu

Executar em Ubuntu como usuário comum, dentro do diretório do repositório:

```bash
bash vr-server-manager.sh --check
bash tests/test-dashboard.sh
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

Repetir uma vez saindo com Q e outra com Ctrl+C. Ubuntu Server, Ubuntu Desktop,
SSH, sinalização de resize e comparação real de estado são **não testados nesta
entrega**. A Etapa 2 não foi iniciada.
