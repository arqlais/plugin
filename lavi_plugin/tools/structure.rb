# Pilares e vigas: pilares clicando ou a partir dos quadradinhos do DWG; vigas nas linhas selecionadas
# ou clicando o caminho. Pilares iguais viram cópias do mesmo componente (leve).

module LAVIStudio
  module Plugin
    module Tools
      module Structure
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          case action
          when 'pilar_click'
            pick('Pilares: clique onde vai cada pilar (Enter termina)') { |pts| pilares(pts, p) }
          when 'pilar_faces'
            faces = H.selection.grep(Sketchup::Face)
            return H.err('Selecione as faces dos pilares (os quadradinhos ou círculos da planta).') if faces.empty?
            extrude(faces, p)
          when 'viga_lines'
            paths = Railing.chains(H.selection.to_a)
            return H.err('Selecione as linhas do eixo das vigas.') if paths.empty?
            vigas(paths, p)
          when 'viga_click'
            pick('Viga: clique o caminho (Enter termina)') { |pts, closed| vigas([pts.map { |q| [q.x, q.y, q.z] } + (closed ? [[pts[0].x, pts[0].y, pts[0].z]] : [])], p) }
          else H.err('Ação desconhecida.')
          end
        end

        def pick(hint)
          Sketchup.active_model.select_tool(
            Pickers::PointPicker.new(hint) do |pts, closed|
              Sketchup.active_model.select_tool(nil)
              res = begin
                yield pts, closed
              rescue StandardError => e
                H.err(e.message)
              end
              Dialog.push('result', res.merge(tool: 'structure'))
            end
          )
          H.ok(hint, picking: true)
        end

        def conc
          H.material('lavi Concreto', 'C9C6C0')
        end

        # componente do pilar (reaproveita o mesmo para o mesmo tamanho)
        def pilar_def(p)
          alt = H.cm([H.num(p['alt'], 280), 1].max)
          if p['forma'] == 'redondo'
            r = H.cm([H.num(p['diam'], 30), 1].max) / 2.0
            name = "lavi pilar Ø#{H.br(H.to_cm(2 * r), 0)} × #{H.br(H.to_cm(alt), 0)} cm"
            pts = (0...24).map { |k| a = 2 * Math::PI * k / 24; [r * Math.cos(a), r * Math.sin(a), 0] }
          else
            w = H.cm([H.num(p['larg'], 20), 1].max)
            d = H.cm([H.num(p['prof'], 20), 1].max)
            name = "lavi pilar #{H.br(H.to_cm(w), 0)} × #{H.br(H.to_cm(d), 0)} × #{H.br(H.to_cm(alt), 0)} cm"
            pts = [[-w / 2, -d / 2, 0], [w / 2, -d / 2, 0], [w / 2, d / 2, 0], [-w / 2, d / 2, 0]]
          end
          df = H.model.definitions[name]
          return df if df && df.entities.grep(Sketchup::Face).size > 2
          df ||= H.model.definitions.add(name)
          f = df.entities.add_face(pts)
          f.reverse! if f.normal.z > 0
          f.pushpull(-alt)
          df.entities.grep(Sketchup::Edge).each { |e| e.soft = e.smooth = true if e.faces.size == 2 && e.faces[0].normal.angle_between(e.faces[1].normal) < 0.3 } if p['forma'] == 'redondo'
          df
        end

        def pilares(pts, p)
          return H.err('Clique pelo menos um ponto.') if pts.empty?
          giro = H.num(p['giro'], 0) * Math::PI / 180
          H.operation('lavi · Pilares') do
            d = pilar_def(p)
            pts.each do |q|
              t = Geom::Transformation.translation(Geom::Vector3d.new(q.x, q.y, q.z))
              t *= Geom::Transformation.rotation(ORIGIN, Z_AXIS, giro) if giro != 0
              i = H.model.active_entities.add_instance(d, t)
              i.material = conc
              i.layer = H.tag('lavi · Estrutura')
            end
          end
          H.ok("#{pts.size} pilar(es) criado(s).", stats: [['Pilares', pts.size.to_s], ['Concreto', "#{H.br(volume(p) * pts.size, 2)} m³"]])
        end

        def volume(p)
          alt = H.num(p['alt'], 280) / 100.0
          area = p['forma'] == 'redondo' ? Math::PI * (H.num(p['diam'], 30) / 200.0)**2 : H.num(p['larg'], 20) * H.num(p['prof'], 20) / 10_000.0
          area * alt
        end

        # pilares a partir das faces da planta (cada face vira um pilar com aquele desenho)
        def extrude(faces, p)
          alt = H.cm([H.num(p['alt'], 280), 1].max)
          vol = 0.0
          H.operation('lavi · Pilares do DWG') do
            faces.each do |f|
              g = H.model.active_entities.add_group
              nf = g.entities.add_face(f.outer_loop.vertices.map(&:position))
              next unless nf
              nf.reverse! if nf.normal.z < 0
              nf.pushpull(alt)
              g.material = conc
              g.name = 'Pilar'
              g.layer = H.tag('lavi · Estrutura')
              vol += H.m2(f.area) * H.to_m(alt)
            end
          end
          H.ok("#{faces.size} pilar(es) levantado(s) da planta.", stats: [['Pilares', faces.size.to_s], ['Concreto', "#{H.br(vol, 2)} m³"]])
        end

        # vigas: seção b × h com o topo na altura escolhida (acima da linha), cantos em meia-esquadria
        def vigas(paths, p)
          b = H.cm([H.num(p['vb'], 15), 1].max)
          h = H.cm([H.num(p['vh'], 40), 1].max)
          topo = H.cm(H.num(p['topo'], 280))
          prof = [[-b / 2, topo - h], [b / 2, topo - h], [b / 2, topo], [-b / 2, topo]]
          len = 0.0
          H.operation('lavi · Vigas') do
            paths.each do |path|
              next if path.size < 2
              z = path[0][2]
              closed = path.size > 2 && Math.hypot(path[0][0] - path[-1][0], path[0][1] - path[-1][1]) < 1e-3
              pts2 = path.map { |q| [q[0], q[1]] }
              pts2.pop if closed
              g = H.model.active_entities.add_group
              len += Sweep.build(g.entities, pts2, closed, prof, ->(q, v) { Geom::Point3d.new(q[0], q[1], z + v) })
              g.material = conc
              g.name = 'Viga'
              g.layer = H.tag('lavi · Estrutura')
            end
          end
          H.ok("Viga de #{H.br(H.to_m(len))} m criada.",
               stats: [['Comprimento', "#{H.br(H.to_m(len))} m"], ['Seção', "#{H.br(H.to_cm(b), 0)} × #{H.br(H.to_cm(h), 0)} cm"],
                       ['Concreto', "#{H.br(H.to_m(len) * H.to_m(b) * H.to_m(h), 2)} m³"]])
        end

        Registry.register(:structure, name: 'Pilares e vigas', tab: :arq, package: :arq, handler: self,
                                      desc: 'Pilares clicando ou dos quadradinhos do DWG, vigas nas linhas, com volume de concreto.',
                                      steps: ['Escolha pilar ou viga e o tamanho', 'Clique ou selecione', 'Criar'])
      end
    end
  end
end
