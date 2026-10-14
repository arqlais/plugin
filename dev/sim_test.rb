# Testa TODAS as ferramentas num SketchUp simulado (dev/sim/su_sim.rb):
# monta um modelo de teste, seleciona como a pessoa faria, roda cada ação do painel
# com os valores padrão do formulário (dev/sim/forms.json), simula os cliques no modelo
# e confere o que foi criado. Falha se alguma ação der erro.
# Uso: ruby dev/sim_test.rb [ferramenta]   (antes: node dev/forms_dump.js > dev/sim/forms.json)

require 'json'
require 'tmpdir'
$LOAD_PATH.unshift(File.join(__dir__, 'stub')) # sketchup.rb e extensions.rb vazios
require_relative 'sim/su_sim'

ROOT_DIR = File.expand_path('..', __dir__)
PLUGINS = ROOT_DIR
OUT = Dir.mktmpdir('lavi_sim')
require File.join(ROOT_DIR, 'lavi_plugin.rb')
P = LAVIStudio::Plugin
abort("ERROS AO CARREGAR:\n#{P::LOAD_ERRORS.join("\n")}") unless P::LOAD_ERRORS.empty?
FORMS = JSON.parse(File.read(File.join(__dir__, 'sim', 'forms.json'))).map { |f| [f['id'], f] }.to_h
ONLY = ARGV[0]

# ---------------------------------------------------------------- utilidades
def m; Sketchup.active_model; end
def pt(x, y, z = 0) Geom::Point3d.new(x.cm, y.cm, z.cm) end
def sel(*e) m.selection.clear; m.selection.add(e.flatten) end

def fresh
  Sketchup.reset_model!
  UI.answers = { select_directory: OUT, savepanel: ->(*a) { File.join(OUT, a[2].to_s.empty? ? 'saida' : a[2].to_s) } }
  UI.log = []
  P::Dialog.show unless P::Dialog.instance_variable_get(:@dlg)
  $js.clear
end

# piso retangular (cm) com um pilar no meio (furo)
def floor(w = 400, d = 300, z = 0, pilar: true, ents: m.entities)
  f = ents.add_face(pt(0, 0, z), pt(w, 0, z), pt(w, d, z), pt(0, d, z))
  f.reverse! if f.normal.z < 0
  if pilar
    h = ents.add_face(pt(180, 130, z), pt(210, 130, z), pt(210, 160, z), pt(180, 160, z))
    h.erase!
  end
  f
end

# caixa (grupo) em cm
def box(x, y, z, w, d, h, name: '', ents: m.entities, mat: nil)
  g = ents.add_group
  f = g.entities.add_face(pt(x, y, z), pt(x + w, y, z), pt(x + w, y + d, z), pt(x, y + d, z))
  f.reverse! if f.normal.z > 0
  f.pushpull(-h.cm)
  g.name = name
  g.material = mat if mat
  g
end

def component(name, w, d, h, at)
  dfn = m.definitions[name] || m.definitions.add(name)
  if dfn.entities.empty?
    f = dfn.entities.add_face(pt(0, 0), pt(w, 0), pt(w, d), pt(0, d))
    f.reverse! if f.normal.z > 0
    f.pushpull(-h.cm)
  end
  m.entities.add_instance(dfn, Geom::Transformation.new(at))
end

def all_faces(ents = m.entities, tr = IDENTITY, out = [])
  ents.each do |e|
    out << [e, tr] if e.is_a?(Sketchup::Face)
    all_faces(e.definition.entities, tr * e.transformation, out) if e.is_a?(Sketchup::ComponentInstance)
  end
  out
end

def groups_named(rx) m.entities.grep(Sketchup::ComponentInstance).select { |g| g.name.to_s =~ rx } end
def kinds; m.entities.grep(Sketchup::ComponentInstance).map { |g| g.get_attribute('plane', 'kind') }.compact; end

# chamada igual à do painel (passa pelo Dialog.run e pela licença)
def run(tool, action, extra = {})
  p = (FORMS[tool.to_s] ? FORMS[tool.to_s]['defaults'] : {}).merge(extra)
  if action.start_with?('assign:')
    p['cat'] = action.split(':', 2)[1]
    action = 'assign'
  end
  $js.clear
  P::Dialog.run(JSON.generate(req: 1, tool: tool, action: action, params: p))
  line = $js.reverse.find { |j| j.start_with?('PLN.onResult(') }
  raise 'sem resposta' unless line
  JSON.parse(line[/\APLN\.onResult\((.*)\)\z/m, 1])[1]
end

# o que a ferramenta mandou depois (cliques no modelo)
def pushed
  $js.select { |j| j.start_with?('PLN.on("result"') }.map { |j| JSON.parse(j[/, (.*)\)\z/m, 1]) }
end

# simula os cliques numa ferramenta de clique ativa
def click_points(points, closed: false)
  t = m.tool
  raise "nenhuma ferramenta de clique ativa (#{t.class})" unless t.is_a?(P::Pickers::PointPicker)
  t.instance_variable_set(:@pts, points)
  t.finish(closed)
end

def click_face(face, at = nil, tr = IDENTITY)
  t = m.tool
  raise "nenhuma ferramenta de face ativa (#{t.class})" unless t.is_a?(P::Pickers::FacePicker)
  at ||= face.bounds.center
  t.instance_variable_get(:@on_pick).call(face, tr, at, [face])
end

def typed(text)
  t = m.tool
  t.onUserText(text, m.active_view)
end

# ---------------------------------------------------------------- casos
$results = []
def check(name)
  return unless __FILE__ == $PROGRAM_NAME || $RUN_CHECKS
  return if ONLY && !name.start_with?(ONLY)
  fresh
  t0 = Time.now
  info = yield
  open = m.open_ops
  raise "operação ficou aberta (#{open}) — o Ctrl+Z não fecharia" if open != 0
  $results << [name, :ok, info.to_s, Time.now - t0]
rescue StandardError, ScriptError => e
  where = e.backtrace.find { |l| l.include?('lavi_plugin') } || e.backtrace.first
  $results << [name, :falhou, "#{e.class}: #{e.message}  @ #{where.sub(ROOT_DIR + '/', '')}", Time.now - t0]
end

def ok!(r, what = '')
  raise "#{what} → #{r['msg']}" unless r['ok']
  r
end

def expect(cond, msg) raise msg unless cond end

# === Paredes
check('walls · desenhar clicando (retângulo fechado)') do
  ok!(run(:walls, 'draw'))
  click_points([pt(0, 0), pt(400, 0), pt(400, 300), pt(0, 300)], closed: true)
  r = pushed.last or raise 'não mandou resultado'
  expect(r['ok'], r['msg'])
  g = m.entities.grep(Sketchup::ComponentInstance)
  expect(g.any?, 'nenhum grupo de parede criado')
  "#{g.size} grupo(s), #{all_faces.size} faces · #{r['msg']}"
end

check('walls · medida digitada (5 = 5 m)') do
  ok!(run(:walls, 'draw', 'unid' => 'm'))
  t = m.tool
  t.add_point(pt(0, 0))
  t.instance_variable_get(:@ip).instance_variable_set(:@position, pt(100, 0))
  typed('5')
  typed('3,5')
  pts = t.instance_variable_get(:@pts)
  expect(pts.size == 3, "esperava 3 pontos, veio #{pts.size}")
  d1 = (pts[1].distance(pts[0]) * 2.54).round(1)
  d2 = (pts[2].distance(pts[1]) * 2.54).round(1)
  expect(d1 == 500.0 && d2 == 350.0, "medidas #{d1} e #{d2} cm")
  typed('80mm')
  d3 = (t.instance_variable_get(:@pts)[3].distance(pts[2]) * 2.54).round(1)
  expect(d3 == 8.0, "80mm virou #{d3} cm")
  t.finish(false)
  "5 → #{d1} cm, 3,5 → #{d2} cm, 80mm → #{d3} cm"
end

check('walls · a partir de linhas selecionadas') do
  es = m.entities.add_edges(pt(0, 0), pt(500, 0), pt(500, 400), pt(0, 400), pt(0, 0))
  sel(es)
  r = ok!(run(:walls, 'from_edges'))
  r['msg']
end

