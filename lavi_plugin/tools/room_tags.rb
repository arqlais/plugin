# Etiqueta de ambiente: clica no piso e escreve nome, área, pé-direito e piso.
# Guarda a ligação com a face para atualizar as áreas depois e montar o quadro de áreas.

module LAVIStudio
  module Plugin
    module Tools
      module RoomTags
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          case action
          when 'place'
            @last_name ||= 'SALA'
            Sketchup.active_model.select_tool(
              Pickers::FacePicker.new('Etiqueta de ambiente: clique no piso de cada ambiente') { |f, tr, pt, _path| place(f, tr, pt, p) }
            )
            H.ok('Clique no piso de cada ambiente. Esc termina.', picking: true)
          when 'update'
            n = H.operation('LAVI · Atualizar etiquetas') { tags.count { |t| refresh(t) } }
            H.ok("#{n} etiqueta(s) atualizada(s).", stats: table_stats)
          when 'list'
            H.ok('Quadro de áreas.', stats: table_stats, rooms: rooms.map { |r| r.values_at(:nome, :area, :pd, :piso, :perim) })
          when 'csv'
            rows = [['Ambiente', 'Área (m²)', 'Perímetro (m)', 'Pé-direito (m)', 'Piso']]
            rs = rooms
            rs.each { |r| rows << [r[:nome], r[:area], r[:perim], r[:pd], r[:piso]] }
            rows << ['TOTAL', rs.sum { |r| r[:area] }]
            path = H.save_csv(rows, 'quadro_de_areas.csv')
            path ? H.ok("Quadro de áreas salvo em #{path}") : H.ok('Cancelado.')
          else
            H.err('Ação desconhecida.')
          end
        end

        def place(face, tr, pt, p)
          unless H.horizontal?(face, tr)
            Dialog.push('result', tool: 'room_tags', ok: false, msg: 'Clique numa face de piso (horizontal).')
            return
          end
          name = @last_name
          if p['perguntar'] != false && p['perguntar'] != 'false'
            res = UI.inputbox(['Nome do ambiente'], [name], 'Etiqueta de ambiente')
            return unless res
            name = res[0].to_s.strip
          else
            name = p['nome'].to_s.strip
          end
          name = 'AMBIENTE' if name.empty?
          @last_name = name
          H.operation('LAVI · Etiqueta de ambiente') do
            g = H.model.active_entities.add_group
            g.name = "Etiqueta · #{name}"
            g.layer = H.tag('LAVI · Ambientes')
            H.mark(g, 'room_tag', 'nome' => name, 'pd_cm' => H.num(p['pd'], 0), 'estilo' => p['estilo'] || '3d',
                                  'alt_cm' => H.num(p['altura'], 12), 'piso' => p['piso'] != false && p['piso'] != 'false',
                                  'maiusc' => p['maiusc'] != false && p['maiusc'] != 'false',
                                  'face_pid' => face.persistent_id, 'face_tr' => tr.to_a, 'pt' => pt.to_a)
            draw(g, face, tr)
          end
          Dialog.push('result', { tool: 'room_tags', ok: true, msg: "#{name} etiquetado." }.merge(stats: table_stats))
        rescue StandardError => e
          Dialog.push('result', tool: 'room_tags', ok: false, msg: e.message)
        end

        def lines(g, face, tr)
          name = g.get_attribute(H::DICT, 'nome').to_s
          name = name.upcase if g.get_attribute(H::DICT, 'maiusc')
          out = [name, "A = #{H.br(H.m2(H.face_area(face, tr)))} m²"]
          pd = g.get_attribute(H::DICT, 'pd_cm').to_f
          out << "PD = #{H.br(pd / 100.0)} m" if pd > 0
          if g.get_attribute(H::DICT, 'piso')
            mat = face.material || face.back_material
            out << "Piso: #{mat.display_name}" if mat
          end
          out
        end

        # Desenha o texto no centro do piso (texto 3D deitado ou rótulo de tela)
        def draw(g, face, tr)
          g.entities.clear!
          center = face_center(face, tr)
          txt = lines(g, face, tr)
          if g.get_attribute(H::DICT, 'estilo') == 'tela'
            g.entities.add_text(txt.join("\n"), center)
          else
            h = H.cm(g.get_attribute(H::DICT, 'alt_cm').to_f.clamp(2, 200))
            y = 0.0
            txt.each_with_index do |line, i|
              size = i.zero? ? h : h * 0.7
              sub = g.entities.add_group
              sub.entities.add_3d_text(line, TextAlignCenter, 'Arial', i.zero?, false, size, 0.0, 0.0, true, 0.0)
              bb = sub.bounds
              y -= size * (i.zero? ? 1.0 : 1.5)
              sub.transform!(Geom::Transformation.translation([-bb.center.x, y - bb.min.y, 0]))
            end
            bb = g.entities.to_a.inject(Geom::BoundingBox.new) { |b, e| b.add(e.bounds) }
            g.entities.transform_entities(Geom::Transformation.translation([center.x - bb.center.x, center.y - bb.center.y, center.z + 0.5.cm]), g.entities.to_a)
            g.material = H.material('LAVI_Texto', '2F3A45')
          end
        end

        def face_center(face, tr)
          fr = G.face_frame(face, tr)
          outer, = G.face_loops_2d(face, tr, fr)
          c = poly_centroid(outer)
          c = G.centroid(outer) unless G.point_in_poly?(c, outer)
          G.to_3d(c, fr)
        end

        # centroide de área (fica dentro em L e formas irregulares na maioria dos casos)
        def poly_centroid(pts)
          a = 0.0
          cx = 0.0
          cy = 0.0
          pts.each_with_index do |p0, i|
            p1 = pts[(i + 1) % pts.size]
            k = p0[0] * p1[1] - p1[0] * p0[1]
            a += k
            cx += (p0[0] + p1[0]) * k
            cy += (p0[1] + p1[1]) * k
          end
          return G.centroid(pts) if a.abs < 1e-9
          [cx / (3 * a), cy / (3 * a)]
        end

        def tags
          H.model.entities.grep(Sketchup::Group).select { |g| H.kind_of(g) == 'room_tag' }
        end

        def face_of(g)
          pid = g.get_attribute(H::DICT, 'face_pid')
          return nil unless pid && H.model.respond_to?(:find_entity_by_persistent_id)
          f = H.model.find_entity_by_persistent_id(pid)
          f.is_a?(Sketchup::Face) && f.valid? ? f : nil
        end

        def tr_of(g)
          a = g.get_attribute(H::DICT, 'face_tr')
          a ? Geom::Transformation.new(a) : IDENTITY
        end

        def refresh(g)
          f = face_of(g)
          return false unless f
          draw(g, f, tr_of(g))
          true
        end

        def rooms
          tags.map do |g|
            f = face_of(g)
            tr = tr_of(g)
            area = f ? H.m2(H.face_area(f, tr)) : 0.0
            perim = 0.0
            if f
              f.outer_loop.edges.each do |e|
                perim += e.start.position.transform(tr).distance(e.end.position.transform(tr)).to_f
              end
            end
            mat = f && (f.material || f.back_material)
            { nome: g.get_attribute(H::DICT, 'nome').to_s, area: area.round(2), perim: H.to_m(perim).round(2),
              pd: (g.get_attribute(H::DICT, 'pd_cm').to_f / 100).round(2), piso: mat ? mat.display_name : '' }
          end.sort_by { |r| r[:nome] }
        end

        def table_stats
          rs = rooms
          stats = rs.first(12).map { |r| [r[:nome], "#{H.br(r[:area])} m²"] }
          stats << ['TOTAL', "#{H.br(rs.sum { |r| r[:area] })} m²"] unless rs.empty?
          stats
        end

        Registry.register(:room_tags, name: 'Ambientes e quadro de áreas', tab: :pres, package: :pres, handler: self,
                                      desc: 'Clica no piso e escreve nome, área e pé-direito; gera o quadro de áreas.',
                                      steps: ['Escolha o estilo', 'Clique no piso de cada ambiente', 'Exporte o quadro de áreas'])
      end
    end
  end
end
