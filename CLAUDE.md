# Planê Plugin — contexto do projeto

Plugin para SketchUp (Ruby + painel HTML) que a Laís está criando para **vender como renda extra**, ligado à marca **Planê** dela.
É uma suíte única, com ferramentas divididas em **pacotes vendidos separadamente** e liberados por chave de licença.
(Até a v0.3 se chamava "LAVI Tools"; ela pediu nome, símbolo e cor novos na v0.4.)

## Sobre a dona do projeto
- Laís, freelancer de 3D, render, detalhamento e projeto executivo, estudante de arquitetura (Santo André/SP).
- **Não programa.** Quer arquivos prontos para instalar (`.rbz`), sem precisar editar código.
- Fala português. Responda e escreva textos de interface em **português do Brasil**.
- Ela testa no próprio SketchUp e manda prints. Este ambiente não tem SketchUp: **a parte 3D nunca foi executada de verdade**. Trate tudo que mexe em geometria como "precisa de teste".

## Identidade visual (decidida — não mudar sem ela pedir)
- Nome **Planê Plugin** (o "ê" em degradê). Símbolo = **"P em laço"** da identidade da Planê (traço contínuo), branco sobre quadrado arredondado em degradê.
- Acento **degradê rosa `#FF2E88` → lilás `#A970FF`**, texto quase preto `#1A1220` sobre o degradê. Grafite da Planê `#2F3A45`/`#3E4B57` no texto.
- **Tema claro padrão** (`#F6F3F4`, cards brancos) com **modo escuro** (botão de lua, salvo em `Sketchup.write_default`).
- Fontes: **Poppins** (interface) + **JetBrains Mono** (medidas e números), embutidas em `plane_plugin/ui/fonts/` (funciona offline).
- Ela quer: **intuitivo, organizado, ícones/símbolos para tudo, bem dinâmico** (animações, prévias ao vivo).
- **Rejeitado por ela:** laranja neon (v0.3); qualquer verde/lima neon; paleta petróleo/rosé/areia com serifa; preto + amarelo (ArchiTools); o nome "LAVI Tools" e o símbolo antigo.

## Estrutura
```
plane_plugin.rb                 carregador (vai para a pasta Plugins); VERSION aqui
plane_plugin/main.rb            requires, menu Extensões › Planê Plugin, barra de ferramentas, checagem de atualização
plane_plugin/core/registry.rb   catálogo de ferramentas, PACOTES e ABAS
plane_plugin/core/license.rb    licenças por pacote (DEV_MODE, SECRET)
plane_plugin/core/helpers.rb    unidades, operação com desfazer, materiais, etiquetas, CSV pt-BR
plane_plugin/core/geom.rb       matemática 2D (offset, recorte, áreas) + referencial de face
plane_plugin/core/nesting.rb    plano de corte (prateleiras/guilhotina)
plane_plugin/core/pickers.rb    ferramentas de clique (PointPicker, FacePicker)
plane_plugin/core/updater.rb    atualização automática
plane_plugin/core/dialog.rb     HtmlDialog único; callbacks ready/run/favorite/theme/activate/update/open_url
plane_plugin/tools/*.rb         uma ferramenta por arquivo; cada uma chama Registry.register(..., handler: self)
plane_plugin/ui/index.html      painel inteiro (CSS + JS); FORMS[id] declara campos, ações, prévia e resultado
plane_plugin/ui/icon.svg        ícone da barra
updates/latest.json + .rbz      o que a atualização automática baixa
vendas/keygen.rb                gera chaves. NUNCA vai no .rbz nem para cliente
dev/build.sh                    gera dist/*.rbz e atualiza updates/
dev/preview.js                  abre o painel com mock e tira prints (Playwright)
dev/test_core.rb                testes da parte que não depende do SketchUp
docs/                           prints das telas
```

### Contrato Ruby ↔ painel
- JS chama `sketchup.run(JSON {req, tool, action, params})` → `Dialog.run` → `handler.handle(action, params)` → hash `{ok:, msg:, stats: [[rótulo, valor, ok?]], ...}` → `PLN.onResult([req, res])`.
- Ferramentas interativas (clique no modelo) devolvem `{picking: true}` na hora e mandam o resultado depois com `Dialog.push('result', {tool:, ok:, msg:, stats:})`.
- Para criar ferramenta nova: arquivo em `tools/`, `Registry.register(id, name:, tab:, package:, handler: self, desc:, steps: [3 passos])`, nome no `%w[]` do `main.rb`, formulário em `FORMS[id]` no `index.html`, ícone em `IC[id]`, linha em `MOCK.tools`.
- O painel tem **mock** do `sketchup` para abrir no navegador (`window.__MOCK__`, `window.__MOCK_RUN__`). `node dev/preview.js docs` tira os prints e falha se houver erro de JS.

### Pacotes (core/registry.rb)
`base` Essencial (grátis) · `arq` Arquitetura · `rev` Revestimentos · `marc` Marcenaria · `quant` Quantitativo · chave `PRO` libera todos.
Chave: `PLANE-<ARQ|REV|MARC|QUANT|PRO>-<5 chars>-<8 hex>`, verificador = SHA256(SECRET|pacote|serial).

