# LAVI (plugin) — contexto do projeto

Plugin para SketchUp (Ruby + painel HTML) que a Laís está criando para **vender como renda extra**. Nome: **LAVI** (escolhido por ela na v0.6).
É uma suíte única, com ferramentas divididas em **pacotes vendidos separadamente** e liberados por chave de licença.
(Histórico: v0.3 "LAVI Tools" laranja; v0.4–0.5 "Planê Plugin" rosa→lilás com símbolo de laço — ela rejeitou nome, degradê e símbolo; v0.6 virou LAVI.)

## Sobre a dona do projeto
- Laís, freelancer de 3D, render, detalhamento e projeto executivo, estudante de arquitetura (Santo André/SP).
- **Não programa.** Quer arquivos prontos para instalar (`.rbz`), sem precisar editar código.
- Fala português. Responda e escreva textos de interface em **português do Brasil**.
- Ela testa no próprio SketchUp e manda prints. Este ambiente não tem SketchUp: **a parte 3D nunca foi executada de verdade**. Trate tudo que mexe em geometria como "precisa de teste".

## Identidade visual (decidida por ela na v0.6 — não mudar sem ela pedir)
- Nome **LAVI** (wordmark em Bodoni Moda 600, caixa alta, espaçado). Símbolo = **planta com porta** (quadrado + parede + giro de porta), `IC.lavi`, **sem fundo**: planta em vinho e giro da porta em pink (v0.7: ela rejeitou o fundo lima, "já existe muito plugin assim").
- **NUNCA usar degradê**, em nada (ela pediu explicitamente). Só cores sólidas.
- Paleta das referências dela: cinza `#EFEFEF` (fundo), orquídea `#EAA2E5` (seleção), lima `#D3DC2A` (não usar mais no ícone), lima claro `#EBF5A0` (texto sobre vinho, selo grátis), vinho/mulberry `#5C0632` (marca, botão principal, texto forte), pink `#E1146C` (detalhes: números, destaque no título), areia `#E3E2D7` (dicas).
- Fontes embutidas: **Poppins** (interface, a mesma do site dela lais3d.com.br), **Bodoni Moda** (nome LAVI), **JetBrains Mono** (medidas). Em `lavi_plugin/ui/fonts/`. Anton e Montserrat saíram na v0.7 (ela achou feio).
- Layout (v0.7, referência dela = painel do HeyPrint + sites lais3d.com.br/souplane.com.br): fundo claro quente, marca + 2 botões quadrados vinho, busca, lista por grupo (só ícone + nome + estrela, sem descrição). Títulos de seção pequenos, caixa alta, espaçados. Na ferramenta: voltar + título, campos numa caixa branca **uma linha por campo** (rótulo à esquerda, controle à direita), chaves liga/desliga, régua deslizante (`type:'range'`), seção `opt:1` mostra "opcional". Ela achou a versão anterior "poluída": não encher de caixas, badges e textos.
- Barra do SketchUp: ícone LAVI colorido + um botão monocromático por ferramenta principal (`TOOLBAR` em main.rb; ícones gerados por `python3 dev/make_icons.py` a partir de `IC`, desenho a 80% e traço fino ~1,2 px, porque ela achou grande e grosso).
- Modo claro padrão + escuro (lua). Ela quer intuitivo, organizado, ícones para tudo.
- **Rejeitado por ela:** laranja neon; verde/lima neon como cor dominante (lima só no ícone principal veio da referência dela); petróleo/rosé/areia com serifa; preto + amarelo; "LAVI Tools"/símbolo antigo; "Planê Plugin", símbolo de laço e qualquer degradê.

