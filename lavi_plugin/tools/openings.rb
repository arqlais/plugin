# Portas, janelas e passagens: clique na parede e o vão é aberto na espessura toda

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
            filler(ents, p['tipo'], p1, u, n, w, h, thick) if p['inserir'] != false && p['inserir'] != 'false'
          end
          Dialog.push('result', tool: 'openings', ok: true,
                                msg: "Vão de #{H.br(H.to_cm(w), 0)} × #{H.br(H.to_cm(h), 0)} cm aberto#{ref} (parede de #{H.br(H.to_cm(thick), 1)} cm).")
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

        def rect(ents, o, u, w, v, h)
          a = u.clone
          a.length = w
          b = v.clone
          b.length = h
          ents.add_face(o, o.offset(a), o.offset(a).offset(b), o.offset(b))
        end

        Registry.register(:openings, name: 'Portas e janelas', tab: :arq, package: :arq, handler: self,
                                     desc: 'Clique na parede para abrir o vão e já colocar a porta ou a janela.',
                                     steps: ['Escolha o tipo e as medidas', 'Clique na parede', 'Esc para terminar'])
      end
    end
  end
end