## Ferramentas — status (v0.4.0, todas escritas do zero nesta versão, nenhuma testada no SketchUp)
| id | ferramenta | pacote |
|---|---|---|
| walls | Paredes (clicando cantos ou de linhas selecionadas; meia-esquadria) | arq |
| openings | Portas e janelas (clica na parede, abre o vão, põe folha/vidro) | arq |
| dwg_walls | DWG → Paredes (pares paralelos, vergas e peitoris nos vãos) | arq |
| stairs | Escada reta Blondel, maciça ou flutuante, corrimão | arq |
| roofs | Telhado 1/2/4 águas, beiral, telhas | arq |
| urban_index | TO, CA, permeabilidade vs. limites da lei | arq |
| tiling / wall_tiling | Paginação de piso e de parede (rejunte, ½ ⅓, ângulo, furos, caixas, rejunte kg) | rev |
| baseboard | Rodapé (pula linhas de porta selecionadas com Shift, pilares) | rev |
| ceiling | Forro com sanca, placas | rev |
| joinery | Marcenaria em componente dinâmico nativo | marc |
| cut_list | Lista de peças + plano de corte + fita + ferragens + CSV | marc |
| countertop | Recorte de cuba/cooktop no tampo | marc |
| takeoff | Quantitativo por material (piso/parede/teto) + itens + CSV | quant |
| budget | Orçamento (preços salvos no .skp), MO, BDI, proposta HTML→PDF | quant |
| model_health, align, replace, auto_tags | Essenciais | base |

## Marcenaria dinâmica — decisões importantes
Ela quer **literalmente componentes dinâmicos (DC) nativos**, no estilo das bibliotecas do Fábio Coutinho:
esticar com a **Escala**, editar em **Janela › Opções do componente**, abrir portas/gavetas com **Interagir**, funcionar **sem o plugin**.
- `tools/joinery.rb`, dicionário `dynamic_attributes`. Redesenho via `$dc_observers.get_latest_class.redraw_with_undo(inst)`.
- **Unidades (mudou na v0.4):** `_lengthunits = CENTIMETERS`; fórmulas em cm; valores de comprimento guardados em polegadas (cm/2,54). Se as medidas saírem erradas no teste, o primeiro suspeito é isto.
- Estrutura: raiz (definição de componente, sem geometria) → peças-folha (grupo com cubo de 1" escalado por LenX/LenY/LenZ) e agrupadores (Porta esquerda/direita com `ANIMATE("rotz",…)`, Basculante com `rotx`, Gaveta = slot com `copies`/`COPY` + "Corpo da gaveta" que anima `y` com `ANIMATE("y",0,-abre)`).
- Fórmulas só alcançam `Parent!`; por isso os agrupadores repassam atributos (lf, hf, ef, mf, px, pz, py…).
- `onclick` gravado em `onclick` e `_onclick_formula`. **Ponto de risco** se a animação não funcionar.
- Rótulos de listas codificados em `%XX` (UTF-8), mantendo `_ . -`. **Ponto de risco:** se aparecer `%20` nas opções, mudar `enc()`.
- `tampovis` (escondido) permite o recorte de cuba trocar o tampo dinâmico por um grupo com furo.
- "Salvar biblioteca .skp" grava 9 blocos com `definition.save_as` — **segundo produto vendável**.
- A lista de peças lê as medidas reais (escala × bounds) e ignora peças escondidas.

## Atualização automática
- `Updater` lê `https://raw.githubusercontent.com/arqlais/plugin/HEAD/updates/latest.json` 8 s depois de abrir o SketchUp; se a versão for maior, baixa o `.rbz`, confere SHA256 e roda `Sketchup.install_from_archive`. Depois pede para reiniciar o SketchUp.
- Para publicar versão nova: subir `VERSION` em `plane_plugin.rb`, `sh dev/build.sh "nota 1" "nota 2"`, commit e merge no branch padrão.
- **Precisa de repositório público** (ou mover `updates/` para um host público, ex. o LAVI APP / site da Planê). Se o repo ficar privado, a atualização para de funcionar.

## Regras
- **Código 100% original.** Projetos antigos dela tinham plugins de terceiros modificados para remover licença: nada disso entra aqui.
- Antes de vender: `DEV_MODE = false` em `core/license.rb` e trocar o `SECRET` (o `keygen.rb` lê de lá). Com o repo público, o SECRET fica visível: o ideal é validar a chave online pelo app dela (Next.js + Redis + Mercado Pago PIX, já existente).
- Toda alteração geométrica dentro de `Helpers.operation` (um Ctrl+Z desfaz tudo).
- Compatível com SketchUp 2019+ (Ruby 2.5): evitar `&.`, `tally`, `filter_map`, sintaxe de Ruby 3.
- Antes de entregar: `ruby dev/test_core.rb`, `node dev/preview.js docs`, `sh dev/build.sh`. Entregar o `.rbz` + prints e explicar em linguagem simples o que testar.

## Próximos passos combinados
1. Ela testa a v0.4 (principalmente bloco dinâmico, paredes, vãos e paginação) e manda prints → corrigir.
2. Licença online + página de venda.
3. Plano de corte mais eficiente (maxrects) e etiquetas para impressão das peças.
