// Prints de todas as telas do painel (uma por ferramenta). Uso: node dev/prints_telas.js pasta
const path=require('path');const {chromium}=require('playwright');
(async()=>{const b=await chromium.launch();const pg=await b.newPage({viewport:{width:430,height:900},deviceScaleFactor:2});
const errs=[];pg.on('pageerror',e=>errs.push(e.message));
await pg.goto('file://'+path.resolve('lavi_plugin/ui/index.html'));await pg.waitForTimeout(600);
await pg.addStyleTag({content:'body{overflow:visible!important}#app{height:auto!important}main{overflow:visible!important;padding-bottom:16px!important}.actions{position:static!important;border-top:0!important}#updbar{display:none}'});
const out=process.argv[2];
await pg.screenshot({path:`${out}/00-inicio.png`,fullPage:true});
const ids=await pg.evaluate(()=>[...document.querySelectorAll('.tool[data-tool]')].map(e=>e.dataset.tool));
const uniq=[...new Set(ids)];
let i=1;
for(const id of uniq){ if(await pg.$('.thead [data-back]')) await pg.click('.thead [data-back]'); await pg.click(`.tool[data-tool="${id}"]`); await pg.waitForTimeout(500);
  await pg.screenshot({path:`${out}/${String(i).padStart(2,'0')}-${id}.png`,fullPage:true}); i++; }
await pg.click('.thead [data-back]'); await pg.click('#btnTheme'); await pg.waitForTimeout(300); await pg.screenshot({path:`${out}/99-inicio-escuro.png`,fullPage:false});
console.log(uniq.length, errs.join('|')||'sem erros');await b.close();})();
