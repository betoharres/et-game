---
name: revisar-docs
description: Revisa a documentação do ET Game (docs/, README.md, tools/VALIDACAO.md) contra os commits feitos desde a última revisão. Use somente quando o desenvolvedor pedir a revisão — normalmente na hora do commit. Não use durante desenvolvimento comum: por padrão o projeto não documenta.
---

# Revisar a documentação do ET Game

O procedimento está na seção **Documentação** de `AGENTS.md`, em "Revisar a
documentação". **Leia-a antes de começar** — ela define o escopo (o intervalo
desde o último commit que tocou a documentação), o que conta como mudança
digna de doc e onde cada tipo de informação mora.

Fica no `AGENTS.md` de propósito: o projeto é desenvolvido com Claude Code e
Codex, e a regra precisa valer para os dois. Esta skill só existe para
carregá-la na hora certa; mantenha o conteúdo lá, nunca aqui.

Comece por:

```
python .claude/hooks/aviso-docs.py
git log --stat <marco>..HEAD
```