## Estrutura
```
lavi_plugin.rb                 carregador (vai para a pasta Plugins); VERSION aqui
lavi_plugin/main.rb            requires, menu Extensões › LAVI, barra de ferramentas, checagem de atualização
lavi_plugin/core/registry.rb   catálogo de ferramentas, PACOTES e ABAS
lavi_plugin/core/license.rb    licenças por pacote (DEV_MODE, SECRET)
lavi_plugin/core/helpers.rb    unidades, operação com desfazer, materiais, etiquetas, CSV pt-BR
lavi_plugin/core/geom.rb       matemática 2D (offset, recorte, áreas) + referencial de face
lavi_plugin/core/nesting.rb    plano de corte (prateleiras/guilhotina)
lavi_plugin/core/pickers.rb    ferramentas de clique (PointPicker, FacePicker)
lavi_plugin/core/updater.rb    atualização automática
lavi_plugin/core/dialog.rb     HtmlDialog único; callbacks ready/run/favorite/theme/activate/update/open_url
lavi_plugin/tools/*.rb         uma ferramenta por arquivo; cada uma chama Registry.register(..., handler: self)
lavi_plugin/ui/index.html      painel inteiro (CSS + JS); FORMS[id] declara campos, ações, prévia e resultado
lavi_plugin/ui/icon.svg        ícone da barra
updates/latest.json + .rbz      o que a atualização automática baixa
vendas/keygen.rb                gera chaves. NUNCA vai no .rbz nem para cliente
dev/build.sh                    gera dist/*.rbz e atualiza updates/
dev/preview.js                  abre o painel com mock e tira prints (Playwright)
dev/test_core.rb                testes da parte que não depende do SketchUp
dev/make_icons.py               gera ui/icons/*.svg e ui/icon.svg a partir do IC do painel
dev/load_test.rb + dev/stub/    carrega o .rbz com a API do SketchUp simulada (ruby -I dev/stub dev/load_test.rb)
docs/                           prints das telas
```

### Contrato Ruby ↔ painel
- JS chama `sketchup.run(JSON {req, tool, action, params})` → `Dialog.run` → `handler.handle(action, params)` → hash `{ok:, msg:, stats: [[rótulo, valor, ok?]], ...}` → `PLN.onResult([req, res])`.
- Ferramentas interativas (clique no modelo) devolvem `{picking: true}` na hora e mandam o resultado depois com `Dialog.push('result', {tool:, ok:, msg:, stats:})`.
- Para criar ferramenta nova: arquivo em `tools/`, `Registry.register(id, name:, tab:, package:, handler: self, desc:, steps: [3 passos])`, nome no `%w[]` do `main.rb`, formulário em `FORMS[id]` no `index.html`, ícone em `IC[id]`, linha em `MOCK.tools`.
- O painel tem **mock** do `sketchup` para abrir no navegador (`window.__MOCK__`, `window.__MOCK_RUN__`). `node dev/preview.js docs` tira os prints e falha se houver erro de JS.

### Pacotes (core/registry.rb)
`base` Essencial (grátis) · `pres` Apresentação · `arq` Arquitetura · `rev` Revestimentos · `marc` Marcenaria · `quant` Quantitativo · chave `PRO` libera todos.
Chave: `LAVI-<ARQ|REV|PRES|MARC|QUANT|PRO>-<5 chars>-<8 hex>`, verificador = SHA256(SECRET|pacote|serial).

## Ferramentas — status (v0.6.1; nada de geometria testado por ela ainda)
| id | ferramenta | pacote |
|---|---|---|
| walls | Paredes (clicando cantos ou de linhas selecionadas; meia-esquadria; digitar "5" = 5 m, unidade escolhível) | arq |
| openings | Portas e janelas (clica na parede, abre o vão, põe folha/vidro) | arq |
| dwg_walls | DWG → Paredes (pares paralelos, vergas e peitoris nos vãos) | arq |
| stairs | Escada reta Blondel, maciça ou flutuante, corrimão | arq |
| roofs | Telhado 1/2/4 águas, beiral, telhas | arq |
| urban_index | TO, CA, permeabilidade vs. limites da lei | arq |
| tiling / wall_tiling | Paginação de piso e de parede (rejunte, ½ ⅓, ângulo, furos, caixas, rejunte kg) | rev |
| baseboard | Rodapé (pula linhas de porta selecionadas com Shift, pilares) | rev |
| ceiling | Forro com sanca, placas | rev |
| cut_list | Lista de peças + plano de corte + fita + ferragens + CSV | marc |
| countertop | Recorte de cuba/cooktop no tampo | marc |
| takeoff | Quantitativo por material (piso/parede/teto) + itens + CSV | quant |
| scenes | Cenas automáticas: plantas por nível (corte 1,20), cobertura, cortes AA/BB, 4 fachadas, perspectiva | pres |
| export_images | Exportar cenas em PNG/JPG (formatos feed/story/A4…), moldura + grade de terços na tela (Overlay, SU 2023+), atalhos de câmera (altura, abertura, 2 pontos, vista) | pres |
| room_tags | Etiqueta de ambiente (texto 3D no piso ou rótulo) + quadro de áreas CSV; guarda persistent_id da face | pres |
| furniture | Ficha de mobiliário (dict `plane_item`), relatório por ambiente, CSV, caderno HTML com miniaturas | quant |
| model_health, align, replace, auto_tags, measure, isolate | Essenciais (grátis) | base |

