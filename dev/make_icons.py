# Gera os ícones da barra de ferramentas (SVG) a partir do objeto IC do painel.
# Uso: python3 dev/make_icons.py
import re, os, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
html = (root / 'lavi_plugin/ui/index.html').read_text(encoding='utf-8')
block = html[html.index('const IC = {'):html.index('};', html.index('const IC = {'))]
icons = dict(re.findall(r"\n\s*([a-z_]+):'([^']+)'", block))
out = root / 'lavi_plugin/ui/icons'
out.mkdir(exist_ok=True)
INK = '#3E4B57'
for name, d in icons.items():
    (out / f'{name}.svg').write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
        # desenho reduzido a 80% (margem igual à dos outros plugins) e traço fino (1,2 px efetivo)
        f'<path d="{d}" transform="translate(2.4 2.4) scale(.8)" fill="none" stroke="{INK}" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"/></svg>\n',
        encoding='utf-8')
# ícone principal: sem fundo; planta em vinho e giro da porta em pink (só ele é colorido)
(root / 'lavi_plugin/ui/icon.svg').write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
    '<g transform="translate(2.4 2.4) scale(.8)" fill="none" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M4 4h16v16H4zM14 4v6M4 13h7" stroke="#3E4B57" stroke-width="1.6"/>'
    '<path d="M11 13A7 7 0 0 1 4 20" stroke="#A88A80" stroke-width="1.6"/></g></svg>\n',
    encoding='utf-8')
print(len(icons), 'ícones gerados')
