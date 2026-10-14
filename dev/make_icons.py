# Gera os ícones da barra de ferramentas (SVG) a partir do objeto IC do painel.
# Uso: python3 dev/make_icons.py
import re, os, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
html = (root / 'lavi_plugin/ui/index.html').read_text(encoding='utf-8')
block = html[html.index('const IC = {'):html.index('};', html.index('const IC = {'))]
icons = dict(re.findall(r"\n\s*([a-z_]+):'([^']+)'", block))
out = root / 'lavi_plugin/ui/icons'
out.mkdir(exist_ok=True)
INK = '#3A3437'
for name, d in icons.items():
    (out / f'{name}.svg').write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
        f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>\n',
        encoding='utf-8')
# ícone principal: quadrado lima com a planta em vinho
(root / 'lavi_plugin/ui/icon.svg').write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
    '<rect x="0.5" y="0.5" width="23" height="23" rx="5" fill="#D3DC2A"/>'
    f'<path d="{icons["lavi"]}" fill="none" stroke="#5C0632" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>\n',
    encoding='utf-8')
print(len(icons), 'ícones gerados')
