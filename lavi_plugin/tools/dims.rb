# Cotas automáticas: cota o contorno de pisos e paredes selecionados (externas e internas dos
# ambientes) e as medidas totais, já afastadas do desenho e numa etiqueta própria.

module LAVIStudio
  module Plugin
    module Tools
      module Dims
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          case action
          when 'build' then build(p)
          when 'clear' then clear
          else H.err('Ação desconhecida.')
          end
        end

        # faces de onde tirar as cotas: faces selecionadas ou a face de cima de cada grupo
        def sources
          out = H.selection.grep(Sketchup::Face).select { |f| H.horizontal?(f) }.map { |f| [f, IDENTITY] }
          H.selection.to_a.select { |e| H.instance?(e) }.each do |inst|
            tops = []
            H.each_face(H.entities_of(inst), inst.transformation) { |f, tr, _| tops << [f, tr] if f.normal.transform(tr).z > 0.98 }
            next if tops.empty?
            zmax = tops.map { |f, tr| f.vertices[0].position.transform(tr).z }.max
            tops.select { |f, tr| (f.vertices[0].position.transform(tr).z - zmax).abs < 0.5.cm }.each { |x| out << x }
          end
          out.uniq { |f, _| f.entityID }
        end

        def build(p)
          src = sources
          return H.err('Selecione pisos (faces) ou grupos de parede para cotar.') if src.empty?
          off = H.cm(H.num(p['dist'], 40))
          min = H.cm(H.num(p['minimo'], 10))
          internas = p['internas'] != false && p['internas'] != 'false'
          externas = p['externas'] != false && p['externas'] != 'false'
          total = p['total'] != false && p['total'] != 'false'
          rings = outline(src)
          n = 0
          H.operation('lavi · Cotas') do
            ents = H.model.active_entities
            layer = H.tag('lavi · Cotas')
            add = lambda do |a, b, v|
              d = ents.add_dimension_linear(a, b, v)
              d.layer = layer if d.respond_to?(:layer=)
              n += 1
            end
            bb = Geom::BoundingBox.new
            rings.each do |ring, outer|
              bb.add(ring) if outer
              next if outer ? !externas : !internas
              # contorno externo anti-horário e furos horários: o lado de fora da parede fica à direita
              ring = ring.reverse if (signed_xy(ring) > 0) != outer
              dedupe_collinear(ring).tap do |r|
                r.each_with_index do |a, i|
                  b = r[(i + 1) % r.size]
                  next if a.distance(b) < min
                  dir = b - a
                  out = Geom::Vector3d.new(dir.y, -dir.x, 0)
                  out.length = off
                  add.call(a, b, out)
                end
              end
            end
            if total && !bb.empty?
              z = bb.min.z
              add.call(Geom::Point3d.new(bb.min.x, bb.min.y, z), Geom::Point3d.new(bb.max.x, bb.min.y, z), Geom::Vector3d.new(0, -2.2 * off, 0))
              add.call(Geom::Point3d.new(bb.min.x, bb.min.y, z), Geom::Point3d.new(bb.min.x, bb.max.y, z), Geom::Vector3d.new(-2.2 * off, 0, 0))
            end
          end
          H.ok("#{n} cota(s) criada(s) na etiqueta \"lavi · Cotas\".", stats: [['Cotas', n.to_s], ['Faces lidas', src.size.to_s]])
        end

        # Contorno do conjunto de faces (paredes em vários trechos viram um contorno só):
        # arestas usadas por uma face só do conjunto, ligadas em anéis. Devolve [[pontos, externo?]]
        def outline(src)
          rings = []
          src.group_by { |f, tr| [f.parent, tr.to_a] }.each_value do |list|
            tr = list[0][1]
            set = list.map { |f, _| [f, true] }.to_h
            edges = list.flat_map { |f, _| f.edges }.uniq.select { |e| e.faces.count { |g| set[g] } == 1 }
            left = edges.map { |e| [e, true] }.to_h
            until left.empty?
              e0 = left.keys.first
              left.delete(e0)
              ring = [e0.start, e0.end]
              loop do
                v = ring.last
                nxt = v.edges.find { |e| left[e] }
                break unless nxt
                left.delete(nxt)
                w = nxt.other_vertex(v)
                break if w == ring.first
                ring << w
              end
              rings << ring.map { |v| v.position.transform(tr) } if ring.size >= 3
            end
          end
          # anel dentro de outro = interno (ambiente/pilar)
          rings.map do |r|
            inner = rings.any? { |o| !o.equal?(r) && area_xy(o) > area_xy(r) && inside_xy?(r[0], o) && inside_xy?(r[r.size / 2], o) }
            [r, !inner]
          end
        end

        def area_xy(pts) signed_xy(pts).abs / 2.0 end

        def inside_xy?(q, poly)
          inside = false
          j = poly.size - 1
          poly.each_with_index do |a, i|
            b = poly[j]
            if (a.y > q.y) != (b.y > q.y) && q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x
              inside = !inside
            end
            j = i
          end
          inside
        end

        def signed_xy(pts)
          s = 0.0
          pts.each_with_index { |a, i| b = pts[(i + 1) % pts.size]; s += a.x * b.y - b.x * a.y }
          s
        end

        # junta trechos alinhados (linhas quebradas viram uma cota só)
        def dedupe_collinear(pts)
          out = pts.dup
          changed = true
          while changed && out.size > 3
            changed = false
            out.each_index do |i|
              a = out[i - 1]
              b = out[i]
              c = out[(i + 1) % out.size]
              u = b - a
              v = c - b
              next unless u.valid? && v.valid?
              next unless u.cross(v).length < 1e-6 * u.length * v.length && u.dot(v) > 0
              out.delete_at(i)
              changed = true
              break
            end
          end
          out
        end

        def clear
          layer = H.model.layers['lavi · Cotas']
          return H.ok('Não há cotas do lavi.') unless layer
          dims = H.model.active_entities.to_a.select { |e| e.is_a?(Sketchup::Dimension) && e.layer == layer }
          H.operation('lavi · Apagar cotas') { H.model.active_entities.erase_entities(dims) } unless dims.empty?
          H.ok("#{dims.size} cota(s) apagada(s).")
        end

        Registry.register(:dims, name: 'Cotas automáticas', tab: :arq, package: :arq, handler: self,
                                 desc: 'Cota o contorno dos pisos e das paredes, por dentro e por fora, e as medidas totais.',
                                 steps: ['Selecione pisos ou paredes', 'Escolha o que cotar', 'Cotar'])
      end
    end
  end
end
