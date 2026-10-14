# Paredes: desenhar clicando pontos, ou gerar a partir de linhas selecionadas

module LAVIStudio
  module Plugin
    module Tools
      module Walls
        extend self
        H = Helpers
        G = Geom2

        # unidade usada quando ela digita só o número no campo de medidas
        def unit_of(p)
          u = p['unid'].to_s
          %w[m cm mm].include?(u) ? u : nil
        end

        def handle(action, p)
          case action
          when 'draw'
            Sketchup.active_model.select_tool(
              Pickers::PointPicker.new('Paredes: clique os cantos (ou digite a medida)', unit: unit_of(p)) { |pts, closed| build_async(pts, closed, p) }
            )
            H.ok('Clique os cantos da parede no modelo. Enter termina, clicar no 1º ponto fecha o ambiente.', picking: true)
          when 'from_edges'
            chains = chain_edges(H.selection.grep(Sketchup::Edge))
            return H.err('Selecione as linhas da planta (ex.: o eixo das paredes).') if chains.empty?
            info = H.operation('LAVI · Paredes') { chains.map { |pts, closed| build(pts, closed, p) } }
            summary(info)
          else
            H.err('Ação desconhecida.')
          end
        end

        def build_async(pts, closed, p)
          info = H.operation('LAVI · Paredes') { [build(pts, closed, p)] }
          Dialog.push('result', { tool: 'walls' }.merge(summary(info)))
        rescue StandardError => e
          Dialog.push('result', tool: 'walls', ok: false, msg: e.message)
        end

        def summary(info)
          comp = info.sum { |i| i[:len] }
          area = info.sum { |i| i[:area] }
          H.ok("#{info.size} parede(s) criada(s).",
               stats: [['Comprimento', "#{H.br(comp)} m"], ['Área (1 face)', "#{H.br(area)} m²"], ['Área (2 faces)', "#{H.br(area * 2)} m²"]])
        end

        # Gera o volume da parede. Devolve {len: m, area: m²}
        def build(pts3d, closed, p)
          esp = H.cm(H.num(p['esp'], 15))
          alt = H.cm(H.num(p['alt'], 280))
          z = pts3d[0].z
          pts = G.clean(pts3d.map { |q| [q.x.to_f, q.y.to_f] })
          closed = false if pts.size < 3
          a, b = case p['alinh']
                 when 'esquerda' then [esp, 0.0]
                 when 'direita' then [0.0, -esp]
                 else [esp / 2.0, -esp / 2.0]
                 end
          la = G.offset_polyline(pts, a, closed)
          lb = G.offset_polyline(pts, b, closed)
          m = H.model
          grp = m.active_entities.add_group
          ents = grp.entities
          to3 = ->(arr) { arr.map { |q| Geom::Point3d.new(q[0], q[1], z) } }
          if closed
            outer, inner = G.area(la) > G.area(lb) ? [la, lb] : [lb, la]
            face = ents.add_face(to3.call(outer))
            hole = ents.add_face(to3.call(inner))
            hole.erase! if hole && hole.valid?
          else
            face = ents.add_face(to3.call(la + lb.reverse))
          end
          face.reverse! if face.normal.z < 0
          face.pushpull(alt)
          grp.material = H.material('LAVI_Parede', 'F2F0EC')
          grp.layer = H.tag('LAVI · Paredes')
          grp.name = 'Parede'
          H.mark(grp, 'wall', 'esp_cm' => H.to_cm(esp), 'alt_cm' => H.to_cm(alt))
          len = 0.0
          segs = closed ? pts.size : pts.size - 1
          segs.times { |i| len += G.len(G.sub(pts[(i + 1) % pts.size], pts[i])) }
          { len: H.to_m(len), area: H.to_m(len) * H.to_m(alt) }
        end

        # Junta arestas soltas em polilinhas: [[pontos], fechada?]
        def chain_edges(edges)
          left = edges.dup
          out = []
          until left.empty?
            e = left.shift
            chain = [e.start, e.end]
            grow = lambda do |at_end|
              loop do
                v = at_end ? chain[-1] : chain[0]
                nxt = left.find { |x| x.vertices.include?(v) }
                break unless nxt
                left.delete(nxt)
                o = nxt.other_vertex(v)
                at_end ? chain.push(o) : chain.unshift(o)
              end
            end
            grow.call(true)
            grow.call(false)
            closed = chain.size > 3 && chain[0] == chain[-1]
            chain.pop if closed
            out << [chain.map(&:position), closed]
          end
          out
        end

        Registry.register(:walls, name: 'Paredes', tab: :arq, package: :arq, handler: self,
                                  desc: 'Desenhe clicando os cantos ou gere a partir das linhas da planta.',
                                  steps: ['Escolha espessura e altura', 'Clique os cantos no modelo', 'Enter para terminar'])
      end
    end
  end
end
