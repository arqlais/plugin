# Rodapé automático: contorna o piso (e os pilares) pulando as portas marcadas

module LAVIStudio
  module Plugin
    module Tools
      module Baseboard
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'build'
          faces = H.selected_faces.select { |f, tr| H.horizontal?(f, tr) }
          return H.err('Selecione a face do piso. Para pular portas, segure Shift e selecione também as linhas das portas.') if faces.empty?
          doors = H.selection.grep(Sketchup::Edge)
          alt = H.cm(H.num(p['alt'], 7))
          esp = H.cm(H.num(p['esp'], 1.5))
          total = 0.0
          H.operation('LAVI · Rodapé') do
            mat = H.material("LAVI_Rodape_#{p['cor'].to_s.delete('#')}", p['cor'] || 'FFFFFF')
            grp = H.model.active_entities.add_group
            faces.each do |face, tr|
              fr = G.face_frame(face, tr)
              face.loops.each do |lp|
                runs(lp, doors).each do |edges_pts, closed|
                  pts2 = G.clean(edges_pts.map { |v| G.to_2d(v.transform(tr), fr) })
                  next if pts2.size < 2
                  sign = lp.outer? ? 1.0 : -1.0
                  loop_poly = lp.vertices.map { |v| G.to_2d(v.position.transform(tr), fr) }
                  sign = -sign if G.signed_area(loop_poly) < 0
                  total += piece(grp.entities, pts2, closed, esp * sign, alt, fr)
                end
              end
            end
            grp.material = mat
            grp.name = 'Rodapé'
            grp.layer = H.tag('LAVI · Rodapé')
            H.mark(grp, 'baseboard', 'metros' => H.to_m(total))
          end
          barra = H.num(p['barra'], 2.4)
          perda = H.num(p['perda'], 10)
          m = H.to_m(total)
          stats = [['Comprimento', "#{H.br(m)} m"], ["Barras de #{H.br(barra)} m (+#{H.br(perda, 0)}%)", ((m * (1 + perda / 100)) / barra).ceil.to_s]]
          preco = H.num(p['preco'], 0)
          stats << ['Custo estimado', "R$ #{H.br(m * (1 + perda / 100) * preco)}"] if preco > 0
          H.ok("Rodapé criado#{doors.empty? ? '' : " (#{doors.size} linha(s) de porta puladas)"}.", stats: stats)
        end

        # Divide o contorno em trechos contínuos, quebrando nas arestas de porta
        def runs(lp, doors)
          verts = lp.vertices
          edges = lp.edges
          n = edges.size
          skip = edges.map { |e| doors.include?(e) }
          return [[verts.map(&:position), true]] unless skip.any?
          start = skip.index(true)
          out = []
          cur = nil
          n.times do |k|
            i = (start + 1 + k) % n
            if skip[i]
              out << [cur, false] if cur && cur.size >= 2
              cur = nil
            else
              cur ||= [verts[i].position]
              cur << verts[(i + 1) % n].position
            end
          end
          out << [cur, false] if cur && cur.size >= 2
          out
        end

        def piece(ents, pts, closed, off, alt, fr)
          other = G.offset_polyline(pts, off, closed)
          to3 = ->(arr) { arr.map { |q| G.to_3d(q, fr) } }
          g = ents.add_group
          if closed
            a = g.entities.add_face(to3.call(pts))
            b = g.entities.add_face(to3.call(other))
            small = G.area(pts) < G.area(other) ? a : b
            big = small == a ? b : a
            small.erase! if small && small.valid?
            face = big
          else
            face = g.entities.add_face(to3.call(pts + other.reverse))
          end
          return 0.0 unless face && face.valid?
          face.reverse! if face.normal.dot(fr[:n]) < 0
          face.pushpull(alt)
          len = 0.0
          (closed ? pts.size : pts.size - 1).times { |i| len += G.len(G.sub(pts[(i + 1) % pts.size], pts[i])) }
          len
        end

        Registry.register(:baseboard, name: 'Rodapé', tab: :rev, package: :rev, handler: self,
                                      desc: 'Contorna o piso e os pilares, pula as portas e calcula as barras.',
                                      steps: ['Selecione o piso', 'Shift + clique nas linhas das portas', 'Gerar rodapé'])
      end
    end
  end
end
