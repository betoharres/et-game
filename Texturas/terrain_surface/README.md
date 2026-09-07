# Dados de superfície do terreno

Gerados por `tools/build_terrain_surface.gd`, sem baixar assets externos.

- `ground_normal_roughness.res`, `grass_normal_roughness.res` e
  `rockyCliff_normal_roughness.res`: derivados matematicamente de `../ground.png`,
  `../grass.png` e `../rockyCliff.png`, já presentes no projeto. RGB contém normal
  tangente e alpha contém rugosidade. Diferenças centrais com bordas periódicas
  dão relevo discreto; as imagens de origem são desenhos, não mapas de altura.
- `country_land_use.res`: dados do layout local e dos marcadores do Country Town.
  Vermelho representa desgaste de caminhos/pátios; verde representa cultivo;
  azul representa margem úmida. É uma textura de dados lineares, sem `source_color`.
  Origem XZ `(-64, -64)`, extensão `(768, 576)` metros, resolução `1024 × 768`.

Todos são `ImageTexture` com mipmaps em recursos binários comprimidos. Não há
alteração das imagens originais. Os derivados das texturas mantêm as condições
de uso dos respectivos assets de origem; nenhuma autoria/licença externa nova
é atribuída a eles. O shader mantém os créditos MIT do Terrain3D em seu cabeçalho.
