// Junta prints de telas e desenhos 3D em folhas com título. Uso: node dev/prints_folhas.js pasta_prints pasta_saida
const path=require('path'),fs=require('fs');const {chromium}=require('playwright');
const T=process.argv[2], OUT=process.argv[3], F=path.resolve('lavi_plugin/ui/fonts');
const b64=f=>fs.readFileSync(path.join(F,f)).toString('base64');
const css=`@font-face{font-family:P;font-weight:600;src:url(data:font/woff2;base64,${b64('poppins-semibold.woff2')})}
@font-face{font-family:P;font-weight:400;src:url(data:font/woff2;base64,${b64('poppins-regular.woff2')})}
body{margin:0;background:#F5F1EE;font-family:P;color:#3E4B57;padding:40px}
h1{font-weight:600;font-size:44px;margin:0 0 4px;letter-spacing:-.02em}h1 span{color:#A88A80}
p.s{margin:0 0 30px;font-size:22px;color:#8B939A}
.g{display:grid;gap:28px;align-items:start}
figure{margin:0;background:#fff;border:1px solid #EBE1DC;border-radius:24px;overflow:hidden}
figure img{display:block;width:100%}
figcaption{font-size:20px;padding:14px 20px;border-top:1px solid #EBE1DC}`;
const SHEETS=[
 ['01-inicio','lavi<span>.</span> painel','início claro e escuro',['00-inicio','99-inicio-escuro'],2],
 ['02-apresentacao','Apresentação','cenas, exportar imagens, etiquetas de ambiente',['01-scenes','02-export_images','03-room_tags'],3],
 ['03-arquitetura-1','Arquitetura','paredes, portas e janelas, DWG → paredes, escada',['05-walls','06-openings','07-dwg_walls','08-stairs'],4],
 ['04-arquitetura-2','Arquitetura','telhado, índices, limpar DWG, cotas',['09-roofs','10-urban_index','11-dwg_clean','12-dims'],4],
 ['05-revestimentos','Revestimentos','revestimento, rodapé, forro',['13-tiling','14-baseboard','15-ceiling'],3],
 ['06-marcenaria-quantitativo','Marcenaria e quantitativo','plano de corte, recorte de tampo, mobiliário, quantitativo',['16-cut_list','17-countertop','18-furniture','19-takeoff'],4],
 ['07-essenciais-1','Essenciais (grátis)','medir, isolar, saúde do modelo, alinhar, substituir',['04-measure','20-isolate','21-model_health','22-align','23-replace'],5],
 ['08-essenciais-2','Essenciais (grátis) · novas','copiar em grade, corrigir faces, seleção inteligente, etiquetas',['24-array','25-fix_faces','26-smart_select','27-auto_tags'],4],
 ['09-resultado-3d-arquitetura','Resultado no modelo','o que as ferramentas desenham (SketchUp simulado)',['01-paredes-portas-janelas','11-dwg-paredes','02-escadas','03-telhados','07-cotas','06-forro-sanca-spots'],2],
 ['10-resultado-3d-revestimento','Resultado no modelo · revestimento','8 padrões, pilar recortado no formato, parede 3D',['04-piso-horizontal','04-piso-tijolo','04-piso-espinha','04-piso-chevron','04-piso-damas','04-piso-organica','05-parede-tijolinho-3d','10-cuba','08-cadeiras-caminho'],3],
];
const N={"walls": "Paredes", "openings": "Portas e janelas", "dwg_walls": "DWG → Paredes", "stairs": "Escada", "roofs": "Telhado", "urban_index": "Índices urbanísticos", "tiling": "Revestimento", "baseboard": "Rodapé", "ceiling": "Forro e sanca", "scenes": "Cenas automáticas", "export_images": "Exportar imagens", "room_tags": "Ambientes e quadro de áreas", "furniture": "Ficha de mobiliário", "measure": "Medir seleção", "isolate": "Isolar seleção", "cut_list": "Lista de peças e plano de corte", "countertop": "Recorte de cuba e cooktop", "takeoff": "Quantitativo", "model_health": "Saúde do modelo", "align": "Alinhar e distribuir", "replace": "Selecionar e substituir", "dwg_clean": "Limpar DWG", "dims": "Cotas automáticas", "array": "Copiar em grade ou caminho", "fix_faces": "Corrigir faces invertidas", "smart_select": "Seleção inteligente", "auto_tags": "Etiquetas automáticas", "paredes-portas-janelas": "Paredes + porta + janela", "dwg-paredes": "DWG → Paredes", "escadas": "Escadas", "telhados": "Telhados", "cotas": "Cotas automáticas", "forro-sanca-spots": "Forro + spots em grade", "piso-horizontal": "Piso horizontal", "piso-tijolo": "Piso tijolinho", "piso-espinha": "Piso espinha", "piso-chevron": "Piso chevron", "piso-damas": "Piso damas", "piso-organica": "Pedra orgânica", "parede-tijolinho-3d": "Parede tijolinho 3D", "cuba": "Cuba dupla no tampo", "cadeiras-caminho": "Cadeiras no caminho"};
const label=f=>({'00-inicio':'Início','99-inicio-escuro':'Modo escuro'}[f]||N[f.replace(/^\d+-/,'')]||f);
(async()=>{const br=await chromium.launch();const pg=await br.newPage({viewport:{width:1200,height:800},deviceScaleFactor:1});
for(const [name,title,sub,files,cols] of SHEETS){
  const w=cols*520+80+(cols-1)*28;
  await pg.setViewportSize({width:w,height:800});
  const imgs=files.map(f=>`<figure><img src="data:image/png;base64,${fs.readFileSync(path.join(T,f+'.png')).toString('base64')}"><figcaption>${label(f)}</figcaption></figure>`).join('');
  await pg.setContent(`<style>${css}</style><h1>${title}</h1><p class="s">${sub}</p><div class="g" style="grid-template-columns:repeat(${cols},1fr)">${imgs}</div>`);
  await pg.waitForTimeout(300);
  await pg.screenshot({path:path.join(OUT,name+'.png'),fullPage:true}); console.log(name);
}
await br.close();})();
