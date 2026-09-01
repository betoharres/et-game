# Como validar uma alteração no ET Game

Procedimento de validação do projeto, válido para qualquer agente ou pessoa.
As regras de política ficam em `AGENTS.md`, na seção Validação; aqui está o
como fazer.

O padrão é não validar: a maior parte das mudanças vai direto. Rode algo
apenas nos casos listados em `AGENTS.md`, uma vez, depois da última edição, e
repita só se o código mudar depois da checagem ou se o ciclo rodar/medir fizer
parte da depuração.

## Comandos

Checagem de parsing, importação e referências ausentes:

```powershell
.\tools\godot.cmd --headless --path . --editor --quit
```

Uma ferramenta de `tools/`:

```powershell
.\tools\godot.cmd --headless --path . --script res://tools/<tool>.gd
```

Omita `--headless` quando a checagem depender de rasterização de verdade —
render, screenshot, culling — porque o driver dummy não desenha nada:

```powershell
.\tools\godot.cmd --path . --script res://tools/<tool>.gd --resolution 1280x720
```

**No Windows, use o executável terminado em `_console.exe`**: só ele manda
`print()` para o stdout. O wrapper `tools/godot.cmd` procura, nesta ordem:

1. `..\Godot_v4.7.1-stable_mono_win64_console.exe` (caminho antigo);
2. `C:\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe` (legado);
3. `D:\Program Files\Godot\Godot_v4.8\Godot_v4.8-dev3_mono_win64_console.exe`;
4. `godot` disponível no `PATH`.

Não rode uma segunda instância do Godot enquanto o editor estiver aberto no
mesmo projeto: as duas concorrem pelo cache em `.godot/`.

## Qual ferramenta para cada sistema

| Sistema alterado | Ferramenta |
| --- | --- |
| Estados visuais e `AnimationTree` do Player | `tools/test_player_animation.gd` |
| Pulo e consumo de stamina | `tools/test_player_jump_stamina.gd` |
| Freada e pivô em reversões bruscas | `tools/test_player_reversal.gd` |
| Ragdoll e recuperação | `tools/test_player_ragdoll.gd` |
| Modos Deus e Voo | `tools/test_player_debug_modes.gd` |
| Enquadramento e colisão da câmera | `tools/test_cinematic_camera.gd` |
| Travessia, velocidade e recorte dos portais | `tools/test_portal_teleportation.gd` |
| Presets de névoa e evento alienígena | `tools/test_atmosphere_presets.gd` |
| Filtro de interferência alienígena | `tools/test_alien_interference.gd` |
| Casco interno da nave (frestas) | `tools/check_tapered_shell.gd` |
| Patrulha do NPC genérico na nave | `tools/test_generic_npc_navigation.gd` |
| Custo de render da atmosfera | `tools/measure_atmosphere_cost.gd` (sem `--headless`) |

`tools/build_mixamo_character.py` e `tools/render_prototype_icons.py` são
utilitários de geração de asset, não checagens.

## Roteiros manuais

Resultado visual, de câmera, física, IK, navegação, interação ou gameplay quem
julga é o usuário, no editor que ele já tem aberto. Não abra o jogo para isso;
diga o que ele deve conferir, usando os roteiros abaixo.

- **Coleta e entrega:** pegue, largue e entregue um item solto e um item
  carregado; confirme a pontuação no console.
- **Veículo:** entrada, direção, troca de câmera, saída e devolução do controle
  ao jogador.
- **Fazendeiro:** patrulha, detecção, perseguição, perda do alvo e estado de
  disparo.

## Escrever uma verificação nova

- Imprima diagnóstico em texto e saia com `quit(1)` ao falhar.
- Em falhas espaciais, informe as coordenadas do mundo.
- Screenshot serve só como inspeção visual final, nunca como o critério.
- Testes de unidade, se forem adicionados: prefira GUT, em `test/unit` e
  `test/integration`.
- Nunca remova nem enfraqueça uma validação para esconder falha.
- Nunca declare algo testado sem ter executado.
