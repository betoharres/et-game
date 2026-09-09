# Revisão da documentação

Procedimento compartilhado por Codex e Claude Code. Leia somente quando a
tarefa for revisar documentação; as regras gerais ficam em [AGENTS.md](../AGENTS.md).

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

## Localizar o intervalo

Na raiz do projeto:

```powershell
git log -1 --format=%H -- docs/ README.md AGENTS.md tools/VALIDACAO.md
git log --stat <marco>..HEAD
git diff <marco>..HEAD
git diff HEAD
```

Substitua `<marco>` pelo hash retornado. Consulte também `git status` para
identificar arquivos novos, que não aparecem no diff. Não confunda ausência de
commits posteriores com ausência de problemas na documentação.