# === Portas e janelas
check('openings · porta e janela na parede') do
  ok!(run(:walls, 'draw'))
  click_points([pt(0, 0), pt(400, 0), pt(400, 300), pt(0, 300)], closed: true)
  wall = m.entities.grep(Sketchup::ComponentInstance).first
  faces = all_faces(wall.definition.entities, wall.transformation).select { |f, tr| f.normal.transform(tr).y.abs > 0.9 }
  face, tr = faces.max_by { |f, tr| f.area }
  expect(face, 'não achei face da parede')
  msgs = []
  area0 = face.area
  { 'porta' => { 'larg' => 80, 'alt' => 210, 'peit' => 0 }, 'janela' => { 'larg' => 120, 'alt' => 120, 'peit' => 110 } }.each do |tipo, med|
    ok!(run(:openings, 'place', med.merge('tipo' => tipo, 'posicao' => 'clique')))
    c = face.bounds.center.transform(tr)
    c = Geom::Point3d.new(c.x + (tipo == 'porta' ? -80.cm : 80.cm), c.y, 0)
    click_face(face, c, tr)
    r = pushed.last or raise 'sem resultado'
    expect(r['ok'], "#{tipo}: #{r['msg']}")
    msgs << "#{tipo}: #{r['msg']}"
  end
  furos = all_faces(wall.definition.entities).count { |f, _| f.loops.size > 1 }
  vaos = wall.definition.entities.grep(Sketchup::ComponentInstance).count { |g| %w[Porta Janela].include?(g.name) }
  expect(vaos == 2, "esperava porta e janela, veio #{vaos}")
  expect(msgs.all? { |x| x.include?('parede de 15,0 cm') }, 'espessura da parede errada')
  msgs << "#{furos} face(s) com furo, #{vaos} folha(s)/vidro(s)"
  msgs.join(' | ')
end

# === DWG → paredes
check('dwg_walls · analisar e levantar') do
  # ambiente 400×300 com paredes de 15 cm (linhas de dentro e de fora) e uma porta de 80 cm
  out = [pt(-15, -15), pt(415, -15), pt(415, 315), pt(-15, 315)]
  inn = [pt(0, 0), pt(400, 0), pt(400, 300), pt(0, 300)]
  es = []
  4.times { |i| es << m.entities.add_line(out[i], out[(i + 1) % 4]) }
  es << m.entities.add_line(inn[0], pt(160, 0)) << m.entities.add_line(pt(240, 0), inn[1])
  es << m.entities.add_line(inn[1], inn[2]) << m.entities.add_line(inn[2], inn[3]) << m.entities.add_line(inn[3], inn[0])
  sel(es)
  a = ok!(run(:dwg_walls, 'analyze'), 'analisar')
  b = ok!(run(:dwg_walls, 'build'), 'levantar')
  expect(m.entities.grep(Sketchup::ComponentInstance).any?, 'nada criado')
  "#{a['stats'].map { |s| s[0] + ' ' + s[1] }.join(', ')} · #{b['msg']}"
end

# === Escada
check('stairs · calcular e colocar (maciça e flutuante)') do
  c = ok!(run(:stairs, 'calc'))
  %w[macica flutuante].each do |tipo|
    ok!(run(:stairs, 'place', 'tipo' => tipo))
    click_points([pt(0, 0), pt(0, 100)])
  end
  esc = m.entities.grep(Sketchup::ComponentInstance)
  expect(esc.size == 2, 'escadas não criadas')
  topo = all_faces(esc[0].definition.entities, esc[0].transformation).select { |f, tr| f.normal.transform(tr).z > 0.99 }
  zs = topo.map { |f, tr| (f.bounds.max.transform(tr).z * 2.54).round(1) }.uniq.sort
  expect(zs.include?(262.5) || zs.include?(280.0), "degraus nas alturas #{zs.last(3).inspect}")
  expect(zs.size >= 15, "só #{zs.size} níveis de degrau")
  "#{c['stats'][0, 3].map { |s| s.join(' ') }.join(', ')} · #{m.entities.grep(Sketchup::ComponentInstance).size} escada(s)"
end

# === Telhado
check('roofs · 1, 2 e 4 águas') do
  out = []
  %w[1agua 2aguas 4aguas].each_with_index do |tipo, i|
    f = m.entities.add_face(pt(i * 1000, 0, 280), pt(i * 1000 + 800, 0, 280), pt(i * 1000 + 800, 600, 280), pt(i * 1000, 600, 280))
    sel(f)
    r = ok!(run(:roofs, 'build', 'tipo' => tipo, 'aguas' => tipo), tipo)
    g = m.entities.grep(Sketchup::ComponentInstance).last
    incl = all_faces(g.definition.entities, g.transformation).count { |f, tr| n = f.normal.transform(tr).normalize; n.z.abs > 0.05 && n.z.abs < 0.98 }
    expect(incl >= (tipo == '4aguas' ? 4 : tipo == '2aguas' ? 2 : 1), "#{tipo}: só #{incl} água(s) inclinada(s)")
    out << "#{tipo}: #{incl} face(s) inclinada(s)"
  end
  out.join(' | ')
end

# === Índices urbanísticos
check('tiling · todos os padrões no piso com pilar') do
  f = floor
  sel(f)
  s = ok!(run(:tiling, 'surface'))
  expect(s['surface']['faces'] == 1, 'superfície não reconhecida')
  out = []
  %w[horizontal vertical diagonal tijolo damas chevron espinha organica].each do |pat|
    e = ok!(run(:tiling, 'estimate', 'padrao' => pat, 'pc' => 60, 'pl' => 20), "estimar #{pat}")
    expect(e['est'] && e['est'].size >= 4, "#{pat}: sem estimativa")
    out << "#{pat} #{e['est'][3][1]}"
  end
  sel(f)
  b = ok!(run(:tiling, 'build', 'padrao' => 'espinha', 'pc' => 60, 'pl' => 15), 'gerar')
  g = groups_named(/Paginação/)
  expect(g.size == 1, 'grupo da paginação não criado')
  pieces = g[0].definition.entities.grep(Sketchup::Face).size
  base = g[0].definition.entities.grep(Sketchup::ComponentInstance).first
  holes = base ? base.definition.entities.grep(Sketchup::Face).map { |x| x.loops.size - 1 }.max : 0
  expect(holes.to_i >= 1, 'o rejunte não ficou com o furo do pilar')
  "#{out.join(', ')} · gerou #{pieces} peças, rejunte com furo do pilar"
end

check('tiling · editar paginação existente') do
  f = floor
  sel(f)
  ok!(run(:tiling, 'build', 'padrao' => 'horizontal'))
  g = groups_named(/Paginação/)[0]
  sel(g)
  e = ok!(run(:tiling, 'edit'))
  expect(e['values']['padrao'] == 'horizontal', 'não carregou as opções')
  sel(g)
  ok!(run(:tiling, 'build', 'padrao' => 'chevron', 'pc' => 60, 'pl' => 15))
  gs = groups_named(/Paginação/)
  expect(gs.size == 1, "ficaram #{gs.size} paginações (devia substituir)")
  expect(JSON.parse(gs[0].get_attribute('plane', 'params'))['padrao'] == 'chevron', 'não atualizou')
  'trocou horizontal → chevron no mesmo lugar'
end

check('tiling · parede, peças 3D, texturas, junta seca') do
  wall = m.entities.add_face(pt(0, 0, 0), pt(300, 0, 0), pt(300, 0, 260), pt(0, 0, 260))
  sel(wall)
  imgs = (1..3).map { |i| File.join(OUT, "madeira#{i}.jpg").tap { |f| File.write(f, 'jpg') } }
  UI.answers[:openpanel] = imgs[0]
  a = ok!(run(:tiling, 'add_image'))
  expect(a['values']['texturas'] == [imgs[0].tr('\\', '/')], 'imagem não entrou')
  r = ok!(run(:tiling, 'build', 'padrao' => 'tijolo', 'pc' => 30, 'pl' => 7.5, 'relevo' => true, 'texturas' => imgs))
  g = groups_named(/Paginação de parede/)[0] or raise 'paginação de parede não criada'
  fs = g.definition.entities.grep(Sketchup::Face)
  textured = fs.count { |x| x.material && x.material.texture }
  mapped = fs.count(&:uv_data)
  expect(textured > 0 && mapped > 0, 'as imagens não foram aplicadas nas peças')
  usados = fs.map(&:material).compact.map(&:name).uniq.size
  expect(usados >= 3, "sorteio usou só #{usados} imagem(ns)")
  wall2 = m.entities.add_face(pt(0, 500, 0), pt(300, 500, 0), pt(300, 500, 260), pt(0, 500, 260))
  sel(wall2)
  ok!(run(:tiling, 'build', 'seca' => true, 'mostrar_rej' => false))
  "#{fs.size} faces (peças 3D), #{usados} imagens sorteadas · junta seca ok"
