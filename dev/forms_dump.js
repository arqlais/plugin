// Exporta, do painel, os formulários de cada ferramenta (valores padrão + ações) para o teste no SketchUp simulado.
// Uso: node dev/forms_dump.js > dev/sim/forms.json
const path = require('path');
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  await p.goto('file://' + path.join(__dirname, '..', 'lavi_plugin', 'ui', 'index.html'));
  await p.waitForTimeout(300);
  const forms = await p.evaluate(() => window.__LAVI__.forms());
  process.stdout.write(JSON.stringify(forms, null, 1));
  await b.close();
})();
