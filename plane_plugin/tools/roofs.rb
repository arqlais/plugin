# Telhado de 1, 2 ou 4 águas a partir de uma face (contorno da cobertura)

module Plane
  module Plugin
    module Tools
      module Roofs
        extend self
        H = Helpers
        G = Geom2

        TELHAS = {
          'ceramica'    => { nome: 'Cerâmica',    por_m2: 16.0, cor: 'B5653F' },
          'concreto'    => { nome: 'Concreto',    por_m2: 10.5, cor: '7A7470' },
          'fibrocimento' => { nome: 'Fibrocimento (2,44×1,10)', por_m2: 1 / 2.2, cor: 'A9ABA8' },
          'metalica'    => { nome: 'Metálica sanduíche', por_m2: 1.0, cor: '8C9196' }
        }.freeze

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'build'
          faces = H.selected_faces.select { |f, tr| H.horizontal?(f, tr) }
          return H.err('Selecione a face do contorno da cobertura (vista de cima).') if faces.empty?
          face, tr = faces.max_by { |f, t| H.face_area(f, t) }
          slope = H.num(p['incl'], 30) / 100.0
          beiral = H.cm(H.num(p['beiral'], 50))
          tipo = p['tipo'] || '2aguas'
          telha = TELHAS[p['telha']] || TELHAS['ceramica']

          pts = face.outer_loop.vertices.map { |v| v.position.transform(tr) }
          z0 = pts[0].z + H.cm(H.num(p['elev'], 0))
          longest = pts.each_with_index.map { |q, i| [q, pts[(i + 1) % pts.size]] }.max_by { |a, b| a.distance(b) }
          u = Geom::Vector3d.new(longest[1].x - longest[0].x, longest[1].y - longest[0].y, 0)
          u.normalize!
          v = Z_AXIS.cross(u)
          loc = pts.map { |q| [q.x * u.x + q.y * u.y, q.x * v.x + q.y * v.y] }
          x0, y0, x1, y1 = G.bbox(loc)
          x0 -= beiral
          y0 -= beiral
          x1 += beiral
          y1 += beiral
          len = x1 - x0
          wid = y1 - y0
          world = lambda do |x, y, z|
            gx = x0 + x
            gy = y0 + y
            Geom::Point3d.new(u.x * gx + v.x * gy, u.y * gx + v.y * gy, z0 + z)
          end

          info = H.operation('Planê · Telhado') do
            grp = H.model.active_entities.add_group
            e = grp.entities
            a = world.call(0, 0, 0)
            b = world.call(len, 0, 0)
            c = world.call(len, wid, 0)
            d = world.call(0, wid, 0)
            slopes = []
            ridge = 0.0
            case tipo
            when '1agua'
              h = wid * slope
              ee = world.call(0, wid, h)
              ff = world.call(len, wid, h)
              slopes << e.add_face(a, b, ff, ee)
              e.add_face(d, c, ff, ee)
              e.add_face(a, d, ee)
              e.add_face(b, c, ff)
            when '4aguas'
              h = wid / 2.0 * slope
              if (len - wid).abs < 1e-3
                apex = world.call(len / 2.0, wid / 2.0, h)
                [[a, b], [b, c], [c, d], [d, a]].each { |p1, p2| slopes << e.add_face(p1, p2, apex) }
              else
                r1 = world.call(wid / 2.0, wid / 2.0, h)
                r2 = world.call(len - wid / 2.0, wid / 2.0, h)
                slopes << e.add_face(a, b, r2, r1)
                slopes << e.add_face(b, c, r2)
                slopes << e.add_face(c, d, r1, r2)
                slopes << e.add_face(d, a, r1)
                ridge = len - wid
              end
            else
              h = wid / 2.0 * slope
              r1 = world.call(0, wid / 2.0, h)
              r2 = world.call(len, wid / 2.0, h)
              slopes << e.add_face(a, b, r2, r1)
              slopes << e.add_face(c, d, r1, r2)
              e.add_face(a, r1, d)
              e.add_face(b, c, r2)
              ridge = len
            end
            bottom = e.add_face(a, b, c, d)
            bottom.reverse! if bottom.normal.z > 0
            e.grep(Sketchup::Face).each { |f| f.reverse! if f != bottom && f.normal.z < -0.01 }
            mat = H.material("PLN_Telha_#{p['telha'] || 'ceramica'}", telha[:cor])
            slopes.compact.each { |f| f.material = mat }
            grp.name = 'Telhado'
            grp.layer = H.tag('Planê · Cobertura')
            area = slopes.compact.sum(&:area)
            H.mark(grp, 'roof', 'area_m2' => H.m2(area))
            { area: H.m2(area), proj: H.m2(len * wid), ridge: H.to_m(ridge), h: H.to_cm(h) }
          end
          qtd = (info[:area] * telha[:por_m2] * 1.05).ceil
          H.ok('Telhado criado.', stats: [
                 ['Área inclinada', "#{H.br(info[:area])} m²"], ['Área projetada', "#{H.br(info[:proj])} m²"],
                 ['Altura da cumeeira', "#{H.br(info[:h], 0)} cm"], ['Cumeeira', "#{H.br(info[:ridge])} m"],
                 ["Telhas (#{telha[:nome]}, +5%)", qtd.to_s]
               ])
        end

        Registry.register(:roofs, name: 'Telhado', tab: :arq, package: :arq, handler: self,
                                  desc: '1, 2 ou 4 águas com beiral, inclinação e contagem de telhas.',
                                  steps: ['Selecione o contorno da cobertura', 'Escolha águas e inclinação', 'Gerar'])
      end
    end
  end
end