end

check('tiling · pedra São Tomé rústica, relevo e chanfrado') do
  out = []
  %w[relevo chanfrado rustico].each do |acab|
    fresh
    f = floor(pilar: false)
    sel(f)
    ok!(run(:tiling, 'build', 'padrao' => 'organica', 'pc' => 40, 'pl' => 30, 'rej' => 10, 'acabamento' => acab, 'var' => 6, 'chanfro' => 4, 'esp' => 15))
    g = groups_named(/Paginação/)[0]
    fs = g.definition.entities.grep(Sketchup::Face)
    tops = fs.select { |x| x.normal.z > 0.9 }
    alturas = tops.map { |x| (x.bounds.max.z * 25.4).round(1) }.uniq
    inclinadas = tops.count { |x| x.normal.z < 0.99999 }
    expect(alturas.size > (acab == 'chanfrado' ? 0 : 5), "#{acab}: alturas não variam (#{alturas.size})")
    expect(acab != 'rustico' || inclinadas > 5, 'rústico sem inclinação')
    out << "#{acab}: #{tops.size} pedras, #{alturas.size} alturas"
  end
  out.join(' · ')
end

check('tiling · ponto inicial, giro e escolher face clicando') do
  f = floor(pilar: false)
  ok!(run(:tiling, 'pick'))
  click_face(f)
  r = pushed.last
  expect(r && r['surface'] && r['surface']['faces'] == 1, 'face clicada não ficou escolhida')
  ok!(run(:tiling, 'origin'))
  click_points([pt(30, 30)])
  v = pushed.last['values']
  expect(v['inicio'] == 'ponto', 'ponto inicial não voltou')
  ok!(run(:tiling, 'rotate'))
  click_points([pt(0, 0), pt(100, 100)])
  ang = pushed.last['values']['ang']
  expect((ang - 45).abs < 0.5, "giro deu #{ang}°")
  sel(f)
  ok!(run(:tiling, 'build', v.merge('ang' => ang)))
  "ponto (#{(v['ox'] * 2.54).round}, #{(v['oy'] * 2.54).round}) cm, giro #{ang}°"
end

# === Rodapé, forro
check('baseboard · todos os modelos, com pilar e porta pulada') do
  out = []
  %w[reto chanfrado boleado frisado classico filete].each do |mod|
    fresh
    f = floor
    sel(f)
    r = ok!(run(:baseboard, 'build', 'modelo' => mod, 'alt' => 10, 'esp' => 2))
    g = m.entities.grep(Sketchup::ComponentInstance).last
    h = (g.bounds.depth * 2.54).round(1)
    expect(h == 10.0, "#{mod}: altura #{h} cm")
    expect(r['stats'][0][1] == '15,20 m', "#{mod}: comprimento #{r['stats'][0][1]}")
    out << mod
  end
  fresh
  f = floor(pilar: false)
  porta = f.edges.find { |e| e.start.position.y.abs < 0.01 && e.end.position.y.abs < 0.01 }
  sel(f, porta)
  r = ok!(run(:baseboard, 'build'))
  expect(r['stats'][0][1] == '10,00 m', "com porta pulada: #{r['stats'][0][1]}")
  "#{out.join(', ')} (10 cm, 15,20 m) · pulando a porta: 10,00 m"
end

check('ceiling · rebaixado com tabica, cortineiro, sanca e moldura') do
  f = floor(pilar: false)
  sel(f)
  a = ok!(run(:ceiling, 'build'))
  g = m.entities.grep(Sketchup::ComponentInstance).last
  fz = g.bounds
  expect(((fz.min.z * 2.54) - 260).abs < 0.1, "forro em #{(fz.min.z * 2.54).round(1)} cm (esperava 260)")
  slab = g.definition.entities.grep(Sketchup::ComponentInstance).find { |x| x.name.to_s.empty? && x.bounds.depth < 2.cm }
  expect(slab && (slab.bounds.min.x * 2.54 - 3).abs < 0.05, "forro não recuou 3 cm da parede (#{slab && (slab.bounds.min.x * 2.54).round(2)})")
  expect(g.definition.entities.grep(Sketchup::ComponentInstance).any? { |x| x.name == 'Tabica' }, 'sem tabica')
  janela = f.edges.find { |e| e.start.position.y.abs < 0.01 && e.end.position.y.abs < 0.01 }
  sel(f, janela)
  b = ok!(run(:ceiling, 'build', 'cortineiro' => true, 'cort_larg' => 15))
  g2 = m.entities.grep(Sketchup::ComponentInstance).last
  slab2 = g2.definition.entities.grep(Sketchup::ComponentInstance).find { |x| x.name.to_s.empty? && x.bounds.depth < 2.cm }
  expect((slab2.bounds.min.y * 2.54 - 15).abs < 0.05, "cortineiro não recuou 15 cm (#{(slab2.bounds.min.y * 2.54).round(2)})")
  expect((slab2.bounds.min.x * 2.54 - 3).abs < 0.05, 'tabica dos outros lados sumiu')
  sel(f); ok!(run(:ceiling, 'build', 'tipo' => 'sanca', 'sanca_tipo' => 'aberta'))
  out = []
  %w[reta chanfro cove degrau classica].each do |mod|
    sel(f)
    r = ok!(run(:ceiling, 'build', 'tipo' => 'moldura', 'mold_modelo' => mod, 'mold_tam' => 8))
    out << "#{mod} #{r['stats'].find { |x| x[0] == 'Moldura' }[1]}"
  end
  "#{a['stats'].map { |x| x.join(' ') }.join(', ')} · cortineiro: #{b['stats'].last.join(' ')} · molduras: #{out.join(', ')}"
end

# === Marcenaria
check('cut_list · lista, plano de corte e CSV') do
  ent = box(0, 0, 0, 80, 55, 1.8, name: 'Base')
  box(0, 0, 70, 80, 55, 1.8, name: 'Tampo')
  box(0, 0, 1.8, 1.8, 55, 68.2, name: 'Lateral')
  box(78.2, 0, 1.8, 1.8, 55, 68.2, name: 'Lateral')
  r = ok!(run(:cut_list, 'list'))
  c = ok!(run(:cut_list, 'csv'))
  "#{r['stats'].map { |s| s.join(' ') }.join(', ')} · #{c['msg']}"
end

check('countertop · recorte por medida') do
  tampo = box(0, 0, 90, 120, 60, 2, name: 'Tampo')
  sel(tampo)
  r = ok!(run(:countertop, 'run', 'modo' => 'medida'))
  r['msg']
end

