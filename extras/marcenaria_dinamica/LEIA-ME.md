# Marcenaria dinâmica (pausada)

Tirada do plugin na v0.5 a pedido da Laís: será retomada depois, como produto à parte.
Aqui está tudo pronto para voltar: avaliador de fórmulas DC, árvore de peças, receita do módulo,
montagem no SketchUp (joinery.rb), render de conferência e testes (720 combinações).

- Testes: `ruby extras/marcenaria_dinamica/test_dc.rb`
- Render: `ruby extras/marcenaria_dinamica/render_dc.rb pasta`
- Para religar: mover dc_formula.rb e dc_tree.rb para plane_plugin/core/, joinery*.rb para plane_plugin/tools/,
  pôr os nomes de volta no main.rb e o formulário `joinery` de volta no index.html (ver histórico do git, v0.4.2).
