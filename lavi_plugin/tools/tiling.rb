# Paginação de revestimento (piso, parede ou qualquer face):
# 8 padrões, junta, espessura, ponto inicial e giro escolhidos no modelo, texturas variadas,
# estimativa ao vivo e edição de uma paginação já feita.

require 'json'

module LAVIStudio
  module Plugin
    module Tools
      module Tiling
        extend self
        H = Helpers
        G = Geom2
        MAX_PIECES = 15_000
        PATTERNS = %w[horizontal vertical diagonal tijolo damas chevron espinha organica].freeze

        # número pseudoaleatório estável (mesma entrada → mesmo valor), 0..1
        def rnd(a, b, s)
          m = 0xffffffff
          x = (a * 374_761_393 + b * 668_265_263 + s * 2_147_483_647) & m
          x = ((x ^ (x >> 16)) * 0x85ebca6b) & m
          x = ((x ^ (x >> 13)) * 0xc2b2ae35) & m
          (x ^ (x >> 16)) / 4_294_967_296.0
        end

        def rect(x, y, a, b)
          { pts: [[x, y], [x + a, y], [x + a, y + b], [x, y + b]], o: [x, y], ex: [a, 0.0], ey: [0.0, b] }
        end

        # Peça-base de cada padrão: vetores da repetição (t1, t2), peças da célula e giro próprio
        # w = comprimento da peça, h = largura, j = junta (tudo em polegadas)
        def unit(pat, w, h, j, p)
          sx = w + j
          sy = h + j
          case pat
          when 'vertical'
            v = { pts: rect(0, 0, h, w)[:pts], o: [h, 0.0], ex: [0.0, w], ey: [-h, 0.0] }
            { t1: [h + j, 0.0], t2: [0.0, w + j], tiles: [v], base: 0 }
          when 'diagonal'
            { t1: [sx, 0.0], t2: [0.0, sy], tiles: [rect(0, 0, w, h)], base: 45 }
          when 'tijolo'
            shift = p['amarr'] == 'terco' ? 1.0 / 3 : 0.5
            { t1: [sx, 0.0], t2: [sx * shift, sy], tiles: [rect(0, 0, w, h)], base: 0 }
          when 'chevron'
            ca = Math.cos(Math::PI / 4)
            cw = w * ca
            hv = h / ca
            x0 = cw + j
            left = { pts: [[0.0, 0.0], [cw, cw], [cw, cw + hv], [0.0, hv]], o: [0.0, 0.0], ex: [cw, cw], ey: [0.0, hv] }
            right = { pts: [[x0, cw], [x0 + cw, 0.0], [x0 + cw, hv], [x0, cw + hv]], o: [x0, cw], ex: [cw, -cw], ey: [0.0, hv] }
            { t1: [2 * cw + 2 * j, 0.0], t2: [0.0, hv + j / ca], tiles: [left, right], base: 0 }
          when 'espinha'
            hz = rect(0, 0, w, h)
            vt = { pts: rect(0, h + j, h, w)[:pts], o: [h, h + j], ex: [0.0, w], ey: [-h, 0.0] }
            { t1: [h + j, h + j], t2: [w + j, -(w + j)], tiles: [hz, vt], base: -45 }
          else # horizontal, damas
            { t1: [sx, 0.0], t2: [0.0, sy], tiles: [rect(0, 0, w, h)], base: 0 }
          end
        end

        # mantém a parte do polígono convexo onde dot(q, n) <= c
        def halfplane(poly, n, c)
          out = []
          poly.each_with_index do |a, i|
            b = poly[(i + 1) % poly.size]
            da = G.dot(a, n) - c
            db = G.dot(b, n) - c
            out << a if da <= 0
            if (da <= 0) != (db <= 0)
              t = da / (da - db)
              out << [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
            end
          end
          out
        end

        # Pedra orgânica: células de Voronoi em volta de pontos sorteados numa grade
        def stone(a, b, w, h, j, seed)
          site = lambda do |i, k|
            [i * (w + j) + (rnd(i, k, 1 + seed) - 0.5) * 0.7 * w, k * (h + j) + (rnd(i, k, 2 + seed) - 0.5) * 0.7 * h]
          end
          s = site.call(a, b)
          r = 2.5 * [w, h].max
          cell = [[s[0] - r, s[1] - r], [s[0] + r, s[1] - r], [s[0] + r, s[1] + r], [s[0] - r, s[1] + r]]
          (-3..3).each do |di|
            (-3..3).each do |dk|
              next if di.zero? && dk.zero?
              q = site.call(a + di, b + dk)
              n = G.sub(q, s)
              d = G.len(n)
              next if d < 1e-9
              m = G.mul(G.add(s, q), 0.5)
              cell = halfplane(cell, n, G.dot(m, n) - j / 2.0 * d)
              break if cell.size < 3
            end
          end
          return nil if cell.size < 3
          bx0, by0, bx1, by1 = G.bbox(cell)
          { pts: cell, o: [bx0, by0], ex: [bx1 - bx0, 0.0], ey: [0.0, by1 - by0] }
        end

        # Gera as peças em 2D.
        # Devolve {pieces: [{poly:, o:, ex:, ey:, k:, r:}], full:, cut:, area:}
        # outer/holes: polígonos 2D da face; origin: ponto inicial 2D (ou nil); medidas em polegadas
        def layout(outer, holes, p, origin = nil)
          pat = PATTERNS.include?(p['padrao'].to_s) ? p['padrao'].to_s : 'horizontal'
          w = H.cm([H.num(p['pc'], 60), 0.5].max)
          h = H.cm([H.num(p['pl'], 60), 0.5].max)
          seca = p['seca'] == true || p['seca'] == 'true'
          j = seca ? 0.0 : H.mm([H.num(p['rej'], 2), 0].max)
          seed = H.num(p['seed'], 0).to_i
          u = unit(pat, w, h, j, p)
          ang = (H.num(p['ang'], 0) + u[:base]) * Math::PI / 180.0
          room = G.ccw(G.clean(outer))
          c = G.centroid(room)
          rot = room.map { |q| G.rotate(q, -ang, c) }
          hrot = holes.map { |hl| hl.map { |q| G.rotate(q, -ang, c) } }
          x0, y0, x1, y1 = G.bbox(rot)
          o =
            if p['inicio'] == 'ponto' && origin
              G.rotate(origin, -ang, c)
            elsif p['inicio'] == 'centro'
              cx, cy = G.centroid(rot)
              [cx - w / 2.0, cy - h / 2.0]
            else
              [x0, y0]
            end
          t1 = u[:t1]
          t2 = u[:t2]
          t1, t2 = [[w + j, 0.0], [0.0, h + j]] if pat == 'organica'
          det = G.cross(t1, t2)
          ab = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map do |q|
            d = G.sub(q, o)
            [G.cross(d, t2) / det, G.cross(t1, d) / det]
          end
          ext = u[:tiles].flat_map { |t| t[:pts] }.map { |q| G.len(q) }.max + 3 * [w, h].max
          m = (ext / [G.len(t1), G.len(t2)].min).ceil + 1
          amin = ab.map(&:first).min.floor - m
          amax = ab.map(&:first).max.ceil + m
          bmin = ab.map(&:last).min.floor - m
          bmax = ab.map(&:last).max.ceil + m
          if (amax - amin + 1) * (bmax - bmin + 1) > MAX_PIECES * 12
            raise "Peças demais para esta área. Use uma peça maior ou pagine por partes."
          end
          pieces = []
          full = 0
          cut = 0
          (amin..amax).each do |a|
            (bmin..bmax).each do |b|
              base = G.add(o, G.add(G.mul(t1, a), G.mul(t2, b)))
              tiles = pat == 'organica' ? [stone(a, b, w, h, j, seed)].compact : u[:tiles]
              tiles.each_with_index do |t, ti|
                pts = pat == 'organica' ? t[:pts].map { |q| G.add(o, q) } : t[:pts].map { |q| G.add(base, q) }
                bx0, by0, bx1, by1 = G.bbox(pts)
                next if bx1 < x0 || bx0 > x1 || by1 < y0 || by0 > y1
                tile_area = G.area(pts)
                poly = G.clip(rot, pts)
                next if poly.size < 3
                ar = G.area(poly)
                next if ar < tile_area * 0.002
                cen = G.centroid(poly)
                next if hrot.any? { |hl| G.point_in_poly?(cen, hl) }
                if ar >= tile_area * 0.995 then full += 1 else cut += 1 end
                to = pat == 'organica' ? G.add(o, t[:o]) : G.add(base, t[:o])
                pieces << { poly: poly.map { |q| G.rotate(q, ang, c) }, o: G.rotate(to, ang, c),
                            ex: G.rotate(t[:ex], ang), ey: G.rotate(t[:ey], ang),
                            k: (a + b) % 2, r: rnd(a * 3 + ti, b, 9 + seed) }
                raise "Peças demais (mais de #{MAX_PIECES}). Use uma peça maior ou pagine por partes." if pieces.size > MAX_PIECES
              end
            end
          end
          { pieces: pieces, full: full, cut: cut, area: G.area(room) - holes.sum { |hl| G.area(hl) } }
        end

        def summary(res, p)
          area = H.m2(res[:area])
          perda = H.num(p['perda'], 10)
          compra = area * (1 + perda / 100.0)
          caixa = H.num(p['caixa'], 0)
          stats = [['Área revestida', "#{H.br(area)} m²"], ['Peças inteiras', "#{res[:full]} un"],
                   ['Peças recortadas', "#{res[:cut]} un"], ['Total estimado', "#{res[:full] + res[:cut]} un"],
                   ["Comprar (+#{H.br(perda, 0)}%)", "#{H.br(compra)} m²"]]
          stats << ['Caixas', "#{(compra / caixa).ceil} cx de #{H.br(caixa)} m²"] if caixa > 0
          seca = p['seca'] == true || p['seca'] == 'true'
          unless seca
            pc = H.num(p['pc'], 60) * 10
            pl = H.num(p['pl'], 60) * 10
            kg = (pc + pl) / (pc * pl) * H.num(p['esp'], 9) * H.num(p['rej'], 2) * 1.58 * area
            stats << ['Rejunte', "#{H.br(kg, 1)} kg"]
          end
          stats
        end

        # ---- de onde vem a face -------------------------------------------------
        def tiling_group(sel = H.selection.to_a)
          sel.find { |e| e.is_a?(Sketchup::Group) && e.valid? && %w[floor_tiling wall_tiling].include?(H.kind_of(e).to_s) }
        end

        # [[face, transformação, grupo antigo ou nil], ...]
        def targets
          g = tiling_group
          if g
            face = H.model.find_entity_by_persistent_id(g.get_attribute(H::DICT, 'face_pid').to_i) rescue nil
            tr = g.get_attribute(H::DICT, 'face_tr')
            tr = tr ? Geom::Transformation.new(tr) : IDENTITY
            return face && face.valid? ? [[face, tr, g]] : []
          end
          list = H.selected_faces.map { |f, t| [f, t, nil] }
          list = [[@picked[0], @picked[1], nil]] if list.empty? && @picked && @picked[0].valid?
          list
        end

        def origin_2d(fr, p)
          return nil unless p['inicio'] == 'ponto' && p['ox']
          G.to_2d(Geom::Point3d.new(H.num(p['ox']), H.num(p['oy']), H.num(p['oz'])), fr)
        end

        def surface_info
          t = targets
          area = t.sum { |f, tr, _g| H.m2(G.area(G.face_loops_2d(f, tr, G.face_frame(f, tr))[0])) }
          { faces: t.size, area: H.br(area), editing: !tiling_group.nil? }
        end

        # ---- ações --------------------------------------------------------------
        def handle(action, p)
          case action
          when 'surface' then H.ok('', surface: surface_info)
          when 'pick'
            Sketchup.active_model.select_tool(
              Pickers::FacePicker.new('Revestimento: clique na face') do |face, tr, _pt, _path|
                @picked = [face, tr]
                sel = H.selection
                sel.clear
                sel.add(face) if face.parent.entities == H.model.active_entities
                Sketchup.active_model.select_tool(nil)
                Dialog.push('result', tool: 'tiling', ok: true, msg: 'Face escolhida.', surface: surface_info)
              end
            )
            H.ok('Clique na face do piso ou da parede.', picking: true)
          when 'origin'
            Sketchup.active_model.select_tool(
              Pickers::PointPicker.new('Clique onde a primeira peça começa', single: true) do |pts, _c|
                q = pts[0]
                Dialog.push('result', tool: 'tiling', ok: true, msg: 'Ponto inicial escolhido.',
                                      values: { 'inicio' => 'ponto', 'ox' => q.x.to_f, 'oy' => q.y.to_f, 'oz' => q.z.to_f })
              end
            )
            H.ok('Clique no modelo onde a paginação começa (um canto da primeira peça).', picking: true)
          when 'rotate'
            t = targets.first
            return H.err('Selecione antes a face a revestir.') unless t
            Sketchup.active_model.select_tool(
              Pickers::PointPicker.new('Clique dois pontos na direção das peças', max: 2) do |pts, _c|
                fr = G.face_frame(t[0], t[1])
                a = G.to_2d(pts[0], fr)
                b = G.to_2d(pts[1], fr)
                deg = Math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / Math::PI
                deg = (deg % 180).round(1)
                Dialog.push('result', tool: 'tiling', ok: true, msg: "Ângulo de #{H.br(deg, 1)}°.", values: { 'ang' => deg })
              end
            )
            H.ok('Clique dois pontos no modelo seguindo a direção que as peças devem ter.', picking: true)
          when 'add_image'
            path = UI.openpanel('Imagem da peça', '', 'Imagens|*.jpg;*.jpeg;*.png||')
            return H.ok('Cancelado.') unless path
            path = path.dup.force_encoding('UTF-8').tr('\\', '/')
            H.ok('Imagem adicionada.', values: { 'texturas' => (Array(p['texturas']) + [path]).uniq })
          when 'edit'
            g = tiling_group
            return H.err('Selecione uma paginação feita pelo lavi para editar.') unless g
            saved = JSON.parse(g.get_attribute(H::DICT, 'params').to_s) rescue nil
            return H.err('Esta paginação é de uma versão antiga e não guarda as opções.') unless saved
            H.ok('Opções carregadas. Mude o que quiser e clique em Gerar paginação.', values: saved, surface: surface_info)
          when 'estimate'
            t = targets
            return H.ok('', est: nil, surface: surface_info) if t.empty?
            total = run_layouts(t, p).last
            H.ok('', est: summary(total, p), surface: surface_info)
          when 'build' then build(p)
          else H.err('Ação desconhecida.')
          end
        rescue RuntimeError => e
          H.err(e.message)
        end

        def run_layouts(t, p)
          total = { full: 0, cut: 0, area: 0.0 }
          outs = t.map do |face, tr, g|
            fr = G.face_frame(face, tr)
            outer, holes = G.face_loops_2d(face, tr, fr)
            res = layout(outer, holes, p, origin_2d(fr, p))
            total[:full] += res[:full]
            total[:cut] += res[:cut]
            total[:area] += res[:area]
            [face, tr, g, fr, outer, res]
          end
          [outs, total]
        end

        def piece_materials(p)
          texs = Array(p['texturas']).select { |f| File.exist?(f.to_s) }
          return texs.map { |f| texture_material(f) } unless texs.empty?
          mats = [H.material("lavi_Peca_#{p['cor'].to_s.delete('#')}", p['cor'] || 'E9E3DC')]
          mats << H.material("lavi_Peca_#{p['cor2'].to_s.delete('#')}", p['cor2'] || '3E4B57') if p['padrao'] == 'damas'
          mats
        end

        def texture_material(file)
          name = "lavi_#{File.basename(file, '.*')}"
          mat = H.model.materials[name] || H.model.materials.add(name)
          mat.texture = file unless mat.texture
          mat
        end

        def build(p)
          t = targets
          return H.err('Selecione a face do piso ou da parede (ou clique em Selecionar).') if t.empty?
          relevo = p['relevo'] == true || p['relevo'] == 'true'
          rejunte = p['mostrar_rej'] != false && p['mostrar_rej'] != 'false'
          esp = H.mm([H.num(p['esp'], 9), 0.1].max)
          outs = nil
          total = nil
          H.operation('lavi · Paginação') do
            outs, total = run_layouts(t, p)
            mats = piece_materials(p)
            textured = mats.any?(&:texture)
            rej_mat = H.material("lavi_Rejunte_#{p['correj'].to_s.delete('#')}", p['correj'] || 'BDB6AE')
            outs.each do |face, tr, old, fr, outer, res|
              wall = !H.horizontal?(face, tr)
              old.erase! if old && old.valid?
              grp = H.model.active_entities.add_group
              e = grp.entities
              res[:pieces].each do |pc|
                pts = pc[:poly].map { |q| G.to_3d(q, fr, 0.15.cm) }
                begin
                  f = e.add_face(pts)
                  next unless f
                  f.reverse! if f.normal.dot(fr[:n]) < 0
                  mat = mats.size == 1 ? mats[0] : textured ? mats[(pc[:r] * mats.size).floor % mats.size] : mats[pc[:k]]
                  if mat.texture
                    a = G.to_3d(pc[:o], fr, 0.15.cm)
                    b = G.to_3d(G.add(pc[:o], pc[:ex]), fr, 0.15.cm)
                    d = G.to_3d(G.add(pc[:o], pc[:ey]), fr, 0.15.cm)
                    f.position_material(mat, [a, Geom::Point3d.new(0, 0, 1), b, Geom::Point3d.new(1, 0, 1),
                                              d, Geom::Point3d.new(0, 1, 1)], true)
                  else
                    f.material = mat
                  end
                  f.pushpull(esp) if relevo
                rescue ArgumentError
                  next
                end
              end
              if rejunte
                base = e.add_group
                begin
                  bf = base.entities.add_face(outer.map { |q| G.to_3d(q, fr, 0.05.cm) })
                  if bf
                    bf.reverse! if bf.normal.dot(fr[:n]) < 0
                    bf.material = rej_mat
                    # pilares e vãos viram furos no rejunte também
                    G.face_loops_2d(face, tr, fr)[1].each do |hl|
                      hf = base.entities.add_face(hl.map { |q| G.to_3d(q, fr, 0.05.cm) })
                      hf.erase! if hf && hf.valid?
                    end
                  end
                rescue ArgumentError
                  nil
                end
              end
              grp.name = wall ? 'Paginação de parede' : 'Paginação de piso'
              grp.layer = H.tag(wall ? 'lavi · Revestimento parede' : 'lavi · Piso')
              H.mark(grp, wall ? 'wall_tiling' : 'floor_tiling',
                     'area_m2' => H.m2(res[:area]), 'pecas' => res[:full] + res[:cut], 'material' => mats[0].name,
                     'params' => JSON.generate(p.reject { |k, _| k == 'req' }), 'face_pid' => face.persistent_id,
                     'face_tr' => tr.to_a)
              H.selection.clear
              H.selection.add(grp)
            end
          end
          H.ok(t.any? { |x| x[2] } ? 'Paginação atualizada.' : "Paginação pronta em #{t.size} face(s).",
               stats: summary(total, p), surface: surface_info)
        end

        Registry.register(:tiling, name: 'Revestimento', tab: :rev, package: :rev, handler: self,
                                   desc: 'Paginação de piso e parede: 8 padrões, junta, texturas variadas e estimativa ao vivo.',
                                   steps: ['Selecione a face', 'Escolha padrão, peça e posição', 'Gerar paginação'])
      end
    end
  end
end
