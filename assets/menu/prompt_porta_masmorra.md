# Prompt para o Claude Code — Porta de masmorra procedural (ET Game)

## Objetivo
Adicionar ao ET Game uma porta/portal que dá acesso a uma área 3D gerada
proceduralmente (uma masmorra: salas conectadas por corredores, construída
num `GridMap`). A masmorra deve ser gerada **apenas uma vez por sessão de
jogo** — a porta não regenera nada nas vezes seguintes, só teleporta o
jogador para o layout que já existe.

## Antes de começar
- Leia `AGENTS.md` e `README.md` na raiz do projeto primeiro, e siga as
  convenções já estabelecidas (organização de `scripts/` e `scenes/`,
  autoloads existentes, grupos do Godot, estilo de nomes de arquivo).
- Projeto em Godot `4.7`, GDScript, física Jolt, cena principal carregada a
  partir de `scenes/world.tscn`.
- Não há infraestrutura de save entre execuções — está tudo bem que o estado
  "masmorra já gerada" viva só em memória durante a sessão atual.

## Requisitos funcionais
1. Uma porta (`Area3D`), no estilo das demais áreas de interação do jogo
   (ex.: `DeliveryArea.tscn`), que teleporta o jogador para dentro da
   masmorra ao ser tocada.
2. A masmorra é construída **uma única vez por sessão**, na primeira vez que
   a porta é tocada: gera o layout, marca um flag de "já gerada" e teleporta.
   Nos toques seguintes, com o flag já ativo, a porta só teleporta — não
   chama o gerador de novo.
3. Geração via `GridMap`: salas retangulares sem sobreposição, conectadas em
   sequência por corredores (sala N com sala N-1), com paredes automáticas
   nas bordas de cada célula de chão.
4. Para identificar o jogador na colisão da porta, siga o mesmo padrão já
   usado no projeto (confira como `smelly_farmer.gd` e `photographer.gd`
   reconhecem o Player hoje) em vez de assumir um grupo `player` que pode não
   existir.

## Decisões de arquitetura a seguir
- Guarde o flag "já gerada" de forma coerente com o padrão dos autoloads
  existentes (`GlobalScore`, `PhotoAlertSystem`) — um autoload leve dedicado,
  ou uma variável num node persistente, o que fizer mais sentido dentro da
  estrutura atual de `world.tscn`.
- Decida explicitamente se a masmorra participa da navmesh principal (o que
  pode afetar a navegação do fazendeiro/fotógrafo) ou se é uma sub-área
  isolada sem impacto na IA existente. Isso não deve ser um efeito colateral
  não intencional.
- Siga a convenção de nomes de arquivo já usada (scripts em inglês,
  `snake_case`; autoloads em `PascalCase`).
- Reaproveite materiais já usados na fazenda (`Materiais/`) para a masmorra
  não destoar visualmente do resto do jogo, a menos que o objetivo seja ela
  parecer claramente "outro lugar".

## Validação
- Rode a checagem headless já usada no projeto
  (`godot --headless --path . --editor --quit`) depois de implementar, pra
  garantir que não há erro de parsing ou referência quebrada.
- Teste manual: toque a porta duas vezes na mesma sessão e confirme que a
  segunda vez não gera um layout novo.
- Atualize `README.md` (seções "Estrutura principal", "Fluxo atual" e
  "Estado do protótipo e pendências") descrevendo a nova porta/área, no
  mesmo estilo de documentação já usado no restante do arquivo.

## Em aberto — pergunte antes de decidir sozinho
- O jogador consegue voltar da masmorra pra fazenda, ou é só ida?
- A masmorra tem alguma finalidade de gameplay (item pra coletar, objetivo,
  interação com o fazendeiro/fotógrafo) ou é só uma área extra por enquanto?