check('countertop · recorte automático no formato do bloco ao colocar') do
  tampo = box(0, 0, 88, 200, 60, 3, name: 'Tampo')
  dfn = m.definitions.add('Cuba inox 50x40')
  f = dfn.entities.add_face(pt(0, 0), pt(50, 0), pt(50, 40), pt(0, 40))
  f.reverse! if f.normal.z > 0
  f.pushpull(-20.cm)
  $timers = []
  m.entities.add_instance(dfn, Geom::Transformation.new(pt(30, 10, 72))) # borda 1 cm acima do tampo
  $timers.each(&:call)
  top = tampo.definition.entities.grep(Sketchup::Face).find { |x| x.normal.z > 0.99 }
  expect(top.loops.size == 2, "tampo sem furo depois de colocar a cuba (#{top.loops.size - 1} furos)")
  furo = top.loops[1].vertices.map { |v| v.position }
  w = ((furo.map(&:x).max - furo.map(&:x).min) * 2.54).round(1)
  d = ((furo.map(&:y).max - furo.map(&:y).min) * 2.54).round(1)
  expect([w, d] == [50.0, 40.0], "furo de #{w} × #{d} (esperava 50 × 40)")
  bottom = tampo.definition.entities.grep(Sketchup::Face).find { |x| x.normal.z < -0.99 }
  expect(bottom.loops.size == 2, 'o furo não atravessou o tampo')
  # outra cuba, desta vez recortada pelo botão (com folga)
  c2 = m.definitions.add('Lavatório oval')
  f2 = c2.entities.add_face(pt(0, 0), pt(40, 0), pt(40, 30), pt(0, 30))
  f2.reverse! if f2.normal.z > 0
  f2.pushpull(-15.cm)
  ok!(run(:countertop, 'auto', 'auto' => false))
  i2 = m.entities.add_instance(c2, Geom::Transformation.new(pt(130, 15, 76)))
  $timers.each(&:call)
  expect(top.loops.size == 2, 'recortou com o automático desligado')
  sel(i2)
  r = ok!(run(:countertop, 'run', 'folga' => 1))
  expect(top.loops.size == 3, 'o botão não recortou a segunda cuba')
  ok!(run(:countertop, 'auto', 'auto' => true))
  "automático: #{w} × #{d} cm atravessando · botão com folga: #{r['stats'][1][1]}"
end

# === Apresentação
check('scenes · cenas automáticas') do
  floor(pilar: false)
  box(0, 0, 0, 400, 15, 280, name: 'Parede')
  box(0, 285, 0, 400, 15, 280, name: 'Parede')
  box(0, 0, 280, 400, 300, 10, name: 'Laje')
  r = ok!(run(:scenes, 'create'))
  n = m.pages.size
  expect(n >= 8, "só #{n} cenas")
  r2 = ok!(run(:scenes, 'create'))
  expect(m.pages.size == n, 'rodar de novo duplicou as cenas')
  pl = m.pages[0]
  expect(pl.camera.direction.z < -0.99, 'planta não está vista de cima')
  expect(pl.section_on, 'planta sem plano de corte')
  "#{n} cenas: #{m.pages.map(&:name).join(', ')}"
end

check('export_images · formatos, moldura e câmera') do
  floor(pilar: false)
  m.pages.add('Planta'); m.pages.add('Fachada')
  r = ok!(run(:export_images, 'export', 'proporcao' => '4:5', 'largura' => 1080))
  imgs = m.active_view.images
  expect(imgs.size == 2, "exportou #{imgs.size} imagens")
  expect(imgs[0][:height] == 1350, "altura #{imgs[0][:height]} (esperava 1350)")
  g = ok!(run(:export_images, 'guide', 'guia' => true, 'proporcao' => '9:16'))
  ov = m.overlays.first
  expect(ov && ov.enabled?, 'moldura não ligou')
  ov.draw(m.active_view)
  c = ok!(run(:export_images, 'camera', 'cam_vista' => 'frente', 'cam_alt' => 150, 'cam_fov' => 40, 'cam_cena' => true))
  cam = m.active_view.camera
  expect((cam.eye.z * 2.54 - 150).abs < 0.1 && (cam.fov - 40).abs < 0.01, 'câmera não aplicada')
  expect((cam.target.z - cam.eye.z).abs < 1e-6, 'não ficou em 2 pontos')
  "#{imgs.size} imagens 1080×1350 · moldura 9:16 · câmera a 150 cm, 40°"
end

check('room_tags · etiquetar ambiente, atualizar, lista e CSV') do
  f = floor(pilar: false)
  UI.answers[:inputbox] = [['Sala de estar']]
  UI.answers[:inputbox] = ->(*_a) { ['Sala de estar'] }
  %w[3d tela].each do |estilo|
    ok!(run(:room_tags, 'place', 'estilo' => estilo))
    click_face(f)
    r = pushed.last or raise 'sem resultado'
    expect(r['ok'], "#{estilo}: #{r['msg']}")
  end
  u = ok!(run(:room_tags, 'update'))
  l = ok!(run(:room_tags, 'list'))
  ok!(run(:room_tags, 'csv'))
  "#{u['msg']} · #{l['msg']}"
end

# === Quantitativo
check('furniture · ficha, relatório, CSV e caderno') do
  floor(pilar: false)
  a = component('Sofá 3 lugares', 220, 90, 80, pt(50, 50))
  b = component('Mesa de centro', 80, 80, 40, pt(150, 160))
  sel(a)
  ok!(run(:takeoff, 'apply', 'nome' => 'Sofá Bia', 'fornecedor' => 'Loja X', 'preco' => 4500, 'qtd' => 1))
  sel(a)
  rd = ok!(run(:takeoff, 'read'))
  sel(a, b)
  rp = ok!(run(:takeoff, 'report'))
  ok!(run(:takeoff, 'moveis_csv'))
  ok!(run(:takeoff, 'sheet'))
  "#{rp['msg']}"
end

check('takeoff · quantitativo depois de paginar e rodapé') do
  f = floor
  sel(f); ok!(run(:tiling, 'build'))
  sel(f); ok!(run(:baseboard, 'build'))
  box(0, 0, 0, 400, 15, 280, name: 'Parede')
  m.selection.clear
  r = ok!(run(:takeoff, 'run'))
  ok!(run(:takeoff, 'csv'))
  r['stats'].map { |s| s.join(' ') }.join(', ')
end

# === Essenciais
check('model_health · examinar e corrigir') do
  floor
  m.entities.add_line(pt(900, 0), pt(950, 0)) # aresta solta
  m.materials.add('Sem uso')
  m.layers.add('Etiqueta vazia')
  g = box(0, 0, 0, 10, 10, 10)
  box(0, 0, 0, 5, 5, 5, ents: g.entities)
  s = ok!(run(:model_health, 'scan'))
  ok!(run(:model_health, 'fix'))
  "nota #{s['score']} · #{s['msg']}"
end

check('align · alinhar e distribuir') do
  gs = [box(0, 0, 0, 50, 50, 50), box(100, 30, 0, 50, 50, 70), box(300, 10, 0, 50, 50, 30)]
  out = []
  %w[min centro max distribuir].each do |modo|
    sel(gs)
    out << "#{modo}: #{ok!(run(:align, 'run', 'modo' => modo, 'eixo' => 'y'))['msg']}"
  end
  out.join(' | ')
end

check('replace · listar, selecionar iguais e substituir') do
  a1 = component('Cadeira A', 45, 50, 90, pt(0, 0))
  a2 = component('Cadeira A', 45, 50, 90, pt(100, 0))
  component('Cadeira B', 50, 55, 85, pt(0, 200))
  l = ok!(run(:smart_select, 'list'))
  sel(a1)
  ok!(run(:smart_select, 'select_same'))
  expect(m.selection.size == 2, "selecionou #{m.selection.size}")
  r = ok!(run(:smart_select, 'replace', 'def' => 'Cadeira B'))
  expect(m.entities.grep(Sketchup::ComponentInstance).count { |i| i.definition.name == 'Cadeira B' } == 3, 'não substituiu')
  "#{l['defs'].size} componentes · #{r['msg']}"
end

check('measure · medir seleção') do
  f = floor
  g = box(0, 0, 0, 100, 50, 80)
  e = m.entities.add_line(pt(0, 0, 300), pt(250, 0, 300))
  sel(f, g, e)
  r = ok!(run(:measure, 'run'))
  r['stats'].map { |s| s.join(' ') }.join(', ')
end

check('isolate · isolar, raio-x e mostrar tudo') do
  a = box(0, 0, 0, 50, 50, 50)
  b = box(100, 0, 0, 50, 50, 50)
  sel(a)
  ok!(run(:isolate, 'isolate'))
  expect(b.hidden?, 'não escondeu o resto')
  ok!(run(:isolate, 'restore'))
  expect(!b.hidden?, 'não mostrou tudo de novo')
  sel(a)
  ok!(run(:isolate, 'xray'))
  'isolou e restaurou'
end

check('auto_tags · organizar e listar') do
  component('Cadeira Eames', 45, 50, 80, pt(0, 0))
  component('Planta costela-de-adão', 40, 40, 120, pt(100, 0))
  component('Luminária pendente', 30, 30, 40, pt(200, 0, 250))
  f = floor; sel(f); run(:tiling, 'build')
  r = ok!(run(:auto_tags, 'organize'))
  l = ok!(run(:auto_tags, 'list'))
  tag = (l['tags'] || [])[0]
  ok!(run(:auto_tags, 'toggle', 'tag' => tag[0])) if tag
  "#{r['msg']}"
