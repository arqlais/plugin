# Espalhar objetos numa face: grama, pedrisco, plantas, folhas, pedras, cadeiras de plateia…
# Leve: cada objeto é uma cópia (instância) do componente, girada e com tamanho sorteado.
# Tudo vai num grupo com a etiqueta "lavi · Espalhar" (desligue a etiqueta para o SketchUp andar mais rápido).

module LAVIStudio
  module Plugin
    module Tools
      module Scatter
        extend self
        H = Helpers
        G = Geom2
        MAX = 5000

        def handle(action, p)
          case action
          when 'list'
            defs = H.model.definitions.reject { |d| d.group? || d.image? || d.name.start_with?('lavi ') }
            H.ok("#{defs.size} componentes no modelo.", defs: defs.sort_by(&:name).map { |d| [d.name, d.instances.size] })
          when 'run' then run(p)
          when 'clear' then clear
          else H.err('Ação desconhecida.')
          end
        end

        def run(p)
          sel = H.selection.to_a
          faces = sel.grep(Sketchup::Face).map { |f| [f, IDENTITY] }
          sel.grep(Sketchup::Group).each do |g|
            H.entities_of(g).grep(Sketchup::Face).each { |f| faces << [f, g.transformation] if f.normal.transform(g.transformation).z > 0.5 }
          end
          defs = sel.select { |e| e.is_a?(Sketchup::ComponentInstance) && !e.is_a?(Sketchup::Group) }.map(&:definition).uniq
          if defs.empty?
            d = H.model.definitions[p['def'].to_s]
            defs = [d] if d
          end
          return H.err('Selecione a face (ou o grupo do terreno) onde espalhar.') if faces.empty?
          return H.err('Escolha o objeto na lista, ou selecione junto com a face uma ou mais cópias dos objetos.') if defs.empty?
          rnd = Random.new(H.num(p['seed'], 1).to_i)
          dmin = H.cm([H.num(p['dist'], 20), 0].max)
          info = faces.map do |f, tr|
            fr = G.face_frame(f, tr)
            outer, holes = G.face_loops_2d(f, tr, fr)
            { f: f, fr: fr, outer: outer, holes: holes, area: G.area(outer) - holes.sum { |h| G.area(h) } }
          end
          area = info.sum { |i| i[:area] }
          want = if p['modo'] == 'total'
                   H.num(p['qtd'], 100).to_i
                 else
                   (H.m2(area) * H.num(p['dens'], 10)).round
                 end
          return H.err('Nenhum objeto para colocar: aumente a quantidade.') if want < 1
          return H.err("Ficariam #{want} objetos: é demais para uma vez (máximo #{MAX}). Diminua a densidade ou espalhe por partes.") if want > MAX
          pts = []
          grid = {}
          cell = dmin > 0 ? dmin : 1.0
          info.each do |inf|
            n = (want * inf[:area] / area).round
            bx = G.bbox(inf[:outer])
            tries = 0
            got = 0
            while got < n && tries < n * 30
              tries += 1
              q = [bx[0] + rnd.rand * (bx[2] - bx[0]), bx[1] + rnd.rand * (bx[3] - bx[1])]
              next unless G.point_in_poly?(q, inf[:outer]) && inf[:holes].none? { |h| G.point_in_poly?(q, h) }
              w = G.to_3d(q, inf[:fr])
              if dmin > 0
                k = [(w.x / cell).floor, (w.y / cell).floor, (w.z / cell).floor]
                near = false
                (-1..1).each { |a| (-1..1).each { |b| (-1..1).each { |c| (grid[[k[0] + a, k[1] + b, k[2] + c]] || []).each { |o| near ||= o.distance(w) < dmin } } } }
                next if near
                (grid[k] ||= []) << w
              end
              pts << [w, inf[:fr][:n]]
              got += 1
            end
          end
          girar = p['girar'] != false && p['girar'] != 'false'
          esc = [H.num(p['escala'], 20), 0].max / 100.0
          seguir = p['normal'] == true || p['normal'] == 'true'
          H.operation('lavi · Espalhar') do
            g = H.model.active_entities.add_group
            g.name = "Espalhar · #{defs.map(&:name).join(', ')}"
            g.layer = H.tag('lavi · Espalhar')
            ents = g.entities
            pts.each do |w, n|
              d = defs[rnd.rand(defs.size)]
              k = 1 + (rnd.rand * 2 - 1) * esc
              up = seguir ? n : Z_AXIS
              t = Geom::Transformation.new(w, up)
              t *= Geom::Transformation.rotation(ORIGIN, Z_AXIS, rnd.rand * 2 * Math::PI) if girar
              t *= Geom::Transformation.scaling(ORIGIN, k) if (k - 1).abs > 1e-6
              ents.add_instance(d, t)
            end
          end
          falt = want - pts.size
          H.ok("#{pts.size} objeto(s) espalhado(s)#{falt > 0 ? " (#{falt} não couberam com a distância mínima)" : ''}.",
               stats: [['Objetos', pts.size.to_s], ['Área', "#{H.br(H.m2(area))} m²"], ['Tipos', defs.size.to_s]],
               warn: falt > 0)
        end

        # apaga os grupos de espalhar selecionados (ou todos, se nada estiver selecionado)
        def clear
          gs = H.selection.to_a.select { |e| e.is_a?(Sketchup::Group) && e.name.start_with?('Espalhar') }
          gs = H.model.active_entities.grep(Sketchup::Group).select { |e| e.name.start_with?('Espalhar') } if gs.empty?
          return H.err('Nenhum grupo de espalhar encontrado.') if gs.empty?
          H.operation('lavi · Apagar espalhados') { H.model.active_entities.erase_entities(gs) }
          H.ok("#{gs.size} grupo(s) apagado(s).")
        end

        Registry.register(:scatter, name: 'Espalhar objetos', tab: :render, package: :pres, handler: self,
                                    desc: 'Grama, pedrisco, plantas e pedras espalhados numa face, girados e com tamanhos variados.',
                                    steps: ['Selecione a face (e os objetos)', 'Escolha quantidade e variação', 'Espalhar'])
      end
    end
  end
end
