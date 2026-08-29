extends RefCounted

## Estado minimo que atravessa a troca de cena entre a plataforma orbital e a
## fase. Nao e um autoload: o script estatico nao precisa de arvore de cena,
## ciclo de vida nem sinais.

## True quando a fase foi aberta pelo terminal da plataforma orbital: a fase
## entao nasce o ET em pe sobre uma plataforma no ceu, esperando o jogador
## acionar o feixe. Abrir a fase direto no editor mantem False, preservando a
## cutscene automatica de chegada para testes rapidos.
static var arrived_from_orbit : bool = false
