# Rodapé: vários modelos (reto, chanfrado, boleado, frisado, clássico, filete), alturas padrão,
# contorna o piso e os pilares, pula as portas e calcula as barras.

module LAVIStudio
  module Plugin
    module Tools
      module Baseboard
        extend self
        H = Helpers
        G = Geom2
        MODELS = %w[reto chanfrado boleado frisado classico filete].freeze

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'build'
          faces = H.selected_faces.select { |f, tr| H.horizontal?(f, tr) }
          return H.err('Selecione a face do piso. Para pular portas, segure Shift e selecione também as linhas das portas.') if faces.empty?
          doors = H.selection.grep(Sketchup::Edge)
          alt = H.num(p['alt'], 7)
          esp = H.num(p['esp'], 1.5)
          prof = profile(p['modelo'].to_s, alt, esp).map { |u, v| [H.cm(u), H.cm(v)] }
          total = 0.0
          H.operation('lavi · Rodapé') do
            mat = H.material("lavi_Rodape_#{p['cor'].to_s.delete('#')}", p['cor'] || 'FFFFFF')
            grp = H.model.active_entities.add_group
            faces.each do |face, tr|
              fr = G.face_frame(face, tr)
              to3 = ->(q, v) { G.to_3d(q, fr, v) }
              face.loops.each do |lp|
                loop2 = lp.vertices.map { |v| G.to_2d(v.position.transform(tr), fr) }
                # ambiente à esquerda: contorno anti-horário, pilar (furo) horário
                flip = (G.signed_area(loop2) > 0) != lp.outer?
                runs(lp, doors).each do |pts3, closed|
                  pts2 = pts3.map { |v| G.to_2d(v.transform(tr), fr) }
                  pts2.reverse! if flip
                  g = grp.entities.add_group
                  total += Sweep.build(g.entities, pts2, closed, prof, to3)
                end
              end
            end
            grp.material = mat
            grp.name = 'Rodapé'
            grp.layer = H.tag('lavi · Rodapé')
            H.mark(grp, 'baseboard', 'metros' => H.to_m(total), 'modelo' => p['modelo'].to_s, 'altura_cm' => alt)
          end
          barra = H.num(p['barra'], 2.4)
          perda = H.num(p['perda'], 10)
          m = H.to_m(total)
          stats = [['Comprimento', "#{H.br(m)} m"], ["Barras de #{H.br(barra)} m (+#{H.br(perda, 0)}%)", ((m * (1 + perda / 100)) / barra).ceil.to_s],
                   ['Modelo', "#{p['modelo'] || 'reto'} · #{H.br(alt, 1)} × #{H.br(esp, 1)} cm"]]
          H.ok("Rodapé criado#{doors.empty? ? '' : " (#{doors.size} linha(s) de porta puladas)"}.", stats: stats)
        end

        # Perfil em cm: u = da parede para dentro do ambiente, v = do piso para cima
        def profile(model, h, e)
          e = [e, 0.3].max
          h = [h, 1].max
          case model
          when 'chanfrado'
            c = [e * 0.8, h * 0.3].min
            [[0, 0], [e, 0], [e, h - c], [e - c, h], [0, h]]
          when 'boleado'
            r = [e, h / 2.0].min
            [[0, 0], [e, 0]] + Sweep.arc(e - r, h - r, r, 0, 90, 6) + [[0, h]]
          when 'frisado'
            f = [e * 0.25, 0.3].min
            [[0, 0], [e, 0], [e, h * 0.55], [e - f, h * 0.58], [e, h * 0.61], [e, h * 0.78], [e - f, h * 0.81], [e, h * 0.84], [e, h], [0, h]]
          when 'classico'
            b = e * 0.55
            [[0, 0], [e, 0], [e, h * 0.62]] + Sweep.arc(e, h * 0.62 + (e - b), e - b, 270, 180, 5) + [[b, h * 0.9], [b + e * 0.2, h * 0.93], [b, h], [0, h]]
          when 'filete' # rodapé de embutir: filete fino e baixo, quase rente à parede
            [[0, 0], [[e, 0.6].min, 0], [[e, 0.6].min, h], [0, h]]
          else
            [[0, 0], [e, 0], [e, h], [0, h]]
          end
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

        Registry.register(:baseboard, name: 'Rodapé', tab: :rev, package: :rev, handler: self,
                                      desc: 'Modelos reto, chanfrado, boleado, frisado e clássico; pula portas e calcula as barras.',
                                      steps: ['Selecione o piso', 'Shift + clique nas linhas das portas', 'Gerar rodapé'])
      end
    end
  end
end
