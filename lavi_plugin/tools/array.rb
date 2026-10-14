# Copiar em grade ou ao longo de um caminho: luminárias no forro, cadeiras em volta da mesa,
# postes na calçada, vasos na varanda. Selecione o objeto e a face (ou as linhas do caminho).

module LAVIStudio
  module Plugin
    module Tools
      module ArrayCopy
        extend self
        H = Helpers

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'build'
          sel = H.selection.to_a
          items = sel.select { |e| H.instance?(e) }
          return H.err('Selecione UM grupo ou componente (o objeto a copiar).') if items.size != 1
          item = items[0]
          modo = p['modo'].to_s
          news = []
          H.operation('lavi · Copiar') do
            news = if modo == 'caminho'
                     path_copies(item, sel.grep(Sketchup::Edge), p)
                   else
                     grid_copies(item, sel.grep(Sketchup::Face).first, p)
                   end
            item.erase! if (p['apagar'] == true || p['apagar'] == 'true') && news.any?
          end
          H.selection.clear
          H.selection.add(news)
          H.ok("#{news.size} cópia(s) criada(s).", stats: [['Cópias', news.size.to_s]])
        rescue RuntimeError => e
          H.err(e.message)
        end

        # ---- grade -----------------------------------------------------------
        def grid_copies(item, face, p)
          ex = H.cm([H.num(p['esp_x'], 120), 1].max)
          ey = H.cm([H.num(p['esp_y'], 120), 1].max)
          pts = []
          if face
            margin = H.cm(H.num(p['margem'], 60))
            bb = face.bounds
            z = face.vertices[0].position.z
            raise 'A face precisa estar deitada (piso ou forro).' unless face.normal.z.abs > 0.98
            nx = [((bb.width - 2 * margin) / ex).floor, 0].max + 1
            ny = [((bb.height - 2 * margin) / ey).floor, 0].max + 1
            x0 = bb.center.x - (nx - 1) * ex / 2.0
            y0 = bb.center.y - (ny - 1) * ey / 2.0
            nx.times do |i|
              ny.times do |j|
                q = Geom::Point3d.new(x0 + i * ex, y0 + j * ey, z)
                pts << q if [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge].include?(face.classify_point(q))
              end
            end
            raise 'Nenhuma cópia coube na face. Diminua o espaçamento ou a margem.' if pts.empty?
            anchor = anchor_of(item, face.normal.z > 0 ? :bottom : :top)
          else
            nx = [H.num(p['colunas'], 3).to_i, 1].max
            ny = [H.num(p['linhas'], 2).to_i, 1].max
            base = anchor_of(item, :bottom)
            nx.times { |i| ny.times { |j| pts << base.offset(X_AXIS, i * ex).offset(Y_AXIS, j * ey) unless i.zero? && j.zero? } }
            anchor = base
          end
          pts.map { |q| place(item, Geom::Transformation.translation(q - anchor)) }
        end

        # ponto de referência do objeto: centro de baixo (piso) ou de cima (forro)
        def anchor_of(item, where)
          b = item.bounds
          Geom::Point3d.new(b.center.x, b.center.y, where == :top ? b.max.z : b.min.z)
        end

        # ---- caminho ----------------------------------------------------------
        def path_copies(item, edges, p)
          raise 'Selecione também as linhas do caminho.' if edges.empty?
          chain = chain_points(edges)
          lens = chain.each_cons(2).map { |a, b| a.distance(b) }
          total = lens.sum
          raise 'Caminho muito curto.' if total < 1.cm
          if p['por'] == 'quantidade'
            n = [H.num(p['qtd'], 5).to_i, 2].max
            ds = (0...n).map { |i| total * i / (n - 1).to_f }
          else
            step = H.cm([H.num(p['espac'], 100), 1].max)
            ds = (0..(total / step).floor).map { |i| i * step }
            ds << total if p['fim'] != false && p['fim'] != 'false' && (total - ds.last) > step * 0.25
          end
          anchor = anchor_of(item, :bottom)
          girar = p['girar'] != false && p['girar'] != 'false'
          ref = nil
          ds.map do |d|
            q, dir = at_distance(chain, lens, d)
            t = Geom::Transformation.translation(q - anchor)
            if girar
              ang = Math.atan2(dir.y, dir.x)
              ref ||= ang
              t = Geom::Transformation.rotation(q, Z_AXIS, ang - ref) * t
            end
            place(item, t)
          end
        end

        # liga as arestas selecionadas numa sequência de pontos (de uma ponta à outra)
        def chain_points(edges)
          left = edges.dup
          e = left.shift
          pts = [e.start.position, e.end.position]
          until left.empty?
            nxt = left.find { |x| x.vertices.any? { |v| v.position == pts.last } }
            if nxt
              pts << (nxt.start.position == pts.last ? nxt.end.position : nxt.start.position)
            else
              nxt = left.find { |x| x.vertices.any? { |v| v.position == pts.first } }
              break unless nxt
              pts.unshift(nxt.start.position == pts.first ? nxt.end.position : nxt.start.position)
            end
            left.delete(nxt)
          end
          pts
        end

        def at_distance(chain, lens, d)
          acc = 0.0
          lens.each_with_index do |l, i|
            if d <= acc + l + 1e-6 || i == lens.size - 1
              a = chain[i]
              b = chain[i + 1]
              t = l > 0 ? [[(d - acc) / l, 0].max, 1].min : 0
              return [Geom.linear_combination(1 - t, a, t, b), b - a]
            end
            acc += l
          end
        end

        def place(item, t)
          ents = H.model.active_entities
          if item.is_a?(Sketchup::Group)
            c = item.copy
            c.transformation = t * item.transformation
            c
          else
            c = ents.add_instance(item.definition, t * item.transformation)
            c.material = item.material
            c.layer = item.layer
            c
          end
        end

        Registry.register(:array, name: 'Copiar em grade ou caminho', tab: :base, package: :base, handler: self,
                                  desc: 'Espalha cópias numa face (luminárias no forro) ou ao longo de linhas (cadeiras, postes).',
                                  steps: ['Selecione o objeto e a face ou as linhas', 'Escolha o espaçamento', 'Copiar'])
      end
    end
  end
end