## Marcenaria dinâmica — PAUSADA (fora do plugin desde a v0.5; código em `extras/marcenaria_dinamica/`)
Ela pediu para tirar e fazer depois, à parte. Tudo abaixo continua valendo para quando voltar.

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
- `Updater` lê `https://raw.githubusercontent.com/arqlais/plugin/HEAD/updates/latest.json` 20 s depois de abrir o SketchUp e de novo ao abrir o painel (se faz mais de 1 h). Guarda o aviso (`Updater.state`, vai no `send_state`) e o painel mostra a **barra "Nova versão · Atualizar" em todas as telas** (`#updbar`). Um clique (`update` → `install`) baixa, confere SHA256 e instala; depois só reiniciar o SketchUp, sem reinstalar pelo Gerenciador. Ela pediu isso: não quer ficar reinstalando.
- Nunca instala sem clique. Desde a v0.5 **nunca instala sozinho** (ela reclamou do SketchUp instável); instala só quando ela clica (baixa o `.rbz`, confere SHA256, `Sketchup.install_from_archive`, pede para reiniciar).
- Atenção: o LIA Render oficial e o LAVI Render dela (LIA modificado, backup no repo privado `lavi-app`, ramo `backup/lavi-render-v4`) usam a mesma pasta `thebox_render`: instalar um sobrescreve o outro.
- Para publicar versão nova: subir `VERSION` em `lavi_plugin.rb`, `sh dev/build.sh "nota 1" "nota 2"`, commit e merge no branch padrão.
- **Precisa de repositório público** (ou mover `updates/` para um host público, ex. o LAVI APP). Se o repo ficar privado, a atualização para de funcionar.

## Regras
- Ela pediu: **nada de funcionalidade desnecessária**, só o que é útil no SketchUp em si (por isso o Orçamento saiu na v0.7). Perguntar antes de inventar ferramenta nova.
- Referências de terceiros (HeyPrint, LIA etc.) servem só de ideia de interface: nunca copiar código.
- **Código 100% original.** Projetos antigos dela tinham plugins de terceiros modificados para remover licença: nada disso entra aqui.
- Antes de vender: `DEV_MODE = false` em `core/license.rb` e trocar o `SECRET` (o `keygen.rb` lê de lá). Com o repo público, o SECRET fica visível: o ideal é validar a chave online pelo app dela (Next.js + Redis + Mercado Pago PIX, já existente).
- Toda alteração geométrica dentro de `Helpers.operation` (um Ctrl+Z desfaz tudo).
- Namespace Ruby é `LAVIStudio::Plugin` (o nome `Plane` sozinho era genérico demais). `main.rb` carrega cada arquivo com `safe_require` e mostra os erros num messagebox + `%TEMP%/lavi_plugin_erros.txt`.
- Ela usa **SketchUp 2026 (Ruby 3.2)** no Windows. Compatível com SketchUp 2019+ (Ruby 2.5): evitar `&.`, `tally`, `filter_map`, sintaxe de Ruby 3.
- Antes de entregar: `ruby dev/test_core.rb`, `node dev/preview.js docs`, `sh dev/build.sh`, `ruby -I dev/stub dev/load_test.rb`. Entregar o `.rbz` + prints e explicar em linguagem simples o que testar.

## Próximos passos combinados
1. Ela testa a v0.4 (principalmente bloco dinâmico, paredes, vãos e paginação) e manda prints → corrigir.
2. Licença online + página de venda.
3. Plano de corte mais eficiente (maxrects) e etiquetas para impressão das peças.