end

# === Ferramentas novas (v0.9)
check('dwg_clean · achatar, tirar anotações, sujeira e fechar faces') do
  g = m.entities.add_group
  e = g.entities
  e.add_line(pt(0, 0, 0), pt(400, 0, 5)); e.add_line(pt(400, 0, 5), pt(400, 300, 0))
  e.add_line(pt(400, 300, 0), pt(0, 300, 3)); e.add_line(pt(0, 300, 3), pt(0, 0, 0))
  e.add_line(pt(900, 0, 0), pt(900, 0.05, 0))
  e.add_text('SALA', pt(200, 150))
  e.add_dimension_linear(pt(0, 0), pt(400, 0), Geom::Vector3d.new(0, -20, 0))
  sel(g)
  r = ok!(run(:dwg_walls, 'clean'))
  st = r['stats'].map { |a, b| [a, b.to_i] }.to_h
  expect(st['Anotações removidas'] == 2, "anotações #{st['Anotações removidas']}")
  expect(st['Linhas minúsculas'] == 1, "linhas minúsculas #{st['Linhas minúsculas']}")
  expect(st['Faces criadas'] >= 1, 'não fechou a face')
  zs = g.definition.entities.grep(Sketchup::Edge).flat_map { |x| x.vertices.map { |v| v.position.z.round(4) } }.uniq
  expect(zs == [0.0], "ainda há alturas diferentes: #{zs.inspect}")
  r['stats'].map { |a, b| "#{a} #{b}" }.join(', ')
end

check('dwg_clean · fechar aberturas e marcar o que ficou aberto') do
  # retângulo com 1 cm de abertura num canto e uma linha solta a 30 cm (longe demais)
  es = m.entities.add_edges(pt(1, 0), pt(400, 0), pt(400, 300), pt(0, 300), pt(0, 0.5))
  m.entities.add_line(pt(600, 0), pt(600, 100))
  m.entities.add_edges(pt(150, 300), pt(150, 180), pt(400, 180)) # parede interna encostando em T
  sel(es + m.entities.grep(Sketchup::Edge))
  r = ok!(run(:dwg_walls, 'clean', 'tol' => 2))
  st = r['stats'].map { |a, b| [a, b.to_i] }.to_h
  expect(st['Aberturas fechadas'] >= 1, 'não fechou a abertura de 1 cm')
  expect(m.entities.grep(Sketchup::Face).size >= 2, "encontro em T não fechou os dois ambientes (#{m.entities.grep(Sketchup::Face).size} faces)")
  expect(st['Pontas ainda abertas'] == 2, "pontas abertas #{st['Pontas ainda abertas']}")
  expect(m.entities.grep(Sketchup::ConstructionPoint).size == 2, 'não marcou as pontas abertas')
  g = ok!(run(:dwg_walls, 'gaps'))
  "#{r['msg'][0, 60]}… · mostrar: #{g['msg'][0, 40]}"
end

check('dims · cotas de paredes (fora, dentro, totais) e de piso') do
  ok!(run(:walls, 'draw'))
  click_points([pt(0, 0), pt(400, 0), pt(400, 300), pt(0, 300)], closed: true)
  w = m.entities.grep(Sketchup::ComponentInstance).first
  sel(w)
  r = ok!(run(:dims, 'build'))
  ds = m.entities.grep(Sketchup::Dimension)
  expect(ds.size == 8, "esperava 8 cotas (4 fora, 4 dentro; total repetiria a de fora), veio #{ds.size}")
  c = w.bounds.center
  fora = ds.first(4).all? { |d| mid = Geom.linear_combination(0.5, d.start[1], 0.5, d.end[1]); d.offset_vector.dot(mid - c) > 0 }
  expect(fora, 'cota externa apontando para dentro')
  lens = ds.map { |d| (d.length * 2.54).round }.sort
  expect(lens.include?(385) && lens.include?(285), "faltam as medidas internas: #{lens.inspect}")
  ok!(run(:dims, 'clear'))
  expect(m.entities.grep(Sketchup::Dimension).empty?, 'não apagou as cotas')
  f = floor
  sel(f)
  ok!(run(:dims, 'build', 'internas' => false))
  # ambiente em L: aí a cota total é útil
  ok!(run(:dims, 'clear'))
  l = m.entities.add_face(pt(0, 0, 0), pt(600, 0, 0), pt(600, 200, 0), pt(300, 200, 0), pt(300, 500, 0), pt(0, 500, 0))
  sel(l)
  ok!(run(:dims, 'build'))
  nl = m.entities.grep(Sketchup::Dimension).size
  "paredes: #{lens.uniq.join(' / ')} cm · piso em L: #{nl} cotas"
end

check('array · luminárias no forro e cadeiras no caminho') do
  forro = m.entities.add_face(pt(0, 0, 260), pt(400, 0, 260), pt(400, 300, 260), pt(0, 300, 260))
  forro.reverse! if forro.normal.z > 0
  lum = component('Spot', 10, 10, 8, pt(20, 20, 252))
  sel(lum, forro)
  r = ok!(run(:array, 'build', 'modo' => 'grade', 'esp_x' => 120, 'esp_y' => 120, 'margem' => 60))
  spots = m.entities.grep(Sketchup::ComponentInstance).select { |i| i.definition.name == 'Spot' }
  expect(spots.size == 7, "esperava 6 cópias + original, veio #{spots.size}")
  tops = spots.drop(1).map { |i| (i.bounds.max.z * 2.54).round(1) }.uniq
  expect(tops == [260.0], "spots fora do forro: #{tops.inspect}")
  cad = component('Cadeira', 45, 50, 90, pt(0, 0))
  es = m.entities.add_edges(pt(0, 400), pt(300, 400), pt(300, 600))
  sel(cad, es)
  r2 = ok!(run(:array, 'build', 'modo' => 'caminho', 'espac' => 100))
  cads = m.entities.grep(Sketchup::ComponentInstance).select { |i| i.definition.name == 'Cadeira' }
  expect(cads.size == 7, "esperava 6 cadeiras + original, veio #{cads.size}")
  sel(cad, es)
  ok!(run(:array, 'build', 'modo' => 'caminho', 'por' => 'quantidade', 'qtd' => 4, 'apagar' => true))
  "#{r['msg']} · #{r2['msg']}"
end

check('fix_faces · caixa do avesso e piso de costas pintado') do
  g = box(0, 0, 0, 100, 100, 100)
  g.definition.entities.grep(Sketchup::Face).each(&:reverse!)
  f = m.entities.add_face(pt(200, 0), pt(400, 0), pt(400, 200), pt(200, 200))
  f.reverse! if f.normal.z > 0
  f.back_material = m.materials.add('Porcelanato')
  m.selection.clear
  r = ok!(run(:fix_faces, 'fix'))
  fs = g.definition.entities.grep(Sketchup::Face)
  vol = fs.sum { |x| q = x.vertices[0].position; n = x.normal; x.area * (q.x * n.x + q.y * n.y + q.z * n.z) }
  expect(vol > 0, 'a caixa continuou do avesso')
  expect(f.normal.z > 0, 'o piso continuou de costas')
  expect(f.material && f.material.name == 'Porcelanato', 'a pintura não passou para a frente')
  r['stats'].map { |a, b| "#{a} #{b}" }.join(', ')
end

check('smart_select · material, etiqueta, componente, inverter, soltas') do
  mat = m.materials.add('Madeira')
  a = box(0, 0, 0, 50, 50, 50, mat: mat); b = box(100, 0, 0, 50, 50, 50, mat: mat); box(200, 0, 0, 50, 50, 50)
  c1 = component('Vaso', 30, 30, 40, pt(0, 200)); component('Vaso', 30, 30, 40, pt(100, 200))
  m.entities.add_line(pt(0, 500), pt(100, 500))
  out = []
  sel(a); ok!(run(:smart_select, 'material')); out << "material #{m.selection.size}"
  expect(m.selection.size == 2, 'material errado')
  sel(c1); ok!(run(:smart_select, 'componente')); out << "componente #{m.selection.size}"
  expect(m.selection.size == 2, 'componente errado')
  sel(a); ok!(run(:smart_select, 'etiqueta')); out << "etiqueta #{m.selection.size}"
  sel(a); ok!(run(:smart_select, 'inverter')); out << "inverter #{m.selection.size}"
  ok!(run(:smart_select, 'soltas')); out << "soltas #{m.selection.size}"
  expect(m.selection.size == 1, 'linha solta não achada')
  out.join(', ')
