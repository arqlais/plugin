# Arredondar, chanfrar e curvar: todas as arestas da peça de uma vez (quinas viram esfera, como
# um cubo arredondado), cantos arredondados ou chanfrados (tampos, mesas, bancadas), bordas
# boleadas em cima/embaixo, e curvar uma peça reta em arco (banco, parede, balcão curvo).
# Funciona em grupos/componentes que são "extrusões" (mesmo desenho embaixo e em cima) e em faces soltas.

module LAVIStudio
  module Plugin
    module Tools
      module Shape
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'apply'
          sel = H.selection.to_a
          items = sel.select { |e| H.instance?(e) } + sel.grep(Sketchup::Face)
          return H.err('Selecione o grupo (tampo, mesa, banco…) ou a face que quer arredondar.') if items.empty?
          modo = %w[tudo cantos bordas curvar].include?(p['modo'].to_s) ? p['modo'].to_s : 'tudo'
          ok = 0
          errs = []
          H.operation("lavi · #{{ 'tudo' => 'Arredondar arestas', 'cantos' => 'Arredondar cantos', 'bordas' => 'Bolear bordas', 'curvar' => 'Curvar' }[modo]}") do
            items.each do |it|
              r = it.is_a?(Sketchup::Face) ? face_corners(it, p) : solid(it, modo, p)
              r.is_a?(String) ? errs << r : ok += 1
            end
          end
          return H.err(errs.first) if ok.zero?
          chanfro = modo == 'tudo' ? p['acab'].to_s == 'chanfro' : H.num(p['seg'], 8).to_i <= 1
          H.ok("#{ok} peça(s) #{{ 'tudo' => 'com todas as arestas ' + (chanfro ? 'chanfradas' : 'arredondadas'), 'cantos' => 'com cantos ' + (H.num(p['seg'], 8).to_i <= 1 ? 'chanfrados' : 'arredondados'), 'bordas' => 'com bordas boleadas', 'curvar' => 'curvadas' }[modo]}." +
               (errs.empty? ? '' : " #{errs.size} não deu: #{errs.first}"), stats: [['Peças', ok.to_s]])
        end

        # ---- todas as arestas (como um cubo de quinas redondas) -----------------
        # A peça precisa ser uma extrusão em qualquer direção (caixa, tampo, puff, prateleira, peça em L).
        # Cada "fatia" paralela às tampas é o desenho original recuado d e com os cantos de fora
        # arredondados com raio r - d: assim as arestas viram cilindro e as quinas viram esfera.
        def all_edges(ents, p)
          pr = prism_any(ents)
          return 'A peça precisa ter duas faces iguais e paralelas (caixa, tampo, puff, peça em L).' unless pr
          return 'A peça tem furo (cuba, passagem): arredonde antes de recortar.' unless pr[:holes].empty?
          chanfro = p['acab'].to_s == 'chanfro'
          seg = chanfro ? 1 : [[H.num(p['seg'], 6).to_i, 2].max, 24].min
          h = pr[:z1] - pr[:z0]
          r = [H.cm([H.num(p['raio'], 2), 0.05].max), h / 2.0 - 0.001].min
          layers = []
          if chanfro
            layers = [[r, pr[:z0]], [0, pr[:z0] + r], [0, pr[:z1] - r], [r, pr[:z1]]]
          else
            (0..seg).each { |k| a = Math::PI / 2 * (1 - k.to_f / seg); layers << [r - r * Math.cos(a), pr[:z0] + r - r * Math.sin(a)] }
            (0..seg).each { |k| a = Math::PI / 2 * k.to_f / seg; layers << [r - r * Math.cos(a), pr[:z1] - r + r * Math.sin(a)] }
          end
          layers = layers.each_with_object([]) { |q, acc| acc << q unless acc.last && (acc.last[1] - q[1]).abs < 1e-6 && (acc.last[0] - q[0]).abs < 1e-6 }
          rings = layers.map { |d, z| [ring(pr[:outer], d, r - d, seg), z] }
          return 'O raio é grande demais para essa peça.' if rings.any? { |l, _| l.nil? }
          tr = pr[:tr]
          to3 = ->(q, z) { Geom::Point3d.new(q[0], q[1], z).transform(tr) }
          rebuild(ents) do |e|
            rings.each_cons(2) do |(la, za), (lb, zb)|
              n = la.size
              n.times { |i| facet(e, [to3.call(la[i], za), to3.call(la[(i + 1) % n], za), to3.call(lb[(i + 1) % n], zb), to3.call(lb[i], zb)]) }
            end
            [rings.first, rings.last].each_with_index do |(l, z), k|
              pts = dedupe3(l.map { |q| to3.call(q, z) })
              next if pts.size < 3
              f = e.add_face(pts)
              next unless f
              out = pr[:axis].clone
              out.reverse! if k.zero?
              f.reverse! if f.normal.dot(out) < 0
            end
            e.grep(Sketchup::Face).each { |x| x.material = pr[:mat] } if pr[:mat]
            unless chanfro
              lim = (90.0 / seg + 3) * Math::PI / 180
              e.grep(Sketchup::Edge).each do |ed|
                fs = ed.faces
                next unless fs.size == 2
                a = fs[0].normal.angle_between(fs[1].normal)
                next if a < 1e-4 || a > lim
                ed.soft = true
                ed.smooth = true
              end
            end
          end
          true
        end

        # desenho recuado d, com cantos de fora arredondados (raio rc) — sempre o mesmo número de pontos
        def ring(poly, d, rc, seg)
          base = d > 1e-9 ? G.offset_polyline(poly, d, true) : poly
          return nil if base.size != poly.size || G.signed_area(base) <= 0
          n = base.size
          out = []
          base.each_with_index do |b, i|
            a = base[i - 1]
            c = base[(i + 1) % n]
            # o desenho recuado não pode virar do avesso
            return nil if G.dot(G.sub(b, a), G.sub(poly[i], poly[i - 1])) <= 0
            u = G.unit(G.sub(a, b))
            v = G.unit(G.sub(c, b))
            ang = Math.acos([[G.dot(u, v), 1].min, -1].max)
            convex = G.cross(G.sub(b, a), G.sub(c, b)) > 0
            if !convex || ang > Math::PI - 0.02 || rc < 1e-9
              (seg + 1).times { out << b }
              next
            end
            tlen = rc / Math.tan(ang / 2)
            return nil if tlen > [G.len(G.sub(a, b)), G.len(G.sub(c, b))].min * 0.5 + 1e-6
            p1 = G.add(b, G.mul(u, tlen))
            p2 = G.add(b, G.mul(v, tlen))
            cen = G.add(b, G.mul(G.unit(G.add(u, v)), rc / Math.sin(ang / 2)))
            a1 = Math.atan2(p1[1] - cen[1], p1[0] - cen[0])
            a2 = Math.atan2(p2[1] - cen[1], p2[0] - cen[0])
            dd = a2 - a1
            dd -= 2 * Math::PI while dd > Math::PI
            dd += 2 * Math::PI while dd < -Math::PI
            (0..seg).each { |k| t = a1 + dd * k / seg; out << [cen[0] + rc * Math.cos(t), cen[1] + rc * Math.sin(t)] }
          end
          out
        end

        def dedupe3(pts)
          out = []
          pts.each { |q| out << q unless out.any? { |o| o.distance(q) < 1e-4 } }
          out
        end

        # quadrilátero entre duas fatias (vira triângulo onde a quina fecha num ponto)
        def facet(e, pts)
          q = dedupe3(pts)
          return if q.size < 3
          begin
            e.add_face(q)
          rescue ArgumentError
            [[q[0], q[1], q[2]], [q[0], q[2], q[3]]].each do |t|
              next if t.any?(&:nil?)
              begin
                e.add_face(t)
              rescue ArgumentError
                nil
              end
            end
          end
        end

        # extrusão em qualquer direção: procura duas tampas iguais e paralelas com as laterais em pé
        def prism_any(ents)
          faces = ents.grep(Sketchup::Face)
          return nil if faces.size < 5
          axes = []
          faces.sort_by { |f| [-(f.normal.z.abs > 0.999 ? 1 : 0), -f.area] }.each do |f|
            n = f.normal
            axes << n unless axes.any? { |a| a.parallel?(n) }
          end
          axes.each do |n|
            caps = faces.select { |f| f.normal.parallel?(n) }
            next unless caps.size == 2
            next unless faces.all? { |f| caps.include?(f) || f.normal.dot(n).abs < 1e-3 }
            next if (caps[0].area - caps[1].area).abs > caps[0].area * 0.01
            org = caps[0].vertices[0].position
            zax = n.clone
            zax.normalize!
            # tampa de baixo = a que fica atrás no sentido do eixo
            bot, top = caps.sort_by { |f| (f.vertices[0].position - org).dot(zax) }
            v0 = bot.outer_loop.vertices
            xax = v0[1].position - v0[0].position
            xax.normalize!
            yax = zax.cross(xax)
            tr = Geom::Transformation.axes(bot.vertices[0].position, xax, yax, zax)
            inv = tr.inverse
            to2 = ->(l) { G.clean(l.vertices.map { |v| q = v.position.transform(inv); [q.x, q.y] }) }
            z1 = top.vertices[0].position.transform(inv).z
            next if z1.abs < 1e-3
            return { outer: G.ccw(to2.call(bot.outer_loop)), holes: bot.loops.reject(&:outer?).map { |l| to2.call(l) },
                     z0: 0.0, z1: z1, tr: tr, axis: zax, mat: (bot.material || top.material) }
          end
          nil
        end

        # ---- leitura da peça como extrusão vertical --------------------------
        # devolve {outer:, holes:, z0:, z1:} em coordenadas locais, ou nil
        def prism(ents)
          faces = ents.grep(Sketchup::Face)
          hz = faces.select { |f| f.normal.z.abs > 0.999 }
          return nil if hz.size < 2
          bot = hz.min_by { |f| f.vertices[0].position.z }
          top = hz.max_by { |f| f.vertices[0].position.z }
          z0 = bot.vertices[0].position.z
          z1 = top.vertices[0].position.z
          return nil if (z1 - z0).abs < 1e-3 || (bot.area - top.area).abs > bot.area * 0.01
          to2 = ->(l) { G.clean(l.vertices.map { |v| [v.position.x, v.position.y] }) }
          { outer: G.ccw(to2.call(bot.outer_loop)), holes: bot.loops.reject(&:outer?).map { |l| G.ccw(to2.call(l)).reverse },
            z0: z0, z1: z1, mat: (bot.material || top.material) }
        end

        # ---- extrusão alongada no eixo X (para curvar) --------------------------
        def bar_profile(ents)
          faces = ents.grep(Sketchup::Face)
          ends = faces.select { |f| f.normal.x.abs > 0.999 }
          return nil if ends.size < 2
          a = ends.min_by { |f| f.vertices[0].position.x }
          b = ends.max_by { |f| f.vertices[0].position.x }
          return nil if (a.area - b.area).abs > a.area * 0.01
          x0 = a.vertices[0].position.x
          x1 = b.vertices[0].position.x
          prof = a.outer_loop.vertices.map { |v| [v.position.y, v.position.z] }
          { prof: prof, x0: x0, x1: x1, mat: a.material }
        end

        def solid(inst, modo, p)
          inst.make_unique if inst.respond_to?(:make_unique)
          ents = H.entities_of(inst)
          return all_edges(ents, p) if modo == 'tudo'
          if modo == 'curvar'
            bp = bar_profile(ents)
            return 'A peça precisa ser comprida no eixo X (vermelho) e ter as pontas retas para curvar.' unless bp
            rebuild(ents) { |e| bend(e, bp, p) }
            return true
          end
          pr = prism(ents)
          return 'A peça precisa ter a mesma forma embaixo e em cima (como um tampo ou uma caixa).' unless pr
          r = H.cm(H.num(p['raio'], 5))
          seg = [H.num(p['seg'], 8).to_i, 1].max
          if modo == 'cantos'
            outer = fillet(pr[:outer], r, seg, p['quais'].to_s)
            rebuild(ents) { |e| extrude(e, outer, pr[:holes], pr[:z0], pr[:z1], pr[:mat]) }
          else
            return 'A peça tem furo (cuba, passagem): bolear as bordas antes de recortar.' unless pr[:holes].empty?
            cima = p['cima'] != false && p['cima'] != 'false'
            baixo = p['baixo'] == true || p['baixo'] == 'true'
            rmax = (pr[:z1] - pr[:z0]) / (cima && baixo ? 2.0 : 1.0)
            r = [r, rmax - 0.01.cm].min
            return 'O raio é maior que a espessura da peça.' if r <= 0
            rebuild(ents) { |e| rounded_slab(e, pr, r, seg, cima, baixo) }
          end
          true
        end

        def face_corners(face, p)
          return 'Para curvar, selecione um grupo.' if p['modo'].to_s == 'curvar'
          return 'Para arredondar todas as arestas, selecione um grupo ou componente (a peça inteira).' if p['modo'].to_s == 'tudo'
          return 'A face precisa estar deitada.' unless face.normal.z.abs > 0.999
          z = face.vertices[0].position.z
          outer = G.ccw(G.clean(face.outer_loop.vertices.map { |v| [v.position.x, v.position.y] }))
          pts = fillet(outer, H.cm(H.num(p['raio'], 5)), [H.num(p['seg'], 8).to_i, 1].max, p['quais'].to_s)
          ents = face.parent.entities
          mat = face.material
          up = face.normal.z > 0
          face.erase!
          f = ents.add_face(pts.map { |x, y| [x, y, z] })
          f.reverse! if f && (f.normal.z > 0) != up
          f.material = mat if f
          true
        end

        # apaga tudo e redesenha (mantém material e etiqueta do grupo)
        def rebuild(ents)
          old = ents.to_a.select { |e| e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) }
          ents.erase_entities(old) unless old.empty?
          yield ents
        end

        # ---- cantos arredondados/chanfrados de um polígono 2D -------------------
        # quais: '' = todos, 'convexos' = só os de fora, 'retos' = só os de 90°
        def fillet(poly, r, seg, quais = '')
          n = poly.size
          out = []
          poly.each_with_index do |b, i|
            a = poly[i - 1]
            c = poly[(i + 1) % n]
            u = G.unit(G.sub(a, b))
            v = G.unit(G.sub(c, b))
            cosang = [[G.dot(u, v), 1].min, -1].max
            ang = Math.acos(cosang) # ângulo interno entre as arestas
            convex = G.cross(G.sub(b, a), G.sub(c, b)) > 0
            skip = ang > Math::PI - 0.02 || (quais == 'convexos' && !convex) || (quais == 'retos' && (ang - Math::PI / 2).abs > 0.05)
            if skip
              out << b
              next
            end
            # recua o raio se não couber na aresta
            tlen = r / Math.tan(ang / 2)
            maxt = [G.len(G.sub(a, b)), G.len(G.sub(c, b))].min * 0.5
            rr = tlen > maxt ? maxt * Math.tan(ang / 2) : r
            tlen = rr / Math.tan(ang / 2)
            p1 = G.add(b, G.mul(u, tlen))
            p2 = G.add(b, G.mul(v, tlen))
            if seg <= 1
              out << p1 << p2
              next
            end
            bis = G.unit(G.add(u, v))
            cen = G.add(b, G.mul(bis, rr / Math.sin(ang / 2)))
            a1 = Math.atan2(p1[1] - cen[1], p1[0] - cen[0])
            a2 = Math.atan2(p2[1] - cen[1], p2[0] - cen[0])
            d = a2 - a1
            d -= 2 * Math::PI while d > Math::PI
            d += 2 * Math::PI while d < -Math::PI
            (0..seg).each { |k| t = a1 + d * k / seg; out << [cen[0] + rr * Math.cos(t), cen[1] + rr * Math.sin(t)] }
          end
          G.clean(out)
        end

        # prisma vertical com furos
        def extrude(e, outer, holes, z0, z1, mat)
          f = e.add_face(outer.map { |x, y| [x, y, z0] })
          return unless f
          holes.each do |h|
            hf = e.add_face(h.map { |x, y| [x, y, z0] })
            hf.erase! if hf && hf.valid? && !hf.equal?(f)
          end
          f.reverse! if f.normal.z > 0
          f.pushpull(-(z1 - z0))
          e.grep(Sketchup::Face).each { |x| x.material = mat } if mat
        end

        # tampo com bordas boleadas (ou chanfradas com 1 segmento) em cima e/ou embaixo
        def rounded_slab(e, pr, r, seg, cima, baixo)
          outer = pr[:outer]
          z0 = pr[:z0]
          z1 = pr[:z1]
          rings = []
          if baixo
            (0..seg).each { |k| a = Math::PI / 2 * (1 - k.to_f / seg); rings << [r * (1 - Math.cos(a)), z0 + r * (1 - Math.sin(a))] }
          else
            rings << [0, z0]
          end
          if cima
            (0..seg).each { |k| a = Math::PI / 2 * k.to_f / seg; rings << [r * (1 - Math.cos(a)), z1 - r + r * Math.sin(a)] }
          else
            rings << [0, z1]
          end
          rings = rings.each_with_object([]) { |q, acc| acc << q unless acc.last && (acc.last[0] - q[0]).abs < 1e-6 && (acc.last[1] - q[1]).abs < 1e-6 }
          loops = rings.map { |ins, z| [ins.zero? ? outer : G.offset_polyline(outer, ins, true), z] }
          return if loops.any? { |l, _| l.size != outer.size || G.signed_area(l) <= 0 }
          to3 = ->(q, z) { Geom::Point3d.new(q[0], q[1], z) }
          loops.each_cons(2) do |(la, za), (lb, zb)|
            la.each_index { |i| Sweep.quad(e, to3.call(la[i], za), to3.call(la[(i + 1) % la.size], za), to3.call(lb[(i + 1) % lb.size], zb), to3.call(lb[i], zb)) }
          end
          [loops.first, loops.last].each_with_index do |(l, z), k|
            f = e.add_face(l.map { |q| to3.call(q, z) })
            next unless f
            f.reverse! if (f.normal.z > 0) == k.zero?
          end
          e.grep(Sketchup::Face).each { |x| x.material = pr[:mat] } if pr[:mat]
        end

        # curva a peça (comprida em X) num arco de raio R, para a esquerda ou para a direita
        def bend(e, bp, p)
          len = bp[:x1] - bp[:x0]
          r = H.cm([H.num(p['raio_curva'], 300), 10].max)
          seg = [H.num(p['seg_curva'], 24).to_i, 3].max
          sgn = p['sentido'] == 'direita' ? -1 : 1
          ys = bp[:prof].map(&:first)
          yref = sgn > 0 ? ys.max : ys.min # o raio é medido pela borda de dentro da curva
          path = (0..seg).map do |k|
            t = len / r * k / seg
            [bp[:x0] + r * Math.sin(t), yref + sgn * (r - r * Math.cos(t))]
          end
          # perfil: u = quanto o ponto fica à esquerda do caminho, v = altura
          prof = bp[:prof].map { |y, z| [y - yref, z] }
          Sweep.build(e, path, false, prof, ->(q, v) { Geom::Point3d.new(q[0], q[1], v) })
          e.grep(Sketchup::Face).each { |x| x.material = bp[:mat] } if bp[:mat]
        end

        Registry.register(:shape, name: 'Arredondar, chanfrar e curvar', tab: :base, package: :base, handler: self,
                                  desc: 'Arredonda ou chanfra todas as arestas da peça, cantos, bordas, e curva peças em arco.',
                                  steps: ['Selecione o grupo ou a face', 'Escolha raio e acabamento', 'Aplicar'])
      end
    end
  end
end
