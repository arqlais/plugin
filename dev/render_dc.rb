# Desenha os módulos de marcenaria calculados (sem SketchUp) em SVG, para conferir a montagem.
# Uso: ruby dev/render_dc.rb pasta_de_saida
# Projeção oblíqua: frente (Y=0) virada para quem olha, lateral direita e topo visíveis.

ROOT_DIR = File.expand_path('..', __dir__)
module PlaneLA; module Plugin; end; end
%w[dc_formula dc_tree].each { |f| require File.join(ROOT_DIR, 'plane_plugin', 'core', f) }
require File.join(ROOT_DIR, 'plane_plugin', 'tools', 'joinery_spec')

S = PlaneLA::Plugin::JoinerySpec
out = ARGV[0] || File.join(ROOT_DIR, 'docs')
Dir.mkdir(out) unless Dir.exist?(out)
COLORS = Hash[(S::MAT_FRENTE + S::MAT_TAMPO).map { |_l, n, h| [n, h] }].merge(S::FIXED)

def base(tipo, over = {})
  t = S::TIPOS[tipo]
  { tipo: tipo, nome: t[:nome], lx: t[:lx], ly: t[:ly], lz: t[:lz], frente: t[:frente], nportas: t[:nportas],
    ngav: t[:ngav], hgav: 18, prat: t[:prat], puxador: 2, matfrente: 'PLN_Freijo', matcaixa: 'PLN_Branco',
    tampo: t[:tampo], mattampo: 'PLN_QuartzoBranco', esptampo: 2, esp: 1.5, espf: 1.8, fundo: 0.6, folga: 0.3,
    rod: t[:rod], rodrec: 5, pz: t[:pz] }.merge(over)
end

def shade(hex, f)
  r, g, b = hex.scan(/../).map { |c| (c.to_i(16) * f).round.clamp(0, 255) }
  format('#%02X%02X%02X', r, g, b)
end

def svg(boxes, w = 380, h = 380, title = '')
  k = 0.45
  pr = ->(x, y, z) { [x + y * k * 0.8, -(z + y * k * 0.6)] }
  pts = boxes.flat_map do |b|
    x, y, z = b[:org]
    lx, ly, lz = b[:size]
    [[x, y, z], [x + lx, y + ly, z + lz]].map { |p| pr.call(*p) }
  end
  xs = pts.map(&:first)
  ys = pts.map(&:last)
  sc = [(w - 40) / (xs.max - xs.min), (h - 60) / (ys.max - ys.min)].min
  tx = ->(p) { format('%.1f,%.1f', 20 + (p[0] - xs.min) * sc, 40 + (p[1] - ys.min) * sc) }
  body = boxes.sort_by { |b| [-(b[:org][1] + b[:size][1]), b[:org][2], b[:org][0]] }.map do |b|
    x, y, z = b[:org]
    lx, ly, lz = b[:size]
    c = COLORS[b[:mat].to_s] || 'DDDDDD'
    front = [[x, y, z], [x + lx, y, z], [x + lx, y, z + lz], [x, y, z + lz]]
    top = [[x, y, z + lz], [x + lx, y, z + lz], [x + lx, y + ly, z + lz], [x, y + ly, z + lz]]
    side = [[x + lx, y, z], [x + lx, y + ly, z], [x + lx, y + ly, z + lz], [x + lx, y, z + lz]]
    [[side, 0.72], [top, 0.9], [front, 1.0]].map do |poly, f|
      "<polygon points=\"#{poly.map { |p| tx.call(pr.call(*p)) }.join(' ')}\" fill=\"##{shade(c, f).delete('#')}\" stroke=\"#3E4B57\" stroke-width=\".6\"/>"
    end.join
  end.join("\n")
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{w}\" height=\"#{h}\" viewBox=\"0 0 #{w} #{h}\"><rect width=\"100%\" height=\"100%\" fill=\"#F6F3F4\"/>" \
    "<text x=\"14\" y=\"22\" font-family=\"sans-serif\" font-size=\"13\" fill=\"#2F3A45\">#{title}</text>#{body}</svg>"
end

CASES = [
  ['inferior_gaveta_porta', base('inferior')],
  ['inferior_2portas_120', base('inferior', lx: 120, frente: 1, nportas: 2, prat: 2)],
  ['gaveteiro_4', base('gaveteiro', puxador: 1)],
  ['aereo_2portas', base('aereo', puxador: 3, matfrente: 'PLN_Lilas')],
  ['torre', base('torre')],
  ['nicho', base('nicho', prat: 2)],
  ['basculante', base('basculante')],
  ['inferior_aberto_sem_frente', base('inferior', frente: 4, prat: 2, lx: 90)]
]

files = []
CASES.each do |name, s|
  tree = S.build(s)
  boxes = tree.boxes
  file = File.join(out, "dc_#{name}.svg")
  File.write(file, svg(boxes, 380, 380, "#{name} · #{s[:lx]}×#{s[:ly]}×#{s[:lz]} · #{boxes.size} peças"))
  files << file
end
# visão sem frentes (para ver a caixa por dentro)
s = base('inferior', frente: 3, ngav: 3)
tree = S.build(s)
inner = tree.boxes.reject { |b| %w[porta frente_gaveta tampo puxador acabamento].include?(b[:part]) }
File.write(File.join(out, 'dc_gaveteiro_por_dentro.svg'), svg(inner, 380, 380, 'gavetas sem as frentes'))
puts files
