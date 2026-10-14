# Portas, janelas e passagens: clique na parede e o vão é aberto na espessura toda.
# Porta com batente, guarnição dos dois lados, folha, abertura desenhada no piso (planta) e etiqueta P1/J1.

module LAVIStudio
  module Plugin
    module Tools
      module Openings
        extend self
        H = Helpers

        DEFAULTS = {
          'porta'   => { larg: 80,  alt: 210, peit: 0 },
          'janela'  => { larg: 120, alt: 120, peit: 110 },
          'vao'     => { larg: 90,  alt: 210, peit: 0 },
          'basculante' => { larg: 60, alt: 60, peit: 160 }
        }.freeze

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'place'
          modo = p['posicao'].to_s
          hint = { 'canto' => 'Vãos: clique na parede (a distância conta da ponta da parede)',
                   'ponto' => 'Vãos: clique no ponto de referência (batente, canto, eixo)' }[modo] ||
                 'Vãos: clique na face da parede onde fica o centro do vão'
          picker = Pickers::FacePicker.new(hint, vcb: modo == 'clique' || modo.empty? ? nil : 'Distância (cm)') do |face, tr, pt, _path|
            q = p.dup
            q['dist'] = picker.typed if picker.typed
            place(face, tr, pt, q)
          end
          Sketchup.active_model.select_tool(picker)
          msg = case modo
                when 'canto' then "Clique na parede: o vão fica a #{H.br(H.num(p['dist'], 60), 0)} cm da ponta #{p['lado'] == 'direita' ? 'direita' : 'esquerda'}. Pode digitar outra distância antes de clicar."
                when 'ponto' then "Clique no ponto de referência: o vão começa a #{H.br(H.num(p['dist'], 60), 0)} cm dele, para a #{p['lado'] == 'direita' ? 'direita' : 'esquerda'}. Pode digitar outra distância antes de clicar."
                else 'Clique na parede, no ponto que será o centro do vão. Pode clicar várias vezes. Esc termina.'
                end
          H.ok(msg, picking: true)
        end

        def place(face, tr, world_pt, p)
          d = DEFAULTS[p['tipo']] || DEFAULTS['porta']
          w = H.cm(H.num(p['larg'], d[:larg]))
          h = H.cm(H.num(p['alt'], d[:alt]))
          sill = H.cm(H.num(p['peit'], d[:peit]))
          unless face.normal.z.abs < 0.05
            Dialog.push('result', tool: 'openings', ok: false, msg: 'Clique numa face vertical de parede.')
            return
          end
          ents = face.parent.entities
          pt = world_pt.transform(tr.inverse)
          n = face.normal
          u = Z_AXIS.cross(n)
          u.normalize!
          base_z = face.vertices.map { |v| v.position.z }.min
          top_z = face.vertices.map { |v| v.position.z }.max
          if base_z + sill + h > top_z + 0.01
            Dialog.push('result', tool: 'openings', ok: false, msg: 'O vão ficou mais alto que a parede. Diminua a altura ou o peitoril.')
            return
          end
          c = face.plane
          pt = pt.project_to_plane(c)
          # posição ao longo da parede: centro no clique, a X cm da ponta da parede, ou a X cm do ponto clicado
          modo = p['posicao'].to_s
          ref = ''
          if %w[canto ponto].include?(modo)
            dist = H.cm(H.num(p['dist'], 60))
            # olhando a parede de frente, u cresce para a direita.
            # Da ponta: "direita" conta da ponta direita para dentro (-u). De um ponto: "direita" = vão à direita (+u).
            dir = modo == 'canto' ? (p['lado'] == 'direita' ? -1 : 1) : (p['lado'] == 'direita' ? 1 : -1)
            us = face.outer_loop.vertices.map { |v| (v.position - ORIGIN).dot(u) }
            pu = (pt - ORIGIN).dot(u)
            start = modo == 'canto' ? (dir > 0 ? us.min : us.max) : pu
            target = start + dir * (dist + w / 2.0)
            pt = pt.offset(u, target - pu)
            if (target - w / 2.0) < us.min - 0.01 || (target + w / 2.0) > us.max + 0.01
              Dialog.push('result', tool: 'openings', ok: false, msg: 'O vão passou da ponta da parede. Diminua a distância.')
              return
            end
            lado = p['lado'] == 'direita' ? 'direita' : 'esquerda'
            ref = modo == 'canto' ? " a #{H.br(H.to_cm(dist), 0)} cm da ponta #{lado}" : " a #{H.br(H.to_cm(dist), 0)} cm do ponto, para a #{lado}"
          end
          bottom = Geom::Point3d.new(pt.x, pt.y, base_z + sill)
          half = u.clone
          half.length = w / 2.0
          up = Geom::Vector3d.new(0, 0, h)
          p1 = bottom.offset(half.reverse)
          p2 = bottom.offset(half)
          p3 = p2.offset(up)
          p4 = p1.offset(up)
          mid = Geom.linear_combination(0.5, p1, 0.5, p3)
          thick = thickness(ents, face, mid)
          unless thick
            Dialog.push('result', tool: 'openings', ok: false, msg: 'Não encontrei o outro lado da parede. A parede precisa ser um volume fechado.')
            return
          end
          H.operation('lavi · Vão') do
            f = ents.add_face(p1, p2, p3, p4)
            f.reverse! if f.normal.dot(n) < 0
            f.pushpull(-thick)
            if p['inserir'] != false && p['inserir'] != 'false'
              p['tipo'] == 'porta' ? door(ents, p1, u, n, w, h, thick, p) : filler(ents, p['tipo'], p1, u, n, w, h, thick)
            end
            @code = label(ents, p, p1, u, n, w, h, sill, thick) if %w[porta janela basculante].include?(p['tipo'].to_s) && p['etiqueta'] != false && p['etiqueta'] != 'false'
          end
          Dialog.push('result', tool: 'openings', ok: true,
                                msg: "#{@code ? @code + ' · ' : ''}Vão de #{H.br(H.to_cm(w), 0)} × #{H.br(H.to_cm(h), 0)} cm aberto#{ref} (parede de #{H.br(H.to_cm(thick), 1)} cm).")
          @code = nil
        rescue StandardError => e
          Dialog.push('result', tool: 'openings', ok: false, msg: e.message)
        end

        # Distância até a face paralela do outro lado da parede
        def thickness(ents, face, pt)
          n = face.normal
          best = nil
          ents.grep(Sketchup::Face).each do |f|
            next if f == face
            next unless f.normal.dot(n).abs > 0.99 # aceita face do outro lado mesmo se estiver invertida
            proj = pt.project_to_plane(f.plane)
            dist = pt.distance(proj)
            next if dist < 0.01
            dir = proj - pt
            next unless dir.dot(n) < 0
            cls = f.classify_point(proj)
            next unless [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(cls)
            best = dist if best.nil? || dist < best
          end
          best
        end

        # Folha de porta ou vidro de janela, no meio da espessura
        def filler(ents, tipo, p1, u, n, w, h, thick)
          return if tipo == 'vao'
          grp = ents.add_group
          e = grp.entities
          back = n.reverse
          if tipo == 'porta'
            leaf = 3.5.cm
            gap = 0.5.cm
            o = p1.offset(back, (thick - leaf) / 2.0).offset(u, gap)
            ww = w - 2 * gap
            hh = h - gap
            face = rect(e, o, u, ww, Z_AXIS, hh)
            face.pushpull(face.normal.dot(back) > 0 ? leaf : -leaf)
            grp.material = H.material('lavi_Porta', 'B98B62')
            grp.name = 'Porta'
            H.mark(grp, 'door', 'larg_cm' => H.to_cm(w), 'alt_cm' => H.to_cm(h))
          else
            frame = 4.cm
            depth = 5.cm
            o = p1.offset(back, (thick - depth) / 2.0)
            outer = rect(e, o, u, w, Z_AXIS, h)
            inner_o = o.offset(u, frame).offset(Z_AXIS, frame)
            inner = rect(e, inner_o, u, w - 2 * frame, Z_AXIS, h - 2 * frame)
            inner.erase! if inner && inner.valid?
            outer.pushpull(outer.normal.dot(back) > 0 ? depth : -depth)
            gl = e.add_group
            go = inner_o.offset(back, depth / 2.0)
            gf = rect(gl.entities, go, u, w - 2 * frame, Z_AXIS, h - 2 * frame)
            gf.pushpull(0.6.cm)
            gl.material = H.material('lavi_Vidro', 'BFD9E6', 0.35)
            grp.material = H.material('lavi_Esquadria', '3E4B57')
            grp.name = 'Janela'
            H.mark(grp, 'window', 'larg_cm' => H.to_cm(w), 'alt_cm' => H.to_cm(h))
          end
          grp.layer = H.tag('lavi · Esquadrias')
        end

        # caixa alinhada à parede: de o, a ao longo de u, b ao longo de v e c ao longo de d
        def box(ents, o, u, a, v, b, d, c)
          f = rect(ents, o, u, a, v, b)
          return unless f
          f.pushpull(f.normal.dot(d) > 0 ? c : -c)
        end

        # porta completa: batente na espessura da parede, guarnição dos dois lados, folha e abertura na planta
        def door(ents, p1, u, n, w, h, thick, p)
          back = n.reverse
          grp = ents.add_group
          e = grp.entities
          wood = H.material("lavi Porta #{p['cor_porta'].to_s.delete('#')}", p['cor_porta'] || 'B98B62')
          bat = p['batente'] != false && p['batente'] != 'false' ? H.cm([H.num(p['bat_larg'], 3), 0.5].max) : 0
          if bat > 0
            g = e.add_group
            box(g.entities, p1, u, bat, Z_AXIS, h, back, thick)
            box(g.entities, p1.offset(u, w - bat), u, bat, Z_AXIS, h, back, thick)
            box(g.entities, p1.offset(u, bat).offset(Z_AXIS, h - bat), u, w - 2 * bat, Z_AXIS, bat, back, thick)
            g.name = 'Batente'
          end
          if p['guarnicao'] != false && p['guarnicao'] != 'false'
            gl = H.cm([H.num(p['guarn_larg'], 5), 1].max)
            ge = H.cm([H.num(p['guarn_esp'], 1), 0.3].max)
            g = e.add_group
            [[p1, n], [p1.offset(back, thick), back]].each do |o, out|
              box(g.entities, o.offset(u, -gl), u, gl, Z_AXIS, h + gl, out, ge)
              box(g.entities, o.offset(u, w), u, gl, Z_AXIS, h + gl, out, ge)
              box(g.entities, o.offset(Z_AXIS, h), u, w, Z_AXIS, gl, out, ge)
            end
            g.name = 'Guarnição'
          end
          leaf = H.cm([H.num(p['folha_esp'], 3.5), 1].max)
          gap = 0.3.cm
          lw = w - 2 * bat - 2 * gap
          lh = h - bat - gap - 0.8.cm
          dentro = p['abre'].to_s != 'fora'
          o = p1.offset(u, bat + gap).offset(Z_AXIS, 0.8.cm).offset(back, dentro ? 0 : thick - leaf)
          g = e.add_group
          box(g.entities, o, u, lw, Z_AXIS, lh, back, leaf)
          g.name = 'Folha'
          grp.material = wood
          grp.name = 'Porta'
          grp.layer = H.tag('lavi · Esquadrias')
          H.mark(grp, 'door', 'larg_cm' => H.to_cm(w), 'alt_cm' => H.to_cm(h))
          swing(ents, p1, u, n, thick, bat, lw, dentro, p) if p['simbolo'] != false && p['simbolo'] != 'false'
          grp
        end

        # abertura da porta desenhada no piso: folha aberta a 90° e o arco (aparece na planta)
        def swing(ents, p1, u, n, thick, bat, lw, dentro, p)
          side = dentro ? n : n.reverse
          esq = p['dobradica'].to_s != 'direita'
          base = p1.offset(n.reverse, dentro ? 0 : thick).offset(Z_AXIS, 0.1.cm)
          hinge = base.offset(u, esq ? bat : bat + lw + 0.6.cm)
          along = esq ? u : u.reverse
          g = ents.add_group
          ge = g.entities
          tip_open = hinge.offset(side, lw)
          ge.add_line(hinge, tip_open)
          k = 12
          pts = (0..k).map do |i|
            a = Math::PI / 2 * i / k
            v1 = along.clone
            v1.length = lw * Math.cos(a)
            v2 = side.clone
            v2.length = lw * Math.sin(a)
            hinge.offset(v1).offset(v2)
          end
          pts.each_cons(2) { |a, b| ge.add_line(a, b) }
          g.name = 'Abertura da porta'
          g.layer = H.tag('lavi · Abertura em planta')
        end

        # etiqueta P1 / J1 com as medidas, no meio do vão (para a planta)
        def label(ents, p, p1, u, n, w, h, sill, thick)
          porta = p['tipo'] == 'porta'
          key = porta ? 'n_porta' : 'n_janela'
          k = H.model.get_attribute(H::DICT, key, 0).to_i + 1
          H.model.set_attribute(H::DICT, key, k)
          code = "#{porta ? 'P' : 'J'}#{k}"
          txt = "#{code}\n#{H.br(H.to_cm(w), 0)} × #{H.br(H.to_cm(h), 0)}#{porta ? '' : " / #{H.br(H.to_cm(sill), 0)}"}"
          at = p1.offset(u, w / 2.0).offset(n.reverse, thick / 2.0).offset(Z_AXIS, -sill + 0.2.cm)
          t = ents.add_text(txt, at)
          if t
            t.layer = H.tag('lavi · Etiquetas de esquadria')
            t.set_attribute(H::DICT, 'codigo', code) if t.respond_to?(:set_attribute)
          end
          code
        end

        def rect(ents, o, u, w, v, h)
          a = u.clone
          a.length = w
          b = v.clone
          b.length = h
          ents.add_face(o, o.offset(a), o.offset(a).offset(b), o.offset(b))
        end

        Registry.register(:openings, name: 'Portas e janelas', tab: :arq, package: :arq, handler: self,
                                     desc: 'Abre o vão na distância certa e coloca porta com batente e guarnição (abertura na planta e P1) ou janela.',
                                     steps: ['Escolha o tipo e as medidas', 'Clique na parede', 'Esc para terminar'])
      end
    end
  end
end
