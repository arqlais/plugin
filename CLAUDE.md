# LAVI Tools — contexto do projeto

Plugin para SketchUp (Ruby + painel HTML) que a Laís (estúdio **laís 3d**) está criando para **vender como renda extra**.
É uma suíte única, com ferramentas divididas por **pacotes vendidos separadamente** e liberados por chave de licença.

## Sobre a dona do projeto
- Laís, freelancer de 3D, render, detalhamento e projeto executivo, estudante de arquitetura (Santo André/SP).
- **Não programa.** Quer arquivos prontos para instalar (`.rbz`), sem precisar editar código.
- Fala português. Responda e escreva textos de interface em **português do Brasil**.
- Ela testa no próprio SketchUp e manda prints. Este ambiente não tem SketchUp: **a parte 3D nunca foi executada de verdade**. Trate tudo que mexe em geometria como "precisa de teste".

## Identidade visual (decidida — não mudar sem ela pedir)
- **Tema claro padrão** (branco gelo `#F4F4F0`, cards brancos) com **modo escuro opcional** (botão de lua no topo, salvo em `Sketchup.write_default`).
- Acento **laranja neon `#FF5A1F`**, texto preto sobre o laranja. Títulos com uma palavra em "marca-texto" laranja (no escuro vira texto laranja).
- Fontes: **Poppins** (interface) + **JetBrains Mono** (medidas e números). Ficam embutidas em `lavi_tools/ui/fonts/` (funciona offline).
- Detalhes próprios: divisória em forma de **cota**, seções numeradas `01`, `02`…, logo = parede em L + giro de porta.
- **Rejeitado por ela:** paleta petróleo/rosé/areia com serifa; **qualquer verde/lima neon** ("já tem muitos assim"); preto + amarelo (é do concorrente ArchiTools).

## Estrutura
```
lavi_tools.rb                 carregador (vai para a pasta Plugins); VERSION aqui
lavi_tools/main.rb            requires, menu Extensões › LAVI Tools, barra de ferramentas
lavi_tools/core/registry.rb   catálogo de ferramentas, PACOTES e ABAS
lavi_tools/core/license.rb    licenças por pacote (DEV_MODE, SECRET)
lavi_tools/core/helpers.rb    mm, m², operações com undo, favoritos, materiais
lavi_tools/core/dialog.rb     HtmlDialog único; callbacks ready/run/favorite/theme/activate
lavi_tools/tools/*.rb         uma ferramenta por arquivo; cada uma chama Registry.register(..., handler: self)
lavi_tools/ui/index.html      painel inteiro (CSS + JS); objeto PANELS[id] = { view, bind } por ferramenta
lavi_tools/ui/icon.svg        ícone da barra
vendas/keygen.rb              gera chaves. NUNCA vai no .rbz nem para cliente
dev/                          scripts de prévia e empacotamento
docs/                         prévias das telas
```

### Contrato Ruby ↔ painel
- JS chama `sketchup.run(JSON {req, tool, action, params})` → `Dialog.run` → `handler.handle(action, params)` → devolve um hash `{ok:, msg:, ...}` → `LAVI.onResult([req, res])`.
- Para criar ferramenta nova: arquivo em `tools/`, `Registry.register(id, name:, tab:, package:, status: :ready, handler: self, desc:)`, `require` em `main.rb`, painel em `PANELS[id]` no `index.html`, ícone em `IC[id]`. Ferramentas planejadas ficam em `tools/catalog.rb` como "em breve".
- O painel tem um **mock do objeto `sketchup`** para abrir no navegador fora do SketchUp (`window.__MOCK__` e `window.__MOCK_RUN__`). Use `dev/preview.py` para tirar prints das telas.

### Pacotes (core/registry.rb)
`base` (grátis) · `arq` Arquitetura · `rev` Revestimentos · `marc` Marcenaria · `quant` Quantitativo · chave `PRO` libera todos.
Chave: `LAVI-<ARQ|REV|MARC|QUANT|PRO>-<5 chars>-<8 hex>`, verificador = SHA256(SECRET|pacote|serial).

