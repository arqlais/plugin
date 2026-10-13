// Abre o painel fora do SketchUp (com o mock) e tira prints das telas.
// Uso: node dev/preview.js [pasta-de-saida]
const path = require('path');
const fs = require('fs');
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }

const out = process.argv[2] || path.join(__dirname, '..', 'docs');
fs.mkdirSync(out, { recursive: true });
const url = 'file://' + path.join(__dirname, '..', 'plane_plugin', 'ui', 'index.html');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 430, height: 820 }, deviceScaleFactor: 2 });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(url);
  await page.waitForTimeout(500);

  const shot = async (name, full) => {
    await page.waitForTimeout(650);
    if (full) await page.addStyleTag({ content: 'body{overflow:visible!important}#app{height:auto!important}main{overflow:visible!important}.actions{display:none!important}', }).then(h => (page._full = h));
    await page.screenshot({ path: path.join(out, name + '.png'), fullPage: !!full });
    if (full) await page.evaluate(() => { const st = document.querySelectorAll('style'); st[st.length - 1].remove(); });
    console.log('print', name);
  };
  const tool = async id => { await page.click(`[data-tab="${TABS[id]}"]`); await page.click(`.tool[data-tool="${id}"]`); };
  const TABS = { walls: 'arq', openings: 'arq', stairs: 'arq', roofs: 'arq', dwg_walls: 'arq', urban_index: 'arq', tiling: 'rev', wall_tiling: 'rev', baseboard: 'rev', ceiling: 'rev', joinery: 'marc', cut_list: 'marc', countertop: 'marc', takeoff: 'quant', budget: 'quant', model_health: 'base', align: 'base', replace: 'base', auto_tags: 'base' };

  await shot('01-inicio');
  await page.click('[data-tab="marc"]'); await shot('02-aba-marcenaria');

  await tool('joinery'); await shot('03-marcenaria');
  await page.click('[data-set="matfrente"][data-v="PLN_Freijo"]');
  await page.click('.card[data-set="frente"][data-v="3"]');
  await page.click('.card[data-set="puxador"][data-v="2"]');
  await shot('04-marcenaria-gavetas', true);

  await tool('tiling');
  await page.click('.card[data-set="padrao"][data-v="meia"]');
  await page.click('[data-preset="4"]');
  await page.click('[data-act="build"]');
  await shot('05-piso', true);

  await tool('stairs'); await shot('06-escada');
  await tool('cut_list'); await page.click('[data-act="list"]'); await page.waitForTimeout(700); await shot('07-plano-de-corte', true);
  await tool('budget'); await page.click('[data-act="load"]'); await page.waitForTimeout(700); await shot('08-orcamento', true);
  await tool('model_health'); await page.click('[data-act="scan"]'); await page.waitForTimeout(700); await shot('09-saude');
  await tool('openings'); await page.click('.card[data-set="tipo"][data-v="janela"]'); await shot('10-janelas');
  await tool('roofs'); await shot('11-telhado');

  // varre todas as ferramentas atrás de erros
  for (const id of Object.keys(TABS)) { await tool(id); await page.waitForTimeout(80); }

  await page.click('#btnTheme');
  await page.click('[data-tab="home"]');
  await shot('12-inicio-escuro');
  await tool('joinery'); await shot('13-marcenaria-escuro');
  await page.click('#btnLic'); await shot('14-licenca-escuro');

  await browser.close();
  if (errors.length) { console.error('ERROS NO PAINEL:\n' + errors.join('\n')); process.exit(1); }
  console.log('sem erros');
})();
