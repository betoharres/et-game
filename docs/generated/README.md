# docs/generated — snapshots do repositório

Área do **snapshot gerado por ferramenta**, para dar a um agente uma visão
completa do código sem depender de servidor externo de indexação.

Nada aqui é escrito à mão, e nada aqui é fonte da verdade: o código é a fonte da
verdade, e a documentação curada fica um nível acima, em [`../`](../).

## Os cinco perfis

O repositório inteiro dá ~378 mil tokens — grande demais para carregar de
rotina. Por isso o snapshot é fatiado em camadas, cada uma carregável sozinha:

| Arquivo | Conteúdo | Tamanho |
| --- | --- | --- |
| `01-contexto.md` | `docs/`, `AGENTS.md`, `README.md`, `project.godot`, `export_presets.cfg` | ~31k tokens, 18 arquivos |
| `02-scripts-principais.md` | `scripts/*.gd` — jogador, mundo, entrega, ambientação, veículos, NPCs da fazenda | ~134k tokens, 55 arquivos |
| `03-scripts-subsistemas.md` | `scripts/*/` — `npc/`, `space/`, `dungeon/`, `audio/`, `levels/`, `plane/`, `portal/`, `spider_bot/`, `terrain/` | ~55k tokens, 66 arquivos |
| `04-tools.md` | `tools/` — geradores, checagens e `VALIDACAO.md` | ~117k tokens, 47 arquivos |
| `05-shaders.md` | `shaders/` | ~42k tokens, 24 arquivos |

Somados, cobrem exatamente os mesmos 210 arquivos do snapshot único, sem
sobreposição entre perfis.

**Como usar:** `01-contexto.md` responde sozinho "o que existe e onde fica" e é
o único que vale carregar por hábito — e mesmo ele costuma ser desnecessário,
porque os documentos de `docs/` já estão no repositório e podem ser lidos um a
um. Os outros quatro entram sob demanda, quando a pergunta é sobre o código
daquela camada e uma busca pontual não resolve.

A divisão segue a **estrutura de pastas** de propósito: arquivo novo cai no
perfil certo sozinho, sem ninguém manter lista de arquivos. Uma divisão por
sistema de jogo (player, NPCs, veículos…) exigiria listas mantidas à mão,
porque `scripts/` é plano — não vale o custo.

## Como gerar

```powershell
.\tools\build_snapshots.ps1            # os cinco perfis
.\tools\build_snapshots.ps1 -Completo  # também o snapshot único
```

O script usa [Repomix](https://github.com/yamadashy/repomix) via `npx` e monta
um config temporário por perfil. Isso é necessário porque `repomix --include`
na linha de comando **soma** ao `include` de `repomix.config.json` em vez de
substituí-lo; só `--config` troca o config de verdade.

O `repomix.config.json` da raiz continua descrevendo o **snapshot único**
(`docs/generated/repomix-snapshot.md`), gerado por `npx repomix` sem argumentos.

Todos os perfis excluem `docs/generated/`, `.godot/`, `addons/`, `build/` e —
via `.gitignore` — os pacotes de asset. As cenas `.tscn` ficam de fora: são
grandes, majoritariamente geradas e melhor lidas no editor. Para um snapshot
pontual com elas:

```powershell
npx repomix --include "scenes/**/*.tscn" --output docs/generated/scenes.md
```

## Versionamento

O `.gitignore` desta pasta ignora todos os snapshots e mantém apenas este
README: os arquivos são grandes, mudam a cada commit e não devem entrar no
histórico. Gere quando precisar; não os trate como documentação.
