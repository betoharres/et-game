# Instruções para agentes — ET Game

Fonte única de regras para agentes. `CLAUDE.md` apenas importa este arquivo,
para o Claude Code e o Codex seguirem as mesmas instruções.

Este arquivo contém as regras. [`docs/README.md`](docs/README.md) encaminha
para o sistema e os arquivos envolvidos; não leia toda a documentação por hábito.

## O projeto em cinco linhas

Protótipo 3D single-player em Godot 4.8 dev4. Um ET explora um
mapa noturno, coleta destroços de uma nave e os leva até uma área de entrega.
Não há manager global: um mapa é uma cena que monta terreno, ambiente, jogador,
NPCs, veículos e itens, e os sistemas se falam por **sinais**, **grupos** e
**contratos de método**. Cena principal: `scenes/Menu/main_menu.tscn`. Mapa
jogável: `scenes/world.tscn`.

## Onde está a informação

| Preciso de… | Vá para |
| --- | --- |
| Mapa dos sistemas e por onde começar | [`docs/README.md`](docs/README.md) |
| Autoloads, grupos, contratos, camadas, convenções | [`docs/arquitetura.md`](docs/arquitetura.md) |
| O que existe, como rodar, controles, limitações | [`README.md`](README.md) |
| Comandos de validação, ferramenta por sistema e roteiros manuais | [`tools/VALIDACAO.md`](tools/VALIDACAO.md) |
| O que cada script de `tools/` faz, por categoria | [`docs/ferramentas.md`](docs/ferramentas.md) |
| Quando e como revisar a documentação | seção [Documentação](#documentação) deste arquivo |
| Autoloads, Input Map, camadas de física e render | `project.godot` |

## Antes de alterar

- Leia o documento de [`docs/`](docs/) do sistema envolvido e, em mudanças que
  cruzam sistemas, [`docs/arquitetura.md`](docs/arquitetura.md). A documentação
  pode estar atrás do código: use-a como mapa de onde olhar, não como verdade.
- Consulte o `README.md` apenas se a tarefa envolver execução, controles ou
  limitações do produto. Não é uma etapa obrigatória para ajustes internos.
- Confira em `project.godot` as chaves que a mudança tocar.
- Analise as cenas e os scripts envolvidos, e verifique as referências entre
  cenas, scripts, recursos, grupos, sinais, autoloads, materiais e modelos
  importados.
- Confirme no código o comportamento atual; não documente nem implemente
  funcionalidade presumida.
- Consulte `git status` e preserve mudanças existentes do usuário, inclusive as
  não relacionadas à tarefa atual.

## Escopo

- O projeto atual é um protótipo 3D single-player.
- Preserve o fluxo principal de explorar, coletar destroços e entregá-los.
- Não introduza multiplayer, backend, persistência ou arquitetura de servidor
  sem solicitação explícita.
- Faça a menor alteração necessária e evite reorganizações sem benefício claro.
- O projeto usa Godot 4.8 dev4 e o preset Windows. Compatibilidade com 4.7
  não é garantida: `scripts/living_light.gd` depende de `Trail3D` nativo.

## Godot

- Prefira recursos nativos do Godot e GDScript tipado.
- Sempre use vars, funções e retornos com tipos explícitos
  (`var x: int = 0`; `func foo(delta: float) -> void:`).
- Use ações do Input Map em vez de teclas hard-coded. Ao criar uma ação:
  registre-a em `project.godot` e acrescente-a ao menu de controles do ESC — ver
  [`docs/ui-e-menus.md`](docs/ui-e-menus.md).
  Atualize também a tabela de controles do `README.md`; esta é uma exceção
  pontual à regra de não documentar durante desenvolvimento.
- Prefira sinais, grupos, composição e cenas reutilizáveis.
- Mantenha scripts e nós com responsabilidades pequenas.
- Preserve os grupos `characters`, `vehicles` e `pickup_items` ou atualize
  todos os seus consumidores na mesma mudança.
- Evite managers globais, duplicação e abstrações prematuras. Use o autoload
  `GlobalScore` somente para estado realmente global.
- Para saídas que uma ferramenta regrava, mude a receita e regere
  ([`docs/ferramentas.md`](docs/ferramentas.md)). Preserve partes de autoria que
  o gerador mantém, como as curvas de `TireTrack3D` sem `--reseed`.
- Não edite `.godot/`, arquivos `.uid`, `.import` ou caches gerados.
- Não altere modelos, texturas ou materiais importados quando uma sobrescrita
  local na cena resolver o problema.
- Nunca grave senhas, tokens, chaves ou credenciais no repositório.
- Registre origem, autor e licença ao adicionar assets externos.

## Validação

- O padrão é não validar. Mudança no corpo de uma função, em valores, textos,
  comentários ou documentação vai direto, com um resumo do que mudou.
- Rode a checagem headless do Godot apenas nestes casos: script ou cena nova,
  arquivo movido ou renomeado, alteração em `project.godot`, ou quando o editor
  já estiver acusando erro. Uma vez, depois da última edição.
- Rode uma ferramenta de `tools/` só ao mexer no comportamento que ela cobre —
  a do sistema alterado, nunca a bateria inteira.
- Os comandos, o mapa de ferramentas por sistema, os roteiros do que pedir ao
  usuário e as regras para escrever uma verificação nova estão em
  [`tools/VALIDACAO.md`](tools/VALIDACAO.md).
- Nunca remova ou enfraqueça validações para ocultar falhas.
- Nunca declare algo como testado sem ter executado a validação.

## Documentação

Prefira código claro. Comente apenas o porquê de uma restrição técnica,
contorno de bug ou decisão não óbvia; seja curto. Não repita nomes, tipos,
exports nem o que a função faz. Remova comentários invalidados pela mudança;
não acumule histórico, suposições ou planos futuros.

### Durante o desenvolvimento

**Desenvolvimento não documenta.** Implementar, corrigir ou ajustar não exige
atualizar `docs/`, `README.md` nem este arquivo. A revisão é uma tarefa
explícita, geralmente na hora do commit. Exceções pontuais:

- Ação de input nova: atualize a tabela de controles do `README.md`.
- Mudança que deixa `docs/` induzindo outro agente a escrever código errado:
  corrija o trecho afetado, sem iniciar uma revisão geral.

Ao commitar mudança de contrato entre sistemas, registre o que mudou e por
quê; a mensagem permite recuperar a decisão na revisão posterior.
Ao concluir uma tarefa, informe arquivos alterados, validações executadas e
limitações restantes. Não edite snapshots de `docs/generated/` à mão.

### Revisar a documentação

Só quando pedido. Na revisão incremental, localize o último commit que tocou
`docs/`, `README.md`, `AGENTS.md` ou `tools/VALIDACAO.md`, leia o intervalo até
`HEAD` com `git log`/`git diff` e considere as mudanças locais da tarefa.
Esse marco é uma aproximação: tocar um documento não comprova revisão dos demais.
Em auditoria de organização, duplicação ou cobertura, examine também os
textos existentes, mesmo sem commits posteriores ao marco.

| Informação | Onde manter |
| --- | --- |
| Regras permanentes de trabalho | `AGENTS.md`; corrija também conflitos entre regras |
| Localizar sistema e código | `docs/README.md`; inclua documentos novos no índice |
| Relações, responsabilidades e decisões | Documento do sistema em `docs/` |
| Execução, fluxo, controles, dependências e limitações do produto | `README.md`; mantenha o índice ao mudar seções |
| Comandos, pipeline, argumentos e armadilhas das ferramentas | `tools/VALIDACAO.md` ou cabeçalho do script |
| Receita → saída → sistema | `docs/ferramentas.md` |
| Valores de ajuste | Exports das cenas e constantes do código; não copie para docs |

Atualize os documentos dos sistemas quando mudar cena reutilizável, autoload,
grupo, sinal, contrato, responsabilidade entre scripts, etapa do fluxo ou efeito
de ferramenta. Registre decisões necessárias para evitar que outro agente
repita um erro. Ajuste de valor, correção interna e mudança só visual não pedem
documentação. Descreva a arquitetura atual e apague o que deixou de valer.
Use links em vez de repetir tabelas e procedimentos entre arquivos.

### Aviso de atraso

Rode `python .claude/hooks/aviso-docs.py` no início da sessão. Se imprimir
aviso, repita-o ao desenvolvedor e ofereça a revisão; não revise por conta
própria. O hook usa o último commit que tocou documentação como aproximação,
não verifica se o conteúdo corresponde ao código.
