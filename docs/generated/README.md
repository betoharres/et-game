# docs/generated — snapshot automático do repositório

Área reservada ao **snapshot gerado por ferramenta**, para dar a um agente uma
visão completa do código sem depender de servidor externo de indexação.

Nada aqui é escrito à mão, e nada aqui é fonte da verdade: o código é a fonte da
verdade, e a documentação curada fica um nível acima, em [`../`](../).

## Estado atual

Vazio de propósito. O snapshot ainda não é gerado automaticamente; a
configuração já está pronta na raiz do repositório
([`../../repomix.config.json`](../../repomix.config.json)).

## Como gerar

Com [Repomix](https://github.com/yamadashy/repomix) instalado (ou via `npx`),
na raiz do projeto:

```powershell
npx repomix
```

A configuração grava `docs/generated/repomix-snapshot.md`, empacotando apenas o
que importa para entender o projeto — `scripts/`, `shaders/`, `tools/`,
`docs/`, `project.godot`, `AGENTS.md` e `README.md`. Ficam de fora os pacotes de
asset (`Polygon*/`, `Texturas/`, `3dModelos/`, `Materiais/`, `SICSFarm/`,
`Temporarios/`), os `addons/` vendorados, o cache `.godot/`, a pasta `build/` e
as cenas `.tscn` — que são grandes, majoritariamente geradas e melhor lidas
direto no editor.

Para incluir também as cenas em um snapshot pontual:

```powershell
npx repomix --include "scenes/**/*.tscn"
```

## Versionamento

O `.gitignore` desta pasta ignora os snapshots e mantém apenas este README: o
arquivo gerado é grande, muda a cada commit e não deve entrar no histórico.
Gere quando precisar; não o trate como documentação.