## Ferramentas — status (v0.3.0)
| id | ferramenta | pacote | status |
|---|---|---|---|
| joinery | **Marcenaria dinâmica** (componente dinâmico nativo) | marc | pronta, **não testada no SU** |
| cut_list | Lista de peças (chapas 2750×1840, fita, ferragens, CSV) | marc | pronta, não testada |
| floor_tiling | Paginação de piso (rejunte, amarração ½ ⅓, ângulo, recorte, compra) | rev | pronta, não testada |
| baseboard | Rodapé automático (pula portas marcadas com Shift) | rev | pronta, não testada |
| stairs | Escada reta (Blondel), maciça ou flutuante | arq | pronta, não testada |
| takeoff | Quantitativo por material (piso/parede/teto) + CSV | quant | pronta, não testada |
| model_health | Saúde do modelo (purge, linhas soltas, faces no verso…) | base | pronta, não testada |
| align / replace | Alinhar-distribuir / Selecionar e substituir | base | prontas, não testadas |
| dwg_walls, smart_wall, openings, roofs, urban_index, wall_tiling, ceiling, budget, auto_tags | — | — | em breve (catalog.rb) |

## Marcenaria dinâmica — decisões importantes
Ela quer **literalmente componentes dinâmicos (DC) nativos**, no estilo das bibliotecas de blocos do Fábio Coutinho:
esticar com a **Escala**, editar em **Janela › Opções do componente**, abrir portas/gavetas com **Interagir**, e funcionar **sem o plugin**.
- Gerado em `tools/joinery.rb`, dicionário `dynamic_attributes`. Redesenho via `$dc_observers.get_latest_class.redraw_with_undo(inst)`; exige a extensão "Componentes dinâmicos" ativa.
- **Unidades:** tudo interno em **polegadas** (`_lengthunits = INCHES`, `_formulaunits = INCHES`, constantes geradas por `c(mm)`). Campos que o usuário vê usam `_units = CENTIMETERS`. Se as medidas saírem erradas no teste, o primeiro suspeito é esta decisão.
- Estrutura: módulo raiz (sem geometria) → peças-folha (cubo 1" escalado por lenx/leny/lenz) e agrupadores (porta esquerda/direita com `ANIMATE("rotz",…)`, basculante com `rotx`, gaveta = slot posicionado com `COPY` + "Corpo gaveta" que anima `y`).
- Opções: frente (1 portas, 2 gaveta+portas, 3 gavetas, 4 aberto, 5 basculante), nportas, ngav, prat, puxador (1 perfil, 2 barra, 3 cava), matfrente, matcaixa, tampo, mattampo, espessuras, folga, rodapé.
- Rótulos das listas são codificados em `%XX` (UTF-8). **Ponto de risco:** se aparecerem `%20` na janela de opções, mudar `enc()`.
- Materiais com nomes ASCII `LAVI_Freijo`, `LAVI_Branco`…, porque as fórmulas de material usam o nome.
- "Salvar biblioteca .skp" grava 8 blocos com `definition.save_as`. Isso é um **segundo produto vendável** (biblioteca separada do plugin).
- A lista de peças lê as **medidas reais** (escala da transformação × bounds da definição) e ignora peças escondidas.

## Regras
- **Código 100% original.** Projetos antigos dela (LAVI Render) tinham plugins de terceiros modificados para remover licença. Isso não pode ser vendido, então nada disso entra aqui.
- Antes de vender: `DEV_MODE = false` em `core/license.rb` e trocar o `SECRET` (igual no `keygen.rb`). O ideal futuro é validar a chave online pelo **LAVI APP** dela (Next.js + Redis + Mercado Pago PIX, já existente).
- Toda alteração geométrica deve rodar dentro de `Helpers.operation` (um Ctrl+Z desfaz tudo).
- Entregar sempre o `.rbz` novo (`dev/build.sh`) + print das telas alteradas, e explicar em linguagem simples o que ela deve testar.

## Próximos passos combinados
1. Ela testa a v0.3 (principalmente o bloco dinâmico) e manda prints → corrigir.
2. **DWG → Paredes com vãos** (ler linhas da planta importada, pares paralelos → paredes, blocos/camadas de porta e janela → vãos com peitoril e verga; etapa de limpeza para DWG bagunçado).
3. Recorte de cuba/cooktop no tampo da marcenaria (o concorrente tem).
4. Plano de corte (nesting) a partir da lista de peças.
5. Licença online + página de venda.