end

# === v0.11: posição dos vãos, guarda-corpo, arredondar/curvar e render
check('openings · distância da ponta, de um ponto e digitada') do
  ok!(run(:walls, 'draw'))
  click_points([pt(0, 0), pt(400, 0), pt(400, 300), pt(0, 300)], closed: true)
  wall = m.entities.grep(Sketchup::ComponentInstance).first
  face, tr = all_faces(wall.definition.entities, wall.transformation).select { |f, t| f.normal.transform(t).y < -0.9 }.max_by { |f, _| f.area }
  holes = lambda do
    fs = all_faces(wall.definition.entities).select { |f, _| f.normal.y < -0.9 && f.vertices.map { |v| v.position.y }.max < -1.cm }
    fs.flat_map { |f, _| f.loops.reject(&:outer?) }.map { |l| xs = l.vertices.map { |v| (v.position.x * 2.54).round(1) }; [xs.min, xs.max] }.sort
  end
  ok!(run(:openings, 'place', 'tipo' => 'janela', 'larg' => 80, 'alt' => 100, 'peit' => 100, 'posicao' => 'canto', 'lado' => 'esquerda', 'dist' => 60))
  click_face(face, pt(200, -7.5, 150), tr)
  r1 = pushed.last
  expect(r1['ok'], r1['msg'])
  expect(holes.call.include?([52.5, 132.5]), "janela fora do lugar: #{holes.call.inspect} (esperava 52,5–132,5: 60 cm da ponta esquerda)")
  ok!(run(:openings, 'place', 'tipo' => 'janela', 'larg' => 80, 'alt' => 100, 'peit' => 100, 'posicao' => 'canto', 'lado' => 'direita', 'dist' => 60))
  click_face(face, pt(200, -7.5, 150), tr)
  expect(holes.call.include?([267.5, 347.5]), "da direita: #{holes.call.inspect}")
  ok!(run(:openings, 'place', 'tipo' => 'porta', 'larg' => 70, 'alt' => 210, 'peit' => 0, 'posicao' => 'ponto', 'lado' => 'direita', 'dist' => 10))
  m.tool.onUserText('5', m.active_view) # digitou 5 cm no campo de medidas
  click_face(face, pt(140, -7.5, 100), tr)
  expect(holes.call.include?([145.0, 215.0]), "de um ponto com distância digitada: #{holes.call.inspect}")
  "esquerda 60 cm → 52,5–132,5 · direita 60 cm → 267,5–347,5 · ponto + 5 cm digitado → 145–215"
end

check('stairs · guarda-corpo de vidro, montantes, cabos, mureta, corrimão') do
  out = []
  %w[corrimao vidro montantes cabos mureta].each_with_index do |g, i|
    ok!(run(:stairs, 'place', 'guarda' => g, 'lados' => i.even? ? 'ambos' : 'direito'))
    click_points([pt(i * 200, 0), pt(i * 200, 100)])
    esc = m.entities.grep(Sketchup::ComponentInstance).last
    gcs = esc.definition.entities.grep(Sketchup::ComponentInstance).select { |x| x.name.start_with?('Guarda-corpo') }
    expect(gcs.size == (i.even? ? 2 : 1), "#{g}: #{gcs.size} guarda-corpo(s)")
    out << "#{g} #{gcs.size} lado(s)"
  end
  vid = m.materials['lavi_Vidro']
  expect(vid && vid.alpha < 1, 'vidro sem transparência')
  out.join(', ')
end

check('stairs · em L, em U e caracol, com guarda-corpo') do
  fresh
  out = []
  [['L', 'esquerda'], ['L', 'direita'], ['U', 'esquerda'], ['caracol', 'esquerda']].each_with_index do |(forma, giro), i|
    ok!(run(:stairs, 'place', 'forma' => forma, 'giro' => giro, 'alt' => 280, 'larg' => 90, 'guarda' => 'vidro', 'lados' => 'ambos', 'tipo' => i.odd? ? 'flutuante' : 'macica'))
    click_points([pt(i * 600, 0), pt(i * 600 + 100, 0)])
    esc = m.entities.grep(Sketchup::ComponentInstance).last
    bb = esc.bounds
    w = ((bb.max.x - bb.min.x) * 2.54).round
    d = ((bb.max.y - bb.min.y) * 2.54).round
    top = (bb.max.z * 2.54).round
    tops = []
    stack = [[esc.definition.entities, esc.transformation]]
    until stack.empty?
      ents, tr = stack.pop
      ents.each do |e|
        if e.is_a?(Sketchup::Face) && e.normal.transform(tr).z > 0.99 && !(e.parent.respond_to?(:name) && e.parent.name.to_s =~ /vidro/i)
          tops << (e.bounds.max.transform(tr).z * 2.54).round(1)
        elsif e.respond_to?(:definition) && !e.name.to_s.start_with?('Guarda')
          stack << [e.definition.entities, tr * e.transformation]
        end
      end
    end
    tops = tops.uniq.sort
    gcs = esc.definition.entities.grep(Sketchup::ComponentInstance).count { |x| x.name.start_with?('Guarda-corpo') }
    case forma
    when 'L'
      expect(w > 150 && d > 150, "L #{giro}: planta #{w} × #{d} cm (devia virar)")
      expect(giro == 'esquerda' ? bb.max.y > 100.cm : bb.min.y < -100.cm, "L #{giro}: virou para o lado errado")
    when 'U'
      expect(d >= 190, "U: largura total #{d} cm (2 lances + vão)")
    when 'caracol'
      expect((w - 200).abs < 5 && (d - 200).abs < 5, "caracol: diâmetro #{w} × #{d} (esperava 200)")
    end
    expect(tops.include?(262.5), "#{forma}: último degrau em #{tops.last(2).inspect}")
    expect(top >= 280, "#{forma}: altura total #{top}")
    expect(gcs >= 1, "#{forma}: sem guarda-corpo")
    out << "#{forma} #{giro} #{w}×#{d} cm, #{tops.size} níveis, #{gcs} guarda-corpo(s)"
  end
  out.join(' · ')
end

check('railing · varanda em L pelas linhas e por cliques') do
  fresh
  es = [m.entities.add_line(pt(0, 0, 300), pt(400, 0, 300)), m.entities.add_line(pt(400, 0, 300), pt(400, 200, 300))]
  sel(es)
  r = ok!(run(:railing, 'build', 'guarda' => 'vidro', 'gc_alt' => 110))
  g = m.entities.grep(Sketchup::Group).last
  bb = g.bounds
  expect(((bb.max.z - 300.cm) * 2.54).round == 110, "altura #{((bb.max.z - 300.cm) * 2.54).round} (esperava 110)")
  panels = g.entities.grep(Sketchup::Group).size
  expect(panels == 2, "#{panels} vidros (esperava 2, um por trecho)")
  comp = r['stats'][0][1]
  expect(comp == '6,00 m', "comprimento #{comp}")
  ok!(run(:railing, 'draw', 'guarda' => 'montantes', 'mont_esp' => 11))
  click_points([pt(0, 500, 0), pt(220, 500, 0)])
  g2 = m.entities.grep(Sketchup::Group).last
  nm = g2.entities.grep(Sketchup::Face).size / 6
  expect(nm >= 20, "só #{nm} peças nos montantes")
  "vidro em L: #{comp}, 2 vidros, 110 cm · montantes clicados: #{nm} peças"
end

