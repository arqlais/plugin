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
 ['02-novidades-telas','Novidades no painel · v0.12','ripado, guarda-corpo, pilares e vigas, espalhar, sol, peso do modelo, etiquetas de corte, porta completa',['ripado','railing','structure','scatter','sun','model_health','cut_list','openings'],4],
 ['03-novidades-3d','Novidades no modelo · v0.12','ripado, escadas em L/U/caracol, porta completa, planta, espalhar, guarda-corpo, estrutura',['24-ripado-3d','25-escadas-l-u-caracol','27-porta-completa','28-porta-planta','26-espalhar','29-guarda-corpo-varanda','30-pilares-vigas'],2],
 ['04-apresentacao-render','Apresentação e render','cenas, imagens, ambientes, sol, arestas, materiais, texturas, luzes, variar, espalhar',['scenes','export_images','room_tags','sun','edges','materials','texmap','lights','randomize','scatter'],5],
 ['05-arquitetura','Arquitetura','paredes, portas e janelas, DWG, escada, guarda-corpo, estrutura, telhado, cotas',['walls','openings','dwg_walls','stairs','railing','structure','roofs','dims'],4],
 ['06-revestimentos-marcenaria','Revestimentos, marcenaria e quantitativo','revestimento, ripado, rodapé, forro, plano de corte, recorte de tampo, quantitativo e mobiliário',['tiling','ripado','baseboard','ceiling','cut_list','countertop','takeoff'],4],
 ['07-essenciais','Essenciais (grátis)','medir, isolar, saúde do modelo, alinhar, seleção, copiar, faces, etiquetas, arredondar',['measure','isolate','model_health','align','smart_select','array','fix_faces','auto_tags','shape'],5],
 ['08-resultado-3d-arquitetura','Resultado no modelo','o que as ferramentas desenham (SketchUp simulado)',['01-paredes-portas-janelas','11-dwg-paredes','02-escadas','03-telhados','07-cotas','06-forro-sanca-spots'],2],
 ['09-resultado-3d-revestimento','Resultado no modelo · revestimento','8 padrões, pilar recortado no formato, parede 3D',['04-piso-horizontal','04-piso-tijolo','04-piso-espinha','04-piso-chevron','04-piso-damas','04-piso-organica','05-parede-tijolinho-3d','10-cuba'],2],
 ['10-resultado-3d-v010','Resultado no modelo · v0.10','tabica, cortineiro, moldura, rodapés, recorte automático, pedra rústica, aberturas do DWG',['12-forro-tabica-cortineiro','13-moldura-classica','14-rodapes','15-cuba-automatica','16-pedra-rustica','17-dwg-aberturas'],2],
 ['11-resultado-3d-v011','Resultado no modelo · v0.11','vãos por distância, guarda-corpos, arredondar todas as arestas, curvar, luzes, variar',['23-arredondar-arestas','22-vaos-posicao','18-guarda-corpos','19-arredondar-curvar','20-luzes','21-variar'],2]
];
const N={"paredes-portas-janelas": "Paredes + porta + janela", "dwg-paredes": "DWG → Paredes", "escadas": "Escadas", "telhados": "Telhados", "cotas": "Cotas automáticas", "forro-sanca-spots": "Forro + spots em grade", "piso-horizontal": "Piso horizontal", "piso-tijolo": "Piso tijolinho", "piso-espinha": "Piso espinha", "piso-chevron": "Piso chevron", "piso-damas": "Piso damas", "piso-organica": "Pedra orgânica", "parede-tijolinho-3d": "Parede tijolinho 3D", "cuba": "Cuba dupla no tampo", "cadeiras-caminho": "Cadeiras no caminho", "24-ripado-3d": "Ripado em pé e deitado", "25-escadas-l-u-caracol": "Escadas em L, U e caracol", "26-espalhar": "Espalhar objetos", "27-porta-completa": "Porta com batente e guarnição", "28-porta-planta": "Abertura e P1 na planta", "29-guarda-corpo-varanda": "Guarda-corpo na varanda", "30-pilares-vigas": "Pilares e vigas"};
// acha o print pelo nome mesmo se a numeração mudou (ex.: 'walls' acha '07-walls.png')
// nomes das ferramentas lidos do painel (linhas do MOCK.tools)
const HTML=fs.readFileSync(path.resolve('lavi_plugin/ui/index.html'),'utf8');
for(const m of HTML.matchAll(/\n    \['([a-z_]+)','([^']+)'/g)) if(!N[m[1]]) N[m[1]]=m[2];
const find=f=>{ if(fs.existsSync(path.join(T,f+'.png'))) return f; const base=f.replace(/^\d+-/,''); const hit=fs.readdirSync(T).find(x=>x.replace(/^\d+-/,'')===base+'.png'); return hit?hit.slice(0,-4):f; };
const label=f=>({'00-inicio':'Início','99-inicio-escuro':'Modo escuro'}[f]||N[f]||N[f.replace(/^\d+-/,'')]||f);
(async()=>{const br=await chromium.launch();const pg=await br.newPage({viewport:{width:1200,height:800},deviceScaleFactor:1});
for(const [name,title,sub,files,cols] of SHEETS){
  const w=cols*520+80+(cols-1)*28;
  await pg.setViewportSize({width:w,height:800});
  const imgs=files.map(find).map(f=>`<figure><img src="data:image/png;base64,${fs.readFileSync(path.join(T,f+'.png')).toString('base64')}"><figcaption>${label(f)}</figcaption></figure>`).join('');
  await pg.setContent(`<style>${css}</style><h1>${title}</h1><p class="s">${sub}</p><div class="g" style="grid-template-columns:repeat(${cols},1fr)">${imgs}</div>`);
  await pg.waitForTimeout(300);
  await pg.screenshot({path:path.join(OUT,name+'.png'),fullPage:true}); console.log(name);
}
await br.close();})();
