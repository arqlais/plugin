# Forro: rebaixado com tabica (junta de 3 cm na parede), cortineiro nas janelas, sanca fechada
# ou aberta, ou só moldura de teto (sem rebaixo). Tudo com medida ajustável.

module LAVIStudio
  module Plugin
    module Tools
      module Ceiling
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'build'
          faces = H.selected_faces.select { |f, tr| H.horizontal?(f, tr) }
          return H.err('Selecione a face do piso do ambiente.') if faces.empty?
          lines = H.selection.grep(Sketchup::Edge)
          tipo = %w[rebaixado sanca moldura].include?(p['tipo'].to_s) ? p['tipo'].to_s : 'rebaixado'
          cort = on?(p['cortineiro']) && tipo != 'moldura'
          return H.err('Para o cortineiro, selecione também (com Shift) a linha do piso junto à janela.') if cort && lines.empty?
          st = Hash.new(0.0)
          H.operation('lavi · Forro') do
            grp = H.model.active_entities.add_group
            faces.each { |face, tr| room(grp.entities, face, tr, tipo, cort, lines, p, st) }
            grp.material = H.material('lavi_Gesso', 'FAFAF8')
            grp.name = { 'rebaixado' => 'Forro', 'sanca' => 'Forro com sanca', 'moldura' => 'Moldura de teto' }[tipo]
            grp.layer = H.tag('lavi · Forro')
            H.mark(grp, 'ceiling', 'area_m2' => H.m2(st[:area]), 'tipo' => tipo)
          end
          a = H.m2(st[:area])
          stats = []
          stats << ['Área de forro', "#{H.br(a)} m²"] << ['Placas 1,20 × 2,40 (+10%)', (a * 1.1 / 2.88).ceil.to_s] if a > 0
          stats << ['Tabica', "#{H.br(H.to_m(st[:tabica]))} m"] if st[:tabica] > 0
          stats << ['Cortineiro', "#{H.br(H.to_m(st[:cort]))} m"] if st[:cort] > 0
          stats << ['Moldura', "#{H.br(H.to_m(st[:moldura]))} m"] if st[:moldura] > 0
          H.ok({ 'rebaixado' => 'Forro criado.', 'sanca' => 'Forro com sanca criado.', 'moldura' => 'Moldura de teto criada.' }[tipo], stats: stats)
        end

        def on?(v) v == true || v == 'true' end

        def room(e, face, tr, tipo, cort, lines, p, st)
          fr = G.face_frame(face, tr)
          outer = G.ccw(G.clean(G.face_loops_2d(face, tr, fr)[0]))
          alt = H.cm(H.num(p['alt'], 260))
          esp = H.cm(H.num(p['esp'], 1.25))
          if tipo == 'moldura'
            s = H.num(p['mold_tam'], 6)
            prof = molding(p['mold_modelo'].to_s, s).map { |u, v| [H.cm(u), H.cm(v)] }
            g = e.add_group
            st[:moldura] += Sweep.build(g.entities, outer, true, prof, ->(q, v) { G.to_3d(q, fr, alt - v) })
            if on?(p['teto'])
              slab(e, outer, alt, esp, fr)
              st[:area] += G.area(outer)
            end
            return
          end
          # recuo de cada lado: tabica (junta na parede) ou cortineiro (na janela)
          tab = on?(p['tabica']) ? H.cm(H.num(p['tab_larg'], 3)) : 0.0
          cl = H.cm(H.num(p['cort_larg'], 15))
          is_cort = (0...outer.size).map { |i| cort && near_line?(outer[i], outer[(i + 1) % outer.size], lines, tr, fr) }
          dist = is_cort.map { |c| c ? cl : tab }
          edge = inset(outer, dist)
          raise 'O recuo ficou maior que o ambiente.' if G.signed_area(edge) <= 0
          # tabica: perfil em L, fundo escuro a 3 cm acima do forro (a sombra da junta)
          if tab > 0
            tp = H.cm(H.num(p['tab_prof'], 3))
            g = e.add_group
            outer.each_index do |i|
              next if is_cort[i]
              a = outer[i]; b = outer[(i + 1) % outer.size]
              a2 = edge[i]; b2 = edge[(i + 1) % outer.size]
              f = g.entities.add_face([a, b, b2, a2].map { |q| G.to_3d(q, fr, alt + tp) }) rescue nil
              st[:tabica] += G.len(G.sub(b, a)) if f
            end
            g.material = H.material('lavi_Tabica', '2F3A44')
            g.name = 'Tabica'
          end
          # cortineiro: espelho vertical na borda do forro e fundo fechando até a parede
          if cort
            ch = H.cm(H.num(p['cort_alt'], 20))
            g = e.add_group
            outer.each_index do |i|
              next unless is_cort[i]
              a = outer[i]; b = outer[(i + 1) % outer.size]
              a2 = edge[i]; b2 = edge[(i + 1) % outer.size]
              g.entities.add_face([a2, b2].map { |q| G.to_3d(q, fr, alt) } + [b2, a2].map { |q| G.to_3d(q, fr, alt + ch) }) rescue nil
              g.entities.add_face([a, b, b2, a2].map { |q| G.to_3d(q, fr, alt + ch) }) rescue nil
              st[:cort] += G.len(G.sub(b, a))
            end
            g.name = 'Cortineiro'
          end
          if tipo == 'sanca'
            larg = H.cm(H.num(p['sanca_larg'], 40))
            desc = H.cm(H.num(p['sanca_desc'], 15))
            inner = G.offset_polyline(edge, larg, true)
            raise 'A sanca é larga demais para este ambiente.' if G.signed_area(inner) <= 0
            ring(e, edge, inner, alt - desc, esp, fr)
            if p['sanca_tipo'] == 'aberta'
              lip = H.cm(H.num(p['sanca_aba'], 5))
              wall(e, inner, alt - desc + esp, lip, fr) # aba virada para cima: a luz sai pela fresta
            else
              wall(e, inner, alt - desc, desc, fr)       # sanca fechada: espelho até o forro de cima
            end
            slab(e, inner, alt, esp, fr)
            st[:area] += G.area(edge) + inner.each_index.sum { |i| G.len(G.sub(inner[(i + 1) % inner.size], inner[i])) } * desc
          else
            slab(e, edge, alt, esp, fr)
            st[:area] += G.area(edge)
          end
        end

        # perfis de moldura de teto em cm: u = da parede para dentro, v = do teto para baixo
        def molding(model, s)
          s = [s, 1].max
          case model
          when 'chanfro' then [[0, 0], [s, 0], [0, s]]
          when 'cove' then [[0, 0], [s, 0]] + Sweep.arc(s, s, s, 270, 180, 8).drop(1)
          when 'degrau' then [[0, 0], [s, 0], [s, s * 0.3], [s * 0.62, s * 0.3], [s * 0.62, s * 0.65], [s * 0.3, s * 0.65], [s * 0.3, s], [0, s]]
          when 'classica'
            [[0, 0], [s, 0], [s, s * 0.15]] + Sweep.arc(s, s * 0.85, s * 0.7, 270, 180, 6).drop(1) + [[s * 0.15, s], [0, s]]
          else [[0, 0], [s, 0], [s, 1.0], [1.0, 1.0], [1.0, s], [0, s]] # reta (cantoneira)
          end
        end

        # a borda do piso coincide com alguma linha selecionada (janela)?
        def near_line?(a, b, lines, tr, fr)
          mid = G.mul(G.add(a, b), 0.5)
          lines.any? do |l|
            p0 = G.to_2d(l.start.position, fr)
            p1 = G.to_2d(l.end.position, fr)
            d = G.sub(p1, p0)
            len2 = G.dot(d, d)
            next false if len2 < 1e-9
            t = G.dot(G.sub(mid, p0), d) / len2
            t >= -0.01 && t <= 1.01 && G.len(G.sub(mid, G.add(p0, G.mul(d, t)))) < 1.cm
          end
        end

        # recua cada lado do contorno pela sua distância (anti-horário: para dentro)
        def inset(poly, dist)
          n = poly.size
          lines = (0...n).map do |i|
            a = poly[i]
            dir = G.unit(G.sub(poly[(i + 1) % n], a))
            [G.add(a, G.mul(G.left(dir), dist[i])), dir]
          end
          (0...n).map do |i|
            l0 = lines[(i - 1) % n]
            l1 = lines[i]
            G.line_intersection(l0[0], l0[1], l1[0], l1[1]) || l1[0]
          end
        end

        def slab(e, poly, z, esp, fr)
          g = e.add_group
          f = g.entities.add_face(poly.map { |q| G.to_3d(q, fr, z) })
          return unless f
          f.reverse! if f.normal.dot(fr[:n]) > 0
          f.pushpull(-esp)
        end

        def ring(e, outer, inner, z, esp, fr)
          g = e.add_group
          a = g.entities.add_face(outer.map { |q| G.to_3d(q, fr, z) })
          b = g.entities.add_face(inner.map { |q| G.to_3d(q, fr, z) })
          b.erase! if b && b.valid?
          return unless a && a.valid?
          a.reverse! if a.normal.dot(fr[:n]) > 0
          a.pushpull(-esp)
        end

        # faixa vertical em volta do contorno (espelho da sanca ou aba)
        def wall(e, poly, z, h, fr)
          g = e.add_group
          poly.each_index do |i|
            a = poly[i]
            b = poly[(i + 1) % poly.size]
            g.entities.add_face(G.to_3d(a, fr, z), G.to_3d(b, fr, z), G.to_3d(b, fr, z + h), G.to_3d(a, fr, z + h)) rescue nil
          end
        end

        Registry.register(:ceiling, name: 'Forro e moldura', tab: :rev, package: :rev, handler: self,
                                    desc: 'Forro rebaixado com tabica e cortineiro, sanca aberta ou fechada, ou só moldura de teto.',
                                    steps: ['Selecione o piso (e a linha da janela)', 'Escolha o tipo e as medidas', 'Gerar'])
      end
    end
  end
end