check('scatter · grama no jardim com furo, distância mínima e vários objetos') do
  fresh
  f = floor(400, 300, 0, pilar: true)
  d1 = m.definitions.add('Tufo de grama'); d1.entities.add_face([0, 0, 0], [2, 0, 0], [0, 0, 4])
  d2 = m.definitions.add('Pedra'); d2.entities.add_face([0, 0, 0], [3, 0, 0], [0, 3, 0])
  ok!(run(:scatter, 'list'))
  sel(f)
  r = ok!(run(:scatter, 'run', 'def' => 'Tufo de grama', 'modo' => 'm2', 'dens' => 20, 'dist' => 10, 'seed' => 3))
  g = m.entities.grep(Sketchup::Group).last
  ins = g.entities.grep(Sketchup::ComponentInstance)
  expect((ins.size - 240).abs <= 5, "#{ins.size} tufos (esperava ~240 = 12 m² × 20)")
  inside = ins.count { |i| o = i.transformation.origin; x = o.x * 2.54; y = o.y * 2.54; x >= 180 && x <= 210 && y >= 130 && y <= 160 }
  expect(inside.zero?, "#{inside} tufos dentro do pilar")
  ds = ins.map { |i| i.transformation.origin }.combination(2).map { |a, b| a.distance(b) * 2.54 }.min
  expect(ds >= 9.99, "dois tufos a #{ds.round(1)} cm (mínimo 10)")
  i1 = m.entities.add_instance(d1, IDENTITY); i2 = m.entities.add_instance(d2, Geom::Transformation.new(pt(50, 50)))
  sel(f, i1, i2)
  ok!(run(:scatter, 'run', 'modo' => 'total', 'qtd' => 60, 'dist' => 0))
  g2 = m.entities.grep(Sketchup::Group).last
  tipos = g2.entities.grep(Sketchup::ComponentInstance).map { |i| i.definition.name }.uniq.sort
  expect(tipos == ['Pedra', 'Tufo de grama'], "misturou #{tipos.inspect}")
  ok!(run(:scatter, 'clear'))
  left = m.entities.grep(Sketchup::Group).count { |x| x.name.start_with?('Espalhar') }
  expect(left.zero?, 'apagar espalhados')
  "#{ins.size} tufos em 12 m², nenhum no pilar, distância ≥ 10 cm · 60 misturando #{tipos.join(' e ')} · apagar ok"
end

check('ripado · parede com porta, em pé e deitado, fundo, barras') do
  fresh
  f = m.entities.add_face(pt(0, 0, 0), pt(300, 0, 0), pt(300, 0, 260), pt(0, 0, 260))
  f.reverse! if f.normal.y > 0
  h = m.entities.add_face(pt(110, 0, 0.0001), pt(190, 0, 0.0001), pt(190, 0, 210), pt(110, 0, 210))
  h.erase! if h && h.valid? && !h.equal?(f)
  expect(f.loops.size == 1 || f.loops.size == 2, 'face da parede')
  sel(f)
  r = ok!(run(:ripado, 'build', 'larg' => 4, 'vao' => 2, 'prof' => 2, 'sentido' => 'vertical', 'alinhar' => 'centro'))
  g = m.entities.grep(Sketchup::Group).last
  ins = g.entities.grep(Sketchup::ComponentInstance)
  defs = ins.map(&:definition).uniq
  n = ins.size
  expect(n >= 40 && n <= 55, "#{n} ripas (esperava ~50)")
  expect(defs.size <= 3, "#{defs.size} componentes diferentes (devia reaproveitar)")
  ys = ins.map { |i| i.transformation.origin.y * 2.54 }.uniq.map { |y| y.round(2) }
  expect(ys.all? { |y| y <= 0.01 }, "ripas no lado de fora da parede: y #{ys.inspect}")
  bars = r['stats'].find { |x| x[0].start_with?('Barras') }[1].to_i
  expect(bars > 0, 'conta de barras')
  sel(f)
  r2 = ok!(run(:ripado, 'build', 'larg' => 7, 'vao' => 1, 'sentido' => 'horizontal', 'fundo' => true, 'fundo_esp' => 1.5))
  g2 = m.entities.grep(Sketchup::Group).last
  fundo = g2.entities.grep(Sketchup::Group).first
  expect(fundo && fundo.entities.grep(Sketchup::Face).size >= 6, 'fundo do ripado')
  m2 = g2.entities.grep(Sketchup::ComponentInstance).size
  "em pé: #{n} ripas, #{defs.size} componente(s), #{bars} barras · deitado com fundo: #{m2} ripas"
end

check('shape · todas as arestas: cubo arredondado, chanfrado e peça em L deitada') do
  fresh
  b = box(0, 0, 0, 50, 50, 50, name: 'Cubo')
  sel(b)
  ok!(run(:shape, 'apply', 'modo' => 'tudo', 'acab' => 'redondo', 'raio' => 10, 'seg' => 6))
  es = b.definition.entities
  area = (es.grep(Sketchup::Face).sum(&:area) * 6.4516).round
  exp = (6 * 900 + 12 * 30 * Math::PI * 5 + 4 * Math::PI * 100).round
  expect((area - exp).abs < exp * 0.01, "área do cubo arredondado #{area} (esperava ~#{exp})")
  expect(es.grep(Sketchup::Edge).all? { |e| e.faces.size == 2 }, 'cubo arredondado ficou aberto')
  expect(es.grep(Sketchup::Edge).count(&:soft?) > 100, 'arestas curvas não ficaram suaves')
  xs = es.grep(Sketchup::Face).flat_map(&:vertices).map { |v| (v.position.x * 2.54).round(2) }
  expect(xs.minmax == [0.0, 50.0], "cubo mudou de tamanho #{xs.minmax}")
  c = box(100, 0, 0, 60, 40, 30, name: 'Chanfro')
  sel(c)
  ok!(run(:shape, 'apply', 'modo' => 'tudo', 'acab' => 'chanfro', 'raio' => 5))
  nb = c.definition.entities.grep(Sketchup::Face).size
  expect(nb == 26, "chanfro: #{nb} faces (esperava 6 + 12 + 8 = 26)")
  g = Sketchup.active_model.active_entities.add_group
  f = g.entities.add_face([[0, 0, 0], [80, 0, 0], [80, 0, 20], [20, 0, 20], [20, 0, 60], [0, 0, 60]].map { |x, y, z| pt(x, y + 200, z) })
  f.pushpull(f.normal.y < 0 ? 30.cm : -30.cm)
  sel(g)
  ok!(run(:shape, 'apply', 'modo' => 'tudo', 'acab' => 'redondo', 'raio' => 4, 'seg' => 4))
  expect(g.entities.grep(Sketchup::Edge).all? { |e| e.faces.size == 2 }, 'peça em L ficou aberta')
  "cubo 50 r10: #{area} cm² de superfície, fechado e suave · chanfro: #{nb} faces · peça em L deitada (eixo Y) arredondada e fechada"
end

check('shape · cantos arredondados, chanfro, bordas boleadas e curvar') do
  t = box(0, 0, 0, 120, 60, 3, name: 'Tampo')
  sel(t)
  ok!(run(:shape, 'apply', 'modo' => 'cantos', 'raio' => 10, 'seg' => 8))
  top = t.definition.entities.grep(Sketchup::Face).find { |f| f.normal.z > 0.99 }
  a1 = (top.area * 6.4516).round
  expect((a1 - (7200 - 4 * (100 - Math::PI * 25))).abs < 25, "área com cantos arredondados #{a1} cm²")
  t2 = box(0, 200, 0, 120, 60, 3, name: 'Tampo 2')
  sel(t2)
  ok!(run(:shape, 'apply', 'modo' => 'cantos', 'raio' => 10, 'seg' => 1))
  a2 = (t2.definition.entities.grep(Sketchup::Face).find { |f| f.normal.z > 0.99 }.area * 6.4516).round
  expect(a2 == 7000, "chanfro: área #{a2} (esperava 7000)")
  t3 = box(0, 400, 0, 120, 60, 3, name: 'Tampo 3')
  sel(t3)
  ok!(run(:shape, 'apply', 'modo' => 'bordas', 'raio' => 1, 'seg' => 6, 'cima' => true))
  tops = t3.definition.entities.grep(Sketchup::Face).select { |f| f.normal.z > 0.99 }
  a3 = (tops.max_by(&:area).area * 6.4516).round
  expect(a3 == 118 * 58, "borda boleada: topo #{a3} (esperava #{118 * 58})")
  b = box(0, 600, 0, 200, 40, 45, name: 'Banco')
  sel(b)
  ok!(run(:shape, 'apply', 'modo' => 'curvar', 'raio_curva' => 300, 'sentido' => 'esquerda', 'seg_curva' => 24))
  c = pt(0, 640 + 300)
  ds = b.definition.entities.grep(Sketchup::Face).flat_map(&:vertices).map { |v| (Geom::Point3d.new(v.position.x, v.position.y, 0).distance(c) * 2.54).round(1) }.uniq
  expect((ds.min - 300).abs < 0.5 && (ds.max - 340).abs < 0.5, "banco curvo com raios #{ds.min}–#{ds.max} (esperava 300–340)")
  f = floor(pilar: false)
  sel(f)
  ok!(run(:shape, 'apply', 'modo' => 'cantos', 'raio' => 30, 'seg' => 8))
  "cantos r10: #{a1} cm² · chanfro: #{a2} cm² · borda boleada: topo #{a3} cm² · banco curvo: raio 300–340 cm"
