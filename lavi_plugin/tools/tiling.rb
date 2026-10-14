# Paginação de piso e de parede: peças com rejunte, amarração, ângulo, recortes e compra

module LAVIStudio
  module Plugin
    module Tools
      module Tiling
        extend self
        H = Helpers
        G = Geom2
        MAX_PIECES = 8000

        # Gera as peças em 2D. Devolve {pieces: [[pts], ...], full:, cut:, area:}
        # outer/holes: polígonos 2D do ambiente; medidas em polegadas
        def layout(outer, holes, p)
          w = H.cm(H.num(p['pc'], 60))   # comprimento da peça (ao longo de u)
          h = H.cm(H.num(p['pl'], 60))   # largura da peça (ao longo de v)
          j = H.mm(H.num(p['rej'], 2))
          ang = H.num(p['ang'], 0) * Math::PI / 180.0
          shift = { 'meia' => 0.5, 'terco' => 1.0 / 3 }[p['padrao']] || 0.0
          room = G.ccw(G.clean(outer))
          c = G.centroid(room)
          rot = room.map { |q| G.rotate(q, -ang, c) }
          hrot = holes.map { |hl| hl.map { |q| G.rotate(q, -ang, c) } }
          x0, y0, x1, y1 = G.bbox(rot)
          sx = w + j
          sy = h + j
          if p['inicio'] == 'centro'
            cx, cy = G.centroid(rot)
            ox = cx - w / 2.0 - ((cx - w / 2.0 - x0) / sx).ceil * sx
            oy = cy - h / 2.0 - ((cy - h / 2.0 - y0) / sy).ceil * sy
          else
            ox = x0
            oy = y0
          end
          cols = ((x1 - ox) / sx).ceil + 2
          rows = ((y1 - oy) / sy).ceil + 1
          raise "Peças demais (#{cols * rows}). Use uma peça maior ou pagine por partes." if cols * rows > MAX_PIECES * 3
          full_area = w * h
          pieces = []
          full = 0
          cut = 0
          rows.times do |r|
            off = (r * shift % 1.0) * sx
            y = oy + r * sy
            (-1...cols).each do |k|
              x = ox + k * sx - off
              next if x + w < x0 || x > x1 || y + h < y0 || y > y1
              tile = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
              poly = G.clip(rot, tile)
              next if poly.size < 3
              a = G.area(poly)
              next if a < full_area * 0.002
              cen = G.centroid(poly)
              next if hrot.any? { |hl| G.point_in_poly?(cen, hl) }
              if a >= full_area * 0.995 then full += 1 else cut += 1 end
              pieces << poly.map { |q| G.rotate(q, ang, c) }
              raise "Peças demais (mais de #{MAX_PIECES}). Use uma peça maior." if pieces.size > MAX_PIECES
            end
          end
          { pieces: pieces, full: full, cut: cut, area: G.area(room) - holes.sum { |hl| G.area(hl) } }
        end

        def summary(res, p)
          area = H.m2(res[:area])
          perda = H.num(p['perda'], 10)
          compra = area * (1 + perda / 100.0)
          caixa = H.num(p['caixa'], 0)
          pc = H.num(p['pc'], 60) * 10
          pl = H.num(p['pl'], 60) * 10
          rej = H.num(p['rej'], 2)
          esp = H.num(p['esp'], 8)
          rejunte = (pc + pl) / (pc * pl) * esp * rej * 1.58 * area
          stats = [['Área', "#{H.br(area)} m²"], ['Peças inteiras', res[:full].to_s], ['Peças recortadas', res[:cut].to_s],
                   ["Comprar (+#{H.br(perda, 0)}%)", "#{H.br(compra)} m²"]]
          stats << ['Caixas', "#{(compra / caixa).ceil} cx de #{H.br(caixa)} m²"] if caixa > 0
          stats << ['Rejunte', "#{H.br(rejunte, 1)} kg"]
          preco = H.num(p['preco'], 0)
          stats << ['Custo estimado', "R$ #{H.br(compra * preco)}"] if preco > 0
          stats
        end

        def handle(action, p, wall)
          return H.err('Ação desconhecida.') unless action == 'build'
          faces = H.selected_faces.select { |f, tr| wall ? H.vertical?(f, tr) : H.horizontal?(f, tr) }
          return H.err(wall ? 'Selecione a(s) face(s) da parede.' : 'Selecione a(s) face(s) do piso.') if faces.empty?
          total = { pieces: [], full: 0, cut: 0, area: 0.0 }
          H.operation(wall ? 'LAVI · Paginação de parede' : 'LAVI · Paginação de piso') do
            mat = H.material("LAVI_Peca_#{p['cor'].to_s.delete('#')}", p['cor'] || 'EDE7E1')
            rej_mat = H.material('LAVI_Rejunte', p['correj'] || 'BDB6AE')
            faces.each do |face, tr|
              fr = G.face_frame(face, tr)
              outer, holes = G.face_loops_2d(face, tr, fr)
              res = layout(outer, holes, p)
              grp = H.model.active_entities.add_group
              e = grp.entities
              res[:pieces].each do |poly|
                pts = poly.map { |q| G.to_3d(q, fr, 0.15.cm) }
                begin
                  f = e.add_face(pts)
                  next unless f
                  f.reverse! if f.normal.dot(fr[:n]) < 0
                  f.material = mat
                rescue ArgumentError
                  next
                end
              end
              base = e.add_group
              bpts = outer.map { |q| G.to_3d(q, fr, 0.05.cm) }
              begin
                bf = base.entities.add_face(bpts)
                if bf
                  bf.reverse! if bf.normal.dot(fr[:n]) < 0
                  bf.material = rej_mat
                end
              rescue ArgumentError
                nil
              end
              grp.name = wall ? 'Paginação de parede' : 'Paginação de piso'
              grp.layer = H.tag(wall ? 'LAVI · Revestimento parede' : 'LAVI · Piso')
              H.mark(grp, wall ? 'wall_tiling' : 'floor_tiling',
                     'area_m2' => H.m2(res[:area]), 'pecas' => res[:full] + res[:cut], 'material' => mat.name)
              total[:full] += res[:full]
              total[:cut] += res[:cut]
              total[:area] += res[:area]
            end
          end
          H.ok("Paginação pronta em #{faces.size} face(s).", stats: summary(total, p))
        end

        module Floor
          def self.handle(a, p) Tiling.handle(a, p, false) end
        end

        module Wall
          def self.handle(a, p) Tiling.handle(a, p, true) end
        end

        Registry.register(:tiling, name: 'Paginação de piso', tab: :rev, package: :rev, handler: Floor,
                                   desc: 'Peças com rejunte, amarração ½ ou ⅓, ângulo, recortes e compra em caixas.',
                                   steps: ['Selecione o piso', 'Escolha peça e rejunte', 'Paginar'])
        Registry.register(:wall_tiling, name: 'Paginação de parede', tab: :rev, package: :rev, handler: Wall,
                                        desc: 'Revestimento de parede com a mesma lógica do piso: azulejo, porcelanato, subway.',
                                        steps: ['Selecione a parede', 'Escolha peça e rejunte', 'Paginar'])
      end
    end
  end
end
