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

def collect(ents, tr, mat, out)
  ents.each do |e|
    next if e.respond_to?(:hidden?) && e.hidden?
    case e
    when Sketchup::Face
      loops = e.loops.map { |l| l.vertices.map { |v| v.position.transform(tr) } }
      n = e.normal.transform(tr)
      out[:faces] << [loops, n.normalize, e.material || mat, e.back_material]
    when Sketchup::ComponentInstance
      collect(e.definition.entities, tr * e.transformation, e.material || mat, out)
    when Sketchup::DimensionLinear
      out[:dims] << [e.start[1].transform(tr), e.end[1].transform(tr), e.offset_vector.transform(tr)]
    when Sketchup::Edge
      out[:edges] << [e.start.position.transform(tr), e.end.position.transform(tr)] if e.faces.empty?
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
  faces = data[:faces].map do |loops, n, mat, back|
    facing = n.dot(d) < 0
    col = color_of(facing ? mat : (back || mat))
    sh = 0.62 + 0.38 * n.dot(light).abs
    sh *= 0.85 unless facing
    { loops: loops.map { |l| l.map { |q| pr = proj.call(q); tx.call(pr) + [pr[2]] } },
      rgb: col.map { |c| [[c * sh, 255].min, 0].max.round } }
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
