# Desenha (SVG) o que cada ferramenta cria no SketchUp simulado — "prints" do resultado 3D
# para conferir sem abrir o SketchUp. Uso: ruby dev/render_sim.rb pasta_de_saida
# Depois: node dev/render_sheets.js pasta_de_saida docs  (monta as folhas em PNG)

$RUN_CHECKS = false
require_relative 'sim_test'

OUTDIR = ARGV[0] || File.join(Dir.tmpdir, 'lavi_render')
Dir.mkdir(OUTDIR) unless Dir.exist?(OUTDIR)
WOODS = %w[#B88A62 #A9774E #C69C72 #9C6B45 #D2B48C].freeze

def color_of(mat)
  return [233, 228, 222] unless mat
  if mat.texture
    h = WOODS[mat.name.sum % WOODS.size]
    return [h[1, 2].to_i(16), h[3, 2].to_i(16), h[5, 2].to_i(16)]
  end
  c = mat.color
  [c.red, c.green, c.blue]
end

# faces ligadas por arestas suaves formam um grupo só (a linha entre elas não aparece, como no SketchUp)
def smooth_groups(ents)
  par = {}
  find = ->(f) { par[f] = find.call(par[f]) if par[f] && !par[f].equal?(f); par[f] || f }
  ents.grep(Sketchup::Edge).each do |e|
    next unless e.respond_to?(:soft?) && e.soft?
    fs = e.faces
    next unless fs.size == 2
    a = find.call(fs[0])
    b = find.call(fs[1])
    par[a] = b unless a.equal?(b)
  end
  par
end

def collect(ents, tr, mat, out)
  par = smooth_groups(ents)
  root = ->(f) { r = f; r = par[r] while par[r] && !par[r].equal?(r); r }
  $grp_ids ||= {}
  ents.each do |e|
    next if e.respond_to?(:hidden?) && e.hidden?
    case e
    when Sketchup::Face
      loops = e.loops.map { |l| l.vertices.map { |v| v.position.transform(tr) } }
      n = e.normal.transform(tr)
      g = root.call(e)
      out[:faces] << [loops, n.normalize, e.material || mat, e.back_material, ($grp_ids[[g.object_id, tr.to_a]] ||= $grp_ids.size)]
    when Sketchup::ComponentInstance
      collect(e.definition.entities, tr * e.transformation, e.material || mat, out)
    when Sketchup::DimensionLinear
      out[:dims] << [e.start[1].transform(tr), e.end[1].transform(tr), e.offset_vector.transform(tr)]
    when Sketchup::Edge
      out[:edges] << [e.start.position.transform(tr), e.end.position.transform(tr)] if e.faces.empty?
    when Sketchup::ConstructionPoint
      q = e.position.transform(tr)
      out[:marks] = (out[:marks] || []) << q
    end
  end
  out
end

# vista: :iso (de cima e de lado), :top (planta), :below (de baixo, para forro)
def render(name, title, view: :iso, az: -55, el: 32, w: 860, h: 560)
  data = collect(m.entities, IDENTITY, nil, { faces: [], dims: [], edges: [] })
  if view == :top
    d = Geom::Vector3d.new(0, 0, -1); right = X_AXIS.clone; up = Y_AXIS.clone
  else
    el = -el.abs if view == :below
    a = az * Math::PI / 180; b = el * Math::PI / 180
    d = Geom::Vector3d.new(Math.cos(b) * Math.cos(a), Math.cos(b) * Math.sin(a), -Math.sin(b)).reverse
    d = Geom::Vector3d.new(-Math.cos(b) * Math.cos(a), -Math.cos(b) * Math.sin(a), -Math.sin(b))
    right = d.cross(Z_AXIS).normalize
    up = right.cross(d).normalize
  end
  proj = ->(q) { v = Geom::Vector3d.new(q.to_a); [v.dot(right), -v.dot(up), v.dot(d)] }
  pts = data[:faces].flat_map { |l, *_| l.flatten.map { |q| proj.call(q) } } +
        data[:dims].flat_map { |a, b, o| [proj.call(a.offset(o)), proj.call(b.offset(o))] } +
        data[:edges].flatten.map { |q| proj.call(q) }
  return if pts.empty?
  xs = pts.map(&:first); ys = pts.map { |p| p[1] }
  pad = 40
  k = [(w - 2 * pad) / [xs.max - xs.min, 1e-6].max, (h - 2 * pad - 30) / [ys.max - ys.min, 1e-6].max].min
  tx = ->(p) { [(pad + (p[0] - xs.min) * k).round(1), (pad + 30 + (p[1] - ys.min) * k).round(1)] }
  w = [(2 * pad + (xs.max - xs.min) * k).ceil, 520, title.size * 10 + 60].max
  h = (2 * pad + 30 + (ys.max - ys.min) * k).ceil
  ox = (w - (2 * pad + (xs.max - xs.min) * k)) / 2.0
  tx = ->(p) { [(ox + pad + (p[0] - xs.min) * k).round(1), (pad + 30 + (p[1] - ys.min) * k).round(1)] }
  light = Geom::Vector3d.new(-0.4, -0.7, 0.9).normalize
  # faces → z-buffer em Python (dev/zbuf.py) → imagem embutida no SVG
  faces = data[:faces].map do |loops, n, mat, back, grp|
    facing = n.dot(d) < 0
    col = color_of(facing ? mat : (back || mat))
    al = (facing ? mat : (back || mat))
    al = al ? al.alpha.to_f : 1.0
    col = col.zip([245, 241, 238]).map { |c, b| c * al + b * (1 - al) } if al < 1 # translúcido: clareia
    sh = 0.62 + 0.38 * n.dot(light).abs
    sh *= 0.85 unless facing
    { loops: loops.map { |l| l.map { |q| pr = proj.call(q); tx.call(pr) + [pr[2]] } },
      rgb: col.map { |c| [[c * sh, 255].min, 0].max.round }, grp: grp }
  end
  json = File.join(OUTDIR, "#{name}.json")
  png = File.join(OUTDIR, "#{name}.z.png")
  File.write(json, JSON.generate(w: w, h: h, scale: 2, faces: faces))
  system('python3', File.join(__dir__, 'zbuf.py'), json, png) or raise 'zbuf falhou'
  require 'base64'
  img = Base64.strict_encode64(File.binread(png))
  File.delete(json)
  svg = +%(<svg xmlns="http://www.w3.org/2000/svg" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}"><image width="#{w}" height="#{h}" href="data:image/png;base64,#{img}"/>)
  svg << %(<text x="24" y="34" font-family="Poppins" font-weight="600" font-size="17" fill="#3E4B57">#{title}</text>)
  data[:edges].each { |a, b| p1 = tx.call(proj.call(a)); p2 = tx.call(proj.call(b)); svg << %(<line x1="#{p1[0]}" y1="#{p1[1]}" x2="#{p2[0]}" y2="#{p2[1]}" stroke="#A88A80" stroke-width="1.2"/>) }
  (data[:marks] || []).each do |q|
    c = tx.call(proj.call(q))
    svg << %(<circle cx="#{c[0]}" cy="#{c[1]}" r="14" fill="none" stroke="#C0392B" stroke-width="2.5"/><path d="M#{c[0] - 8} #{c[1] - 8}l16 16m0 -16l-16 16" stroke="#C0392B" stroke-width="2.5"/>)
  end
  data[:dims].each do |a, b, o|
    pa = tx.call(proj.call(a.offset(o))); pb = tx.call(proj.call(b.offset(o)))
    ea = tx.call(proj.call(a)); eb = tx.call(proj.call(b))
    len = (a.distance(b) * 2.54).round
    mx = (pa[0] + pb[0]) / 2; my = (pa[1] + pb[1]) / 2
    svg << %(<g stroke="#A88A80" stroke-width="1"><line x1="#{ea[0]}" y1="#{ea[1]}" x2="#{pa[0]}" y2="#{pa[1]}" stroke-dasharray="2 2"/><line x1="#{eb[0]}" y1="#{eb[1]}" x2="#{pb[0]}" y2="#{pb[1]}" stroke-dasharray="2 2"/><line x1="#{pa[0]}" y1="#{pa[1]}" x2="#{pb[0]}" y2="#{pb[1]}"/></g>)
    svg << %(<text x="#{mx}" y="#{my - 4}" text-anchor="middle" font-family="JetBrains Mono" font-size="12" fill="#3E4B57" paint-order="stroke" stroke="#F5F1EE" stroke-width="3">#{len}</text>)
  end
  File.write(File.join(OUTDIR, "#{name}.svg"), svg + '</svg>')
  puts "desenho #{name}"
end

def scene(name)
  return if ENV['ONLY'] && !name.include?(ENV['ONLY'])
  fresh
  yield
rescue StandardError => e
  puts "ERRO #{name}: #{e.class}: #{e.message} #{e.backtrace.first}"
end

wall_room = lambda do
  run(:walls, 'draw')
  click_points([pt(0, 0), pt(400, 0), pt(400, 300), pt(0, 300)], closed: true)
  m.entities.grep(Sketchup::ComponentInstance).first
end

scene('01-paredes-portas-janelas') do
  floor(pilar: false)
  w = wall_room.call
  face, tr = all_faces(w.definition.entities, w.transformation).select { |f, t| f.normal.transform(t).y < -0.9 }.max_by { |f, _| f.area }
  run(:openings, 'place', 'tipo' => 'porta', 'larg' => 80, 'alt' => 210, 'peit' => 0)
  click_face(face, pt(100, -7.5, 100), tr)
  run(:openings, 'place', 'tipo' => 'janela', 'larg' => 150, 'alt' => 120, 'peit' => 100)
  click_face(face, pt(280, -7.5, 150), tr)
  render('01-paredes-portas-janelas', 'Paredes + porta + janela')
end

scene('02-escadas') do
  run(:stairs, 'place', 'tipo' => 'macica'); click_points([pt(0, 0), pt(0, 100)])
  run(:stairs, 'place', 'tipo' => 'flutuante'); click_points([pt(250, 0), pt(250, 100)])
  render('02-escadas', 'Escada maciça e flutuante (Blondel, 16 degraus)', az: -130, el: 25)
end

scene('03-telhados') do
  %w[1agua 2aguas 4aguas].each_with_index do |tipo, i|
    f = m.entities.add_face(pt(i * 1100, 0, 0), pt(i * 1100 + 800, 0, 0), pt(i * 1100 + 800, 600, 0), pt(i * 1100, 600, 0))
    sel(f); run(:roofs, 'build', 'tipo' => tipo, 'aguas' => tipo)
  end
  render('03-telhados', 'Telhado de 1, 2 e 4 águas, com beiral', el: 55, az: -60)
end

{ 'horizontal' => [60, 60], 'espinha' => [60, 15], 'chevron' => [60, 15], 'organica' => [40, 30], 'tijolo' => [60, 30], 'damas' => [40, 40] }.each_with_index do |(pat, (a, b)), i|
  scene("04-piso-#{pat}") do
    f = floor
    sel(f)
    run(:tiling, 'build', 'padrao' => pat, 'pc' => a, 'pl' => b, 'rej' => 4, 'cor' => '#E9E3DC', 'cor2' => '#3E4B57', 'correj' => '#9C9087')
    f.hidden = true
    render("04-piso-#{pat}", "Revestimento · #{pat} #{a}×#{b} (com pilar)", view: :top)
  end
end

scene('05-parede-tijolinho-3d') do
  wl = m.entities.add_face(pt(0, 0, 0), pt(300, 0, 0), pt(300, 0, 260), pt(0, 0, 260))
  sel(wl)
  imgs = (1..3).map { |i| File.join(OUT, "tijolo#{i}.jpg").tap { |f| File.write(f, 'jpg') } }
  run(:tiling, 'build', 'padrao' => 'tijolo', 'pc' => 30, 'pl' => 7.5, 'rej' => 10, 'relevo' => true, 'texturas' => imgs, 'correj' => '#D8D2CA')
  wl.hidden = true
  render('05-parede-tijolinho-3d', 'Revestimento de parede · tijolinho 3D com 3 imagens sorteadas', az: -70, el: 12)
end

scene('06-forro-sanca-spots') do
  f = floor(pilar: false)
  sel(f); run(:ceiling, 'build', 'sanca' => true)
  forro = m.entities.add_face(pt(0, 0, 259), pt(400, 0, 259), pt(400, 300, 259), pt(0, 300, 259))
  forro.reverse! if forro.normal.z > 0
  lum = component('Spot', 12, 12, 6, pt(20, 20, 253))
  lum.material = m.materials.add('Spot').tap { |x| x.color = Sketchup::Color.new(62, 75, 87) }
  sel(lum, forro); run(:array, 'build', 'modo' => 'grade', 'esp_x' => 100, 'esp_y' => 90, 'margem' => 60, 'apagar' => true)
  es = forro.edges
  forro.erase!
  es.each { |e| e.erase! if e.valid? }
  f.hidden = true
  render('06-forro-sanca-spots', 'Forro com sanca + spots copiados em grade (visto de baixo)', view: :below, az: -60, el: 35)
end

scene('07-cotas') do
  w = wall_room.call
  sel(w); run(:dims, 'build')
  render('07-cotas', 'Cotas automáticas · por fora, por dentro e totais', view: :top)
end

scene('08-cadeiras-caminho') do
  mesa = box(100, 100, 0, 200, 90, 75, name: 'Mesa')
  mesa.material = m.materials.add('Mesa').tap { |x| x.color = Sketchup::Color.new(184, 138, 98) }
  cad = component('Cadeira', 45, 45, 45, pt(0, 0))
  cad.material = m.materials.add('Cadeira').tap { |x| x.color = Sketchup::Color.new(62, 75, 87) }
  es = m.entities.add_edges(pt(60, 40), pt(340, 40), pt(340, 230), pt(60, 230))
  sel(cad, es); run(:array, 'build', 'modo' => 'caminho', 'por' => 'quantidade', 'qtd' => 4, 'apagar' => true)
  render('08-cadeiras-caminho', 'Copiar ao longo do caminho · 4 cadeiras na linha', el: 40)
end

scene('09-etiqueta-ambiente') do
  f = floor(pilar: false)
  UI.answers[:inputbox] = ->(*_a) { ['Sala de estar'] }
  run(:room_tags, 'place', 'estilo' => '3d'); click_face(f)
  render('09-etiqueta-ambiente', 'Etiqueta de ambiente · nome, área e pé-direito no piso', view: :top)
end

scene('10-cuba') do
  tampo = box(0, 0, 88, 120, 60, 3, name: 'Tampo')
  tampo.material = m.materials.add('Granito').tap { |x| x.color = Sketchup::Color.new(90, 90, 92) }
  sel(tampo); run(:countertop, 'cut', 'tipo' => 'cuba_dupla', 'larg' => 80, 'prof' => 40)
  render('10-cuba', 'Recorte no tampo · cuba dupla', el: 45)
end

scene('11-dwg-paredes') do
  out = [pt(-15, -15), pt(615, -15), pt(615, 415), pt(-15, 415)]
  es = []
  4.times { |i| es << m.entities.add_line(out[i], out[(i + 1) % 4]) }
  es << m.entities.add_line(pt(0, 0), pt(160, 0)) << m.entities.add_line(pt(240, 0), pt(600, 0))
  es << m.entities.add_line(pt(600, 0), pt(600, 400)) << m.entities.add_line(pt(600, 400), pt(0, 400)) << m.entities.add_line(pt(0, 400), pt(0, 0))
  sel(es); run(:dwg_walls, 'build')
  render('11-dwg-paredes', 'DWG → Paredes · linhas da planta viram paredes com o vão da porta')
end

scene('12-forro-tabica-cortineiro') do
  f = floor(160, 120, pilar: false)
  box(-15, 0, 0, 15, 120, 280, name: 'Parede').material = m.materials.add('Parede').tap { |x| x.color = Sketchup::Color.new(236, 232, 226) }
  janela = f.edges.find { |e| e.start.position.y.abs < 0.01 && e.end.position.y.abs < 0.01 }
  sel(f, janela)
  run(:ceiling, 'build', 'cortineiro' => true, 'cort_larg' => 15, 'cort_alt' => 20)
  f.hidden = true
  render('12-forro-tabica-cortineiro', 'Forro com tabica de 3 cm e cortineiro de 15 cm (visto de baixo)', view: :below, az: -110, el: 30)
end

scene('13-moldura-classica') do
  f = floor(pilar: false)
  wm = m.materials.add('Parede').tap { |x| x.color = Sketchup::Color.new(236, 232, 226) }
  box(-15, -15, 0, 15, 315, 260, name: 'Parede').material = wm
  box(-15, 300, 0, 415, 15, 260, name: 'Parede').material = wm
  sel(f)
  run(:ceiling, 'build', 'tipo' => 'moldura', 'mold_modelo' => 'classica', 'mold_tam' => 12, 'teto' => true)
  sel(f)
  run(:baseboard, 'build', 'modelo' => 'classico', 'alt' => 15, 'esp' => 2.5)
  render('13-moldura-classica', 'Sem rebaixo: moldura clássica no teto + rodapé clássico', az: -120, el: 18)
end

scene('14-rodapes') do
  %w[reto chanfrado boleado frisado classico filete].each_with_index do |mod, i|
    f = m.entities.add_face(pt(i * 70, 0), pt(i * 70 + 45, 0), pt(i * 70 + 45, 30), pt(i * 70, 30))
    f.reverse! if f.normal.z < 0
    sel(f)
    run(:baseboard, 'build', 'modelo' => mod, 'alt' => 12, 'esp' => 3, 'cor' => '#FFFFFF')
    f.hidden = true
  end
  render('14-rodapes', 'Rodapés: reto, chanfrado, boleado, frisado, clássico e filete', az: -70, el: 28)
end

scene('15-cuba-automatica') do
  tampo = box(0, 0, 88, 200, 60, 3, name: 'Tampo')
  tampo.material = m.materials.add('Granito').tap { |x| x.color = Sketchup::Color.new(90, 90, 92) }
  dfn = m.definitions.add('Cuba inox')
  f = dfn.entities.add_face(pt(0, 0), pt(50, 0), pt(50, 40), pt(0, 40))
  f.reverse! if f.normal.z > 0
  f.pushpull(-20.cm)
  $timers = []
  c = m.entities.add_instance(dfn, Geom::Transformation.new(pt(30, 10, 72)))
  c.material = m.materials.add('Inox').tap { |x| x.color = Sketchup::Color.new(200, 204, 208) }
  d2 = m.definitions.add('Cooktop 4 bocas')
  g = d2.entities.add_face(pt(0, 0), pt(56, 0), pt(56, 49), pt(0, 49))
  g.reverse! if g.normal.z > 0
  g.pushpull(-6.cm)
  k = m.entities.add_instance(d2, Geom::Transformation.new(pt(125, 6, 86)))
  k.material = m.materials.add('Vidro preto').tap { |x| x.color = Sketchup::Color.new(30, 30, 32) }
  $timers.each(&:call)
  c.hidden = true
  k.hidden = true
  render('15-cuba-automatica', 'Recorte automático: a cuba e o cooktop furaram o tampo no formato deles', el: 50, az: -60)
end

scene('16-pedra-rustica') do
  f = m.entities.add_face(pt(0, 0), pt(200, 0), pt(200, 140), pt(0, 140))
  f.reverse! if f.normal.z < 0
  sel(f)
  run(:tiling, 'build', 'padrao' => 'organica', 'pc' => 40, 'pl' => 30, 'rej' => 12, 'acabamento' => 'rustico', 'var' => 15, 'chanfro' => 8, 'esp' => 20, 'cor' => '#E3D3B5', 'correj' => '#8F887E')
  f.hidden = true
  render('16-pedra-rustica', 'Pedra São Tomé rústica: alturas e inclinações diferentes, borda chanfrada', az: -60, el: 22)
end

scene('17-dwg-aberturas') do
  m.entities.add_edges(pt(1, 0), pt(400, 0), pt(400, 300), pt(0, 300), pt(0, 0.5))
  m.entities.add_edges(pt(150, 300), pt(150, 180), pt(260, 180))
  m.entities.add_line(pt(262, 180), pt(400, 180.5))
  sel(m.entities.grep(Sketchup::Edge))
  run(:dwg_walls, 'clean', 'tol' => 1.5)
  render('17-dwg-aberturas', 'Limpar DWG: fechou o canto aberto e os encontros em T; a abertura de 2 cm ficou marcada', view: :top)
end

scene('18-guarda-corpos') do
  { 'vidro' => 'ambos', 'montantes' => 'ambos', 'cabos' => 'ambos', 'mureta' => 'ambos' }.each_with_index do |(g, l), i|
    run(:stairs, 'place', 'guarda' => g, 'lados' => l, 'tipo' => i.odd? ? 'flutuante' : 'macica')
    click_points([pt(i * 180, 0), pt(i * 180, 100)])
  end
  render('18-guarda-corpos', 'Guarda-corpo: vidro, montantes, cabos e mureta', az: -150, el: 22)
end

scene('19-arredondar-curvar') do
  wood = m.materials.add('Madeira').tap { |x| x.color = Sketchup::Color.new(184, 138, 98) }
  t1 = box(0, 0, 0, 120, 60, 4, name: 'Tampo', mat: wood); sel(t1); run(:shape, 'apply', 'modo' => 'cantos', 'raio' => 15, 'seg' => 10)
  t2 = box(150, 0, 0, 120, 60, 4, name: 'Tampo', mat: wood); sel(t2); run(:shape, 'apply', 'modo' => 'cantos', 'raio' => 12, 'seg' => 1)
  t3 = box(300, 0, 0, 120, 60, 6, name: 'Tampo', mat: wood); sel(t3); run(:shape, 'apply', 'modo' => 'bordas', 'raio' => 2.5, 'seg' => 8, 'cima' => true, 'baixo' => true)
  b = box(0, 120, 0, 300, 45, 45, name: 'Banco', mat: m.materials.add('Concreto').tap { |x| x.color = Sketchup::Color.new(190, 186, 180) })
  sel(b); run(:shape, 'apply', 'modo' => 'curvar', 'raio_curva' => 250, 'sentido' => 'direita', 'seg_curva' => 32)
  render('19-arredondar-curvar', 'Cantos arredondados, chanfrados, bordas boleadas e banco curvo', az: -60, el: 40)
end

scene('23-arredondar-arestas') do
  wh = m.materials.add('Branco').tap { |x| x.color = Sketchup::Color.new(236, 234, 230) }
  c1 = box(0, 0, 0, 60, 60, 60, name: 'Cubo', mat: wh); sel(c1); run(:shape, 'apply', 'modo' => 'tudo', 'acab' => 'redondo', 'raio' => 10, 'seg' => 6)
  c2 = box(90, 0, 0, 60, 60, 60, name: 'Cubo', mat: wh); sel(c2); run(:shape, 'apply', 'modo' => 'tudo', 'acab' => 'chanfro', 'raio' => 6)
  box(180, 0, 0, 60, 60, 60, name: 'Cubo', mat: wh)
  pf = box(0, 100, 0, 120, 50, 40, name: 'Puff', mat: m.materials.add('Linho').tap { |x| x.color = Sketchup::Color.new(200, 170, 160) })
  sel(pf); run(:shape, 'apply', 'modo' => 'tudo', 'acab' => 'redondo', 'raio' => 12, 'seg' => 8)
  tp = box(150, 100, 30, 120, 50, 4, name: 'Prateleira', mat: m.materials.add('Madeira').tap { |x| x.color = Sketchup::Color.new(184, 138, 98) })
  sel(tp); run(:shape, 'apply', 'modo' => 'tudo', 'acab' => 'redondo', 'raio' => 1.5, 'seg' => 4)
  render('23-arredondar-arestas', 'Todas as arestas: arredondado, chanfrado, original · puff e prateleira', az: -55, el: 28)
end

scene('24-ripado') do
  f = m.entities.add_face(pt(0, 0, 0), pt(300, 0, 0), pt(300, 0, 260), pt(0, 0, 260))
  f.reverse! if f.normal.y > 0
  h = m.entities.add_face(pt(110, 0, 0.0001), pt(190, 0, 0.0001), pt(190, 0, 210), pt(110, 0, 210))
  h.erase! if h && h.valid? && !h.equal?(f)
  sel(f); run(:ripado, 'build', 'larg' => 4, 'vao' => 2, 'prof' => 2, 'cor_ripa' => '#B88A62')
  f2 = m.entities.add_face(pt(360, 0, 0), pt(560, 0, 0), pt(560, 0, 260), pt(360, 0, 260))
  f2.reverse! if f2.normal.y > 0
  sel(f2); run(:ripado, 'build', 'larg' => 7, 'vao' => 1.5, 'prof' => 2, 'sentido' => 'horizontal', 'fundo' => true, 'cor_ripa' => '#C9A27C', 'cor_fundo' => '#3E4B57', 'recuo' => 10)
  render('24-ripado', 'Ripado em pé com o vão da porta livre · ripado deitado com fundo e recuo', az: -110, el: 18)
end

scene('20-luzes') do
  wm = m.materials.add('Parede').tap { |x| x.color = Sketchup::Color.new(236, 232, 226) }
  wall = m.entities.add_face(pt(0, 300, 0), pt(400, 300, 0), pt(400, 300, 280), pt(0, 300, 280))
  wall.material = wm
  floor(pilar: false).material = m.materials.add('Piso').tap { |x| x.color = Sketchup::Color.new(210, 200, 188) }
  spots = [80, 200, 320].map { |x| component('Spot', 10, 10, 5, pt(x, 220, 255)).tap { |s| s.material = m.materials.add('Spot preto').tap { |q| q.color = Sketchup::Color.new(40, 40, 40) } } }
  sel(spots); run(:lights, 'beam', 'abertura' => 30, 'intensidade' => 25)
  run(:lights, 'wash', 'larg' => 70, 'alt' => 150)
  click_face(wall, pt(80, 300, 250))
  run(:lights, 'neon', 'texto' => 'lavi', 'letra' => 25, 'cor' => '#FF5FA2')
  click_face(wall, pt(260, 300, 170))
  fita = box(0, 297, 275, 400, 2, 2, name: 'Fita')
  sel(fita); run(:lights, 'mark', 'temp' => '3000')
  render('20-luzes', 'Fachos de luz nos spots, mancha na parede, letreiro neon e fita LED marcada', az: -100, el: 15)
end

scene('21-variar') do
  verdes = %w[4F6B3A 6B8F4E 3D5530].map { |h| m.materials.add("Verde #{h}").tap { |x| x.color = Sketchup::Color.new("##{h}") } }
  pl = (0...12).map { |k| component('Planta', 30, 30, 90, pt((k % 6) * 60, (k / 6) * 70)).tap { |x| x.material = verdes[0] } }
  sel(pl)
  run(:randomize, 'run', 'girar' => 180, 'escala' => 25, 'misturar' => false, 'seed' => 3)
  pl.each_with_index { |x, i| x.material = verdes[i % 3] }
  sel(pl); run(:randomize, 'run', 'girar' => 0, 'escala' => 0, 'misturar' => true, 'seed' => 5)
  render('21-variar', 'Variar objetos: cada cópia girada, com outro tamanho e outro tom', az: -60, el: 30)
end

scene('22-vaos-posicao') do
  run(:walls, 'draw')
  click_points([pt(0, 0), pt(400, 0), pt(400, 300), pt(0, 300)], closed: true)
  w = m.entities.grep(Sketchup::ComponentInstance).first
  face, tr = all_faces(w.definition.entities, w.transformation).select { |f, t| f.normal.transform(t).y < -0.9 }.max_by { |f, _| f.area }
  run(:openings, 'place', 'tipo' => 'janela', 'larg' => 100, 'alt' => 100, 'peit' => 110, 'posicao' => 'canto', 'lado' => 'esquerda', 'dist' => 40)
  click_face(face, pt(200, -7.5, 150), tr)
  run(:openings, 'place', 'tipo' => 'porta', 'larg' => 80, 'alt' => 210, 'peit' => 0, 'posicao' => 'canto', 'lado' => 'direita', 'dist' => 15)
  click_face(face, pt(200, -7.5, 150), tr)
  e1 = m.entities.add_dimension_linear(pt(-7.5, -7.5, 0), pt(32.5, -7.5, 0), Geom::Vector3d.new(0, -40, 0))
  e2 = m.entities.add_dimension_linear(pt(312.5, -7.5, 0), pt(407.5, -7.5, 0), Geom::Vector3d.new(0, -40, 0))
  render('22-vaos-posicao', 'Janela a 40 cm da ponta esquerda, porta a 15 cm da ponta direita', az: -90, el: 8)
end
