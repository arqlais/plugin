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

## Ferramentas — status (v0.4.x; só a marcenaria foi testada por ela, e falhou na 0.4.0)
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

## Marcenaria dinâmica — como funciona (v0.4.1, refeita depois do teste da Laís)
Ela quer **literalmente componentes dinâmicos (DC) nativos**, no padrão das bibliotecas profissionais (Fábio Coutinho, AFC):
esticar com a **Escala sem deformar**, editar em **Janela › Opções do componente**, abrir portas/gavetas com **Interagir**, funcionar **sem o plugin**.
Na v0.4.0 o bloco saiu desmontado (peças espalhadas e com tamanho errado): eu deixava o redesenho do DC montar tudo e gravava os atributos fora do padrão.

Arquitetura atual:
- `core/dc_formula.rb`: avaliador das fórmulas DC (IF, AND, OR, MAX, Parent!x, textos…).
- `core/dc_tree.rb`: árvore de entidades (root/node/leaf) com atributos; calcula posição e tamanho de cada peça em cm.
- `tools/joinery_spec.rb`: a receita do módulo (independente do SketchUp). Gavetas (6) e prateleiras (6) são vagas fixas ligadas/desligadas por `Hidden` (sem `Copies`).
- `tools/joinery.rb`: monta no SketchUp **já calculado** (peça = componente com cubo de 1" escalado) e grava as fórmulas para o DC continuar funcionando. "Atualizar" remonta pelo cálculo do plugin. Botões "Testar redesenho do SketchUp" e "Diagnóstico" (txt com a árvore) para depurar.
- `dev/render_dc.rb` desenha os módulos calculados (prints em `docs/marcenaria-modulos.png`); `dev/test_core.rb` testa 720 combinações.

Padrão de atributos, copiado da estrutura de um bloco DC real (biblioteca AFC de pontos elétricos que ela mandou; o `.skp` 2022 tem um ZIP com `model.dat`, onde os dicionários aparecem como chave `\xb66`+u32+texto e valor `\xa48`+u32+(`\xad8` texto | `\xa98` double)):
- Atributos do sistema com rótulo exato: `_lenx_label='LenX'`, `X`, `Y`, `Z`, `RotZ`, `Hidden`, `Material`, `onClick`, `Name`. Nas peças, só `_label` + `_formula` + valor (sem units/formulaunits).
- Atributos próprios: `_k_label`, `_k_access` (NONE/TEXTBOX/LIST/VIEW), `_k_formlabel`, `_k_units`, `_k_formulaunits`, `_k_options` ('&' quando vazio), valor gravado como **texto**; comprimentos em polegadas.
- `_lengthunits = CENTIMETERS`; fórmulas em cm; `_lenx_nominal` etc. na raiz.
- Ainda NÃO confirmado no SketchUp: animação `onClick` (`_onclick_formula` + `onclick`) e o redesenho do DC depois da Escala.
- "Salvar biblioteca .skp" grava 9 blocos (`definition.save_as`) — segundo produto vendável.

Próximo nível que ela quer (imagens de referência): catálogo detalhado como as bibliotecas profissionais — portas com batente/guarnição e símbolo de abertura em planta + etiqueta (P1, medidas), tampos (frontão, saia 45°, rebaixo, cuba esculpida), módulos de lixeira, roupeiro, porta escamoteável, puxadores perfilados. Fazer um de cada vez, sempre com teste + render antes de entregar.

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