end

check('edges · suavizar curvas, esconder, mostrar e estilo') do
  g = m.entities.add_group
  n = 24
  ring = (0...n).map { |k| a = 2 * Math::PI * k / n; pt(50 * Math.cos(a), 50 * Math.sin(a)) }
  f = g.entities.add_face(ring)
  f.reverse! if f.normal.z > 0
  f.pushpull(-40.cm)
  sel(g)
  a = ok!(run(:edges, 'suavizar', 'angulo' => 30))
  soft = g.definition.entities.grep(Sketchup::Edge).count(&:soft?)
  expect(soft == n, "suavizou #{soft} (esperava #{n} arestas laterais)")
  ok!(run(:edges, 'ocultar'))
  expect(g.definition.entities.grep(Sketchup::Edge).all?(&:hidden?), 'não escondeu')
  ok!(run(:edges, 'mostrar'))
  expect(g.definition.entities.grep(Sketchup::Edge).none? { |e| e.hidden? || e.soft? }, 'não mostrou de volta')
  ok!(run(:edges, 'estilo', 'linhas' => false))
  expect(m.rendering_options['EdgeDisplayMode'] == 0, 'estilo continuou com linhas')
  "#{soft} arestas da curva suavizadas; esconder/mostrar/estilo ok"
end

check('materials · conta-gotas, trocar na cena, limpar bloco, prontos') do
  ma = m.materials.add('Madeira clara'); mb = m.materials.add('Madeira escura')
  b1 = box(0, 0, 0, 50, 50, 50, mat: ma); b2 = box(100, 0, 0, 50, 50, 50)
  b2.definition.entities.grep(Sketchup::Face).first.material = ma
  l = ok!(run(:materials, 'list'))
  ok!(run(:materials, 'pick'))
  click_face(b2.definition.entities.grep(Sketchup::Face).first)
  expect(pushed.last['values']['de'] == 'Madeira clara', 'conta-gotas não pegou o material')
  r = ok!(run(:materials, 'swap', 'de' => 'Madeira clara', 'para' => 'Madeira escura'))
  expect(b1.material == mb && b2.definition.entities.grep(Sketchup::Face).first.material == mb, 'não trocou em todo lugar')
  sel(b2); ok!(run(:materials, 'clean'))
  expect(b2.definition.entities.grep(Sketchup::Face).none?(&:material), 'não limpou o bloco')
  sel(b1); ok!(run(:materials, 'apply', 'preset' => 'vidro_fume'))
  expect(b1.material.name == 'lavi Vidro fumê' && b1.material.alpha < 1, 'vidro pronto errado')
  "#{l['mats'].size} materiais listados · #{r['msg']}"
end

check('texmap · projeção caixa, plana, esférica e girar') do
  img = File.join(OUT, 'madeira.jpg'); File.write(img, 'jpg')
  mt = m.materials.add('Madeira'); mt.texture = img
  b = box(0, 0, 0, 100, 60, 40, mat: mt)
  sel(b)
  out = []
  %w[caixa plana esferica].each do |pj|
    r = ok!(run(:texmap, 'apply', 'projecao' => pj, 'tam' => 60, 'rot' => 90))
    out << "#{pj} #{r['stats'][0][1]}"
  end
  expect(b.definition.entities.grep(Sketchup::Face).all?(&:uv_data), 'faces sem mapeamento')
  sel(box(300, 0, 0, 10, 10, 10))
  e = run(:texmap, 'apply')
  expect(!e['ok'], 'aceitou bloco sem textura')
  out.join(', ') + ' faces'
end

check('lights · marcar luz, conta-gotas, facho, parede e letreiro') do
  fita = box(0, 0, 250, 300, 2, 2, name: 'Fita LED')
  sel(fita)
  ok!(run(:lights, 'mark', 'temp' => '2700'))
  expect(fita.material.name == 'lavi Luz 2700K', 'não marcou a luz')
  spot = component('Spot', 10, 10, 6, pt(100, 100, 254))
  sel(spot)
  ok!(run(:lights, 'beam', 'abertura' => 36, 'piso' => 0))
  cone = m.entities.grep(Sketchup::ComponentInstance).find { |x| x.name == 'Facho de luz' }
  expect(cone && (cone.bounds.min.z * 2.54).abs < 1 && cone.material.alpha < 1, 'facho errado')
  wall = m.entities.add_face(pt(0, 300, 0), pt(400, 300, 0), pt(400, 300, 280), pt(0, 300, 280))
  ok!(run(:lights, 'wash'))
  click_face(wall, pt(200, 300, 240))
  expect(pushed.last['ok'], pushed.last['msg'])
  ok!(run(:lights, 'neon', 'texto' => 'Bem-vindo', 'letra' => 15))
  click_face(wall, pt(200, 300, 160))
  neon = m.entities.grep(Sketchup::ComponentInstance).find { |x| x.name.start_with?('Letreiro') }
  expect(neon && neon.bounds.width > 1 && neon.bounds.height < 2.cm + 0.01, 'letreiro não ficou na parede')
  "luz 2700K, facho até o piso, mancha na parede e letreiro neon"
end

check('randomize · girar, escala e misturar materiais') do
  mats = %w[A B C].map { |n| m.materials.add("Verde #{n}") }
  plantas = (0...6).map { |k| component('Planta', 40, 40, 100, pt(k * 80, 0)).tap { |x| x.material = mats[k % 3] } }
  before = plantas.map { |x| x.transformation.to_a }
  sel(plantas)
  ok!(run(:randomize, 'run', 'girar' => 180, 'escala' => 15, 'misturar' => true, 'seed' => 7))
  mudou = plantas.each_with_index.count { |x, i| x.transformation.to_a != before[i] }
  expect(mudou == 6, "só #{mudou} variaram")
  hs = plantas.map { |x| (x.bounds.depth * 2.54).round(1) }
  expect(hs.uniq.size > 2 && hs.all? { |h| h.between?(84.9, 115.1) }, "alturas #{hs.inspect}")
  "alturas #{hs.min}–#{hs.max} cm, todas giradas"
end

# === Painel e atualização
check('painel · abrir e mandar estado') do
  P::Dialog.instance_variable_get(:@dlg).close
  P::Dialog.show
  init = $js.find { |j| j.start_with?('PLN.init(') } or raise 'painel não iniciou'
  st = JSON.parse(init[/\APLN\.init\((.*)\)\z/m, 1])
  expect(st['tools'].size == P::Registry.all.size, 'lista de ferramentas incompleta')
  missing = st['tools'].map { |t| t['id'] } - FORMS.keys
  expect(missing.empty?, "ferramentas sem formulário no painel: #{missing.join(', ')}")
  extra = FORMS.keys - st['tools'].map { |t| t['id'] }
  expect(extra.empty?, "formulários sem ferramenta no Ruby: #{extra.join(', ')}")
  "#{st['tools'].size} ferramentas, todas com formulário"
end

# ---------------------------------------------------------------- relatório
if __FILE__ == $PROGRAM_NAME
ok = $results.count { |r| r[1] == :ok }
w = $results.map { |r| r[0].size }.max.to_i
$results.each do |name, st, info, t|
  puts format("%s  %-#{w}s  %5.2fs  %s", st == :ok ? 'OK    ' : 'FALHOU', name, t, info[0, 220])
end
puts "\n#{ok}/#{$results.size} cenários OK"
exit(ok == $results.size ? 0 : 1)
end
