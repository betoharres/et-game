# Instruções para agentes — ET Game

Regras compartilhadas por Codex e Claude Code; `CLAUDE.md` importa este arquivo.
Protótipo 3D single-player em Godot 4.8 dev4, preset Windows: explorar, coletar
destroços e entregar. Entrada: `scenes/Menu/main_menu.tscn`; fazenda:
`scenes/world.tscn`. Godot 4.7 não é garantido (`living_light.gd` usa `Trail3D`).

## Antes de alterar

- Confira `git status` e preserve mudanças existentes do usuário.
- **Ajuste local com arquivo conhecido** (valor, texto, cor ou correção interna
  sem mudar contrato): vá direto ao código e à propriedade na cena. Não exige
  ler índice, documento do sistema ou README.
- **Local desconhecido:** use os atalhos de [docs/README.md](docs/README.md).
  **Mudança estrutural ou comportamento novo:** leia o documento do sistema;
  se cruzar sistemas, leia também [arquitetura](docs/arquitetura.md).
- Confirme o comportamento no código e as sobrescritas na cena. Amplie a
  leitura aos consumidores se houver efeito além do ponto editado. Documentos
  são um mapa, podem estar atrasados. Confira só as chaves afetadas de
  `project.godot`; evite ler cenas grandes ou snapshots inteiros.

## Implementação

- Use recursos nativos e GDScript com tipos explícitos em variáveis, parâmetros
  e retornos. Prefira sinais, grupos, composição e cenas reutilizáveis, com
  responsabilidades pequenas; evite managers globais. `GlobalScore` é só para
  estado realmente global.
- Preserve `characters`, `vehicles` e `pickup_items`, ou atualize todos os
  consumidores na mesma mudança.
- Use Input Map, não teclas hard-coded. Ação nova exige `project.godot`, menu
  de controles do ESC ([fiação](docs/ui-e-menus.md#remapeamento-de-teclas)) e
  tabela de controles do `README.md`.
- Saída regravada por ferramenta: edite a receita e regere
  ([geradores](docs/ferramentas.md)). Preserve partes de autoria mantidas pelo
  gerador, como curvas de `TireTrack3D` sem `--reseed`.
- Não edite `.godot/`, `.uid`, `.import`, caches ou snapshots gerados. Prefira
  sobrescrita local na cena a alterar modelos, texturas ou materiais importados.
- Não grave credenciais. Assets externos precisam de origem, autor e licença.

## Ferramentas

Use o MCP do Godot, quando disponível, para consultar o estado do editor,
inspecionar cenas ou conferir uma alteração, antes ou depois de editar,
respeitando a política de validação. Para ler e editar arquivos, prefira
acesso direto ao repositório.

## Validação

O padrão é não validar ajustes em funções, valores, textos, comentários ou
documentação. Headless do Godot apenas para script/cena nova, arquivo movido
ou renomeado, alteração em `project.godot` ou erro já apontado pelo editor;
uma vez após a última edição. Ferramenta de teste só ao alterar o comportamento
que ela cobre; nunca a bateria inteira. Comandos e testes por sistema:
[tools/VALIDACAO.md](tools/VALIDACAO.md). Não enfraqueça validações para ocultar
falhas nem declare testes não executados.

## Documentação

- Durante desenvolvimento, não atualize documentação. Sem exceção.
- Comente apenas o porquê não óbvio de restrições, contornos de bugs e decisões.
  Seja curto; remova comentários invalidados, sem histórico ou planos futuros.
- Revisão solicitada: siga [revisao-documentacao.md](docs/revisao-documentacao.md).
  Não carregue esse procedimento durante implementação comum.
- Ao concluir, informe arquivos alterados, validações executadas, limitações e
  documentação que a mudança deixou desatualizada.

Execução, controles e limitações do produto: [README.md](README.md), somente
quando relevantes à tarefa.
