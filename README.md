# LAVI · plugin para SketchUp

Ferramentas para SketchUp feitas para quem projeta: paredes, portas e janelas, planta DWG em 3D, escada, telhado, índices urbanísticos, paginação de piso e parede, rodapé, forro, lista de peças com plano de corte e quantitativo.

- **Instalar:** SketchUp › Extensões › Gerenciador de extensões › Instalar extensão › escolher o `.rbz` (o mais novo fica em `updates/lavi_plugin.rbz`).
- **Atualizar:** automático. O plugin confere `updates/latest.json` sempre que o SketchUp abre.
- **Gerar o .rbz e publicar atualização:** `sh dev/build.sh "o que mudou"`
- **Testes:** `ruby dev/test_core.rb` e `node dev/preview.js docs` (prints das telas em `docs/`)
- **Gerar chaves de cliente:** `ruby vendas/keygen.rb MARC 5` (só você; nunca enviar este arquivo).
- **Contexto completo para o Claude Code:** veja `CLAUDE.md`.
