// Converte os desenhos SVG do dev/render_sim.rb em PNG (com as fontes do painel).
// Uso: node dev/render_sheets.js pasta_svg pasta_png
const path = require('path'), fs = require('fs');
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const [src, out] = [process.argv[2], process.argv[3] || process.argv[2]];
const fonts = path.join(__dirname, '..', 'lavi_plugin', 'ui', 'fonts');
const b64 = f => fs.readFileSync(path.join(fonts, f)).toString('base64');
const css = `@font-face{font-family:Poppins;font-weight:600;src:url(data:font/woff2;base64,${b64('poppins-semibold.woff2')})}
@font-face{font-family:'JetBrains Mono';src:url(data:font/woff2;base64,${b64('jetbrains-mono-latin-400-normal.woff2')})}body{margin:0}`;
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ deviceScaleFactor: 2 });
  for (const f of fs.readdirSync(src).filter(x => x.endsWith('.svg')).sort()) {
    const svg = fs.readFileSync(path.join(src, f), 'utf8');
    const w = +svg.match(/width="(\d+)"/)[1], h = +svg.match(/height="(\d+)"/)[1];
    await p.setViewportSize({ width: w, height: h });
    await p.setContent(`<style>${css}</style>${svg}`);
    await p.waitForTimeout(150);
    await p.screenshot({ path: path.join(out, f.replace('.svg', '.png')) });
    console.log('png', f);
  }
  await b.close();
})();
