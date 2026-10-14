# Escada reta, em L, em U ou caracol, calculada pela fórmula de Blondel (2e + p entre 63 e 64 cm),
# com guarda-corpo (corrimão, vidro, montantes, cabos ou mureta).

module LAVIStudio
  module Plugin
    module Tools
      module Stairs
        extend self
        H = Helpers

        def calc(p)
          alt = H.num(p['alt'], 280)
          alvo = H.num(p['espelho'], 17.5)
          n = [(alt / alvo).round, 2].max
          e = alt / n
          piso = (64 - 2 * e).clamp(25.0, 32.0)
          blondel = 2 * e + piso
          comp = (n - 1) * piso
          avisos = []
          avisos << 'Espelho acima de 18,5 cm: escada cansativa.' if e > 18.5
          avisos << 'Espelho abaixo de 16 cm: degraus baixos demais.' if e < 16
          avisos << 'Blondel fora de 63–64 cm: passo desconfortável.' unless blondel.between?(62.5, 64.5)
          { n: n, e: e, piso: piso, blondel: blondel, comp: comp, avisos: avisos,
            angulo: Math.atan2(e, piso) * 180 / Math::PI }
        end

        def handle(action, p)
          c = calc(p)
          stats = [['Degraus', c[:n].to_s], ['Espelho', "#{H.br(c[:e], 1)} cm"], ['Piso', "#{H.br(c[:piso], 1)} cm"],
                   ['Blondel', "#{H.br(c[:blondel], 1)} cm"], ['Comprimento', "#{H.br(c[:comp] / 100.0)} m"],
                   ['Inclinação', "#{H.br(c[:angulo], 0)}°"]]
          case action
          when 'calc'
            H.ok(c[:avisos].empty? ? 'Escada confortável.' : c[:avisos].join(' '), stats: stats, warn: !c[:avisos].empty?)
          when 'place'
            Sketchup.active_model.select_tool(
              Pickers::PointPicker.new('Escada: clique o início e depois a direção de subida', max: 2) do |pts, _closed|
                begin
                  H.operation('lavi · Escada') { build(pts[0], pts[1], c, p) }
                  Dialog.push('result', tool: 'stairs', ok: true, msg: "Escada com #{c[:n]} degraus criada.", stats: stats)
                rescue StandardError => e
                  Dialog.push('result', tool: 'stairs', ok: false, msg: e.message)
                end
              end
            )
            H.ok('Clique o ponto de início e depois um ponto na direção da subida.', picking: true, stats: stats)
          else
            H.err('Ação desconhecida.')
          end
        end

        FORMAS = %w[reta L U caracol].freeze

        def build(a, b, c, p)
          xdir = Geom::Vector3d.new(b.x - a.x, b.y - a.y, 0)
          raise 'Clique dois pontos diferentes.' unless xdir.valid?
          xdir.normalize!
          ydir = Z_AXIS.cross(xdir)
          tr = Geom::Transformation.axes(Geom::Point3d.new(a.x, a.y, a.z), xdir, ydir, Z_AXIS)
          forma = FORMAS.include?(p['forma'].to_s) ? p['forma'].to_s : 'reta'
          grp = H.model.active_entities.add_group
          ents = grp.entities
          if forma == 'caracol'
            spiral(ents, c, p)
            grp.material = H.material('lavi_Madeira', 'A0754E')
          else
            fl = layout(forma, c, p)
            fl[:flights].each { |f| flight(ents, f, c, p) }
            landing(ents, fl[:landing], p) if fl[:landing]
            guards(ents, p, fl[:sides]) unless fl[:sides].empty?
            grp.material = p['tipo'] == 'flutuante' ? H.material('lavi_Madeira', 'A0754E') : H.material('lavi_Concreto', 'C9C6C0')
          end
          grp.transform!(tr)
          grp.name = forma == 'reta' ? 'Escada' : "Escada #{forma == 'caracol' ? 'caracol' : "em #{forma}"}"
          grp.layer = H.tag('lavi · Escadas')
          H.mark(grp, 'stairs', 'degraus' => c[:n], 'forma' => forma)
        end

        # lances (origem, direção, degraus, altura inicial), patamar e caminhos dos guarda-corpos
        # Coordenadas da escada: x = subida do 1º lance, y = largura (y = 0 é o lado direito de quem sobe).
        def layout(forma, c, p)
          n = c[:n]
          e = c[:e].cm
          pz = c[:piso].cm
          w = H.cm(H.num(p['larg'], 90))
          esq = p['giro'].to_s != 'direita'
          if forma == 'reta'
            f1 = { o: [0, 0], d: [1, 0], k: n, z0: 0 }
            return { flights: [f1], landing: nil, sides: side_paths([f1], nil, forma, esq, e, pz, w, p) }
          end
          k = (n / 2.0).ceil
          l1 = (k - 1) * pz
          zl = k * e
          gap = H.cm([H.num(p['vao_u'], 10), 0].max)
          f1 = { o: [0, 0], d: [1, 0], k: k, z0: 0 }
          if forma == 'L'
            f2 = esq ? { o: [l1 + w, w], d: [0, 1], k: n - k, z0: zl } : { o: [l1, 0], d: [0, -1], k: n - k, z0: zl }
            land = [l1, 0, l1 + w, w, zl]
          else
            f2 = esq ? { o: [l1, 2 * w + gap], d: [-1, 0], k: n - k, z0: zl } : { o: [l1, -gap], d: [-1, 0], k: n - k, z0: zl }
            land = esq ? [l1, 0, l1 + w, 2 * w + gap, zl] : [l1, -(w + gap), l1 + w, w, zl]
          end
          { flights: [f1, f2], landing: land, sides: side_paths([f1, f2], land, forma, esq, e, pz, w, p) }
        end

        def at(f, x, y)
          [f[:o][0] + f[:d][0] * x - f[:d][1] * y, f[:o][1] + f[:d][1] * x + f[:d][0] * y]
        end

        # um lance: maciço (perfil puxado) ou degraus flutuantes, num subgrupo com seu próprio eixo
        def flight(ents, f, c, p)
          k = f[:k]
          return if k < 1
          e = c[:e].cm
          pz = c[:piso].cm
          w = H.cm(H.num(p['larg'], 90))
          g = ents.add_group
          ge = g.entities
          if p['tipo'] == 'flutuante'
            t = H.cm(H.num(p['espdegrau'], 4))
            (k - 1).times do |i|
              x0 = i * pz
              z1 = (i + 1) * e
              fc = ge.add_face([x0, 0, z1 - t], [x0 + pz, 0, z1 - t], [x0 + pz, 0, z1], [x0, 0, z1])
              fc.pushpull(fc.normal.y < 0 ? -w : w)
            end
          else
            slab = H.cm(H.num(p['laje'], 12))
            len = (k - 1) * pz
            pts = [[0, 0]]
            (k - 1).times do |i|
              pts << [i * pz, (i + 1) * e]
              pts << [(i + 1) * pz, (i + 1) * e]
            end
            ang = Math.atan2(k * e, [len, 1e-3].max)
            hv = slab / Math.cos(ang)
            return g.erase! if k < 2
            if f[:z0] > 0
              # lance que sai do patamar: a laje inclinada continua por baixo do patamar
              pts << [len, k * e] << [len, k * e - hv] << [0, -slab]
            else
              pts << [len, k * e] << [len, [k * e - hv, 0].max] << [[hv / Math.tan(ang), len].min, 0]
            end
            pts = pts.each_with_object([]) { |q, acc| acc << q unless acc.last && (acc.last[0] - q[0]).abs < 1e-6 && (acc.last[1] - q[1]).abs < 1e-6 }
            if pts.size >= 3
              fc = ge.add_face(pts.map { |x, z| Geom::Point3d.new(x, 0, z) })
              fc.pushpull(fc.normal.y < 0 ? -w : w) if fc
            end
          end
          o = Geom::Point3d.new(f[:o][0], f[:o][1], f[:z0])
          g.transform!(Geom::Transformation.axes(o, Geom::Vector3d.new(f[:d][0], f[:d][1], 0), Geom::Vector3d.new(-f[:d][1], f[:d][0], 0), Z_AXIS))
          g.name = 'Lance'
        end

        def landing(ents, l, p)
          x0, y0, x1, y1, z = l
          t = p['tipo'] == 'flutuante' ? H.cm(H.num(p['espdegrau'], 4)) : H.cm(H.num(p['laje'], 12))
          g = ents.add_group
          fc = g.entities.add_face([x0, y0, z - t], [x1, y0, z - t], [x1, y1, z - t], [x0, y1, z - t])
          fc.reverse! if fc.normal.z < 0
          fc.pushpull(t)
          g.name = 'Patamar'
        end

        # caminho de cada lado: pontos [x, y, z da linha dos bocéis, z do piso embaixo]
        def side_paths(flights, land, forma, esq, e, pz, w, p)
          tipo = guard_type(p)
          return [] if tipo == 'nenhum'
          lados = { 'direito' => [:dir], 'esquerdo' => [:esq], 'ambos' => %i[dir esq] }[p['lados'].to_s] || [:dir]
          lados.map do |lado|
            yc = lado == :dir ? 3.cm : w - 3.cm
            pts = []
            flights.each_with_index do |f, fi|
              len = (f[:k] - 1) * pz
              # pontos a cada degrau, para o montante pousar no degrau certo
              (0..(f[:k] - 1)).each do |i|
                x = i * pz
                xy = at(f, x, yc)
                pts << [xy[0], xy[1], f[:z0] + e + x * e / pz, f[:z0] + e * (i + 1)]
              end
              next unless fi.zero? && land
              # contorna o patamar pelo lado de fora; pelo lado de dentro passa direto
              outer = (lado == :dir) == esq
              zl = land[4]
              f2 = flights[1]
              if outer
                xf = land[2] - 3.cm
                pts << [xf, at(f, len, yc)[1], zl, zl]
                s2 = at(f2, 0, yc)
                pts << [xf, s2[1], zl, zl] if forma == 'U'
                pts << [s2[0], s2[1], zl, zl] if forma == 'L'
              end
            end
            { lado: lado, pts: pts, tipo: tipo }
          end
        end

        def guard_type(p)
          tipo = p['guarda'].to_s
          tipo = (p['corrimao'] == false || p['corrimao'] == 'false') ? 'nenhum' : 'corrimao' if tipo.empty?
          tipo
        end

        # escada caracol: coluna no centro e degraus em leque (sempre flutuantes)
        def spiral(ents, c, p)
          n = c[:n]
          e = c[:e].cm
          w = H.cm(H.num(p['larg'], 90))
          rc = H.cm([H.num(p['coluna'], 10), 3].max)
          rr = rc + w
          volta = [[H.num(p['volta'], 360), 90].max, 720].min * Math::PI / 180
          sg = p['giro'].to_s == 'direita' ? -1 : 1
          da = volta / (n - 1)
          t = H.cm(H.num(p['espdegrau'], 4))
          arc = ->(r, a0, a1, k) { (0..k).map { |j| a = a0 + (a1 - a0) * j / k; [r * Math.cos(a), sg * r * Math.sin(a)] } }
          (n - 1).times do |i|
            z1 = (i + 1) * e
            a0 = i * da
            a1 = (i + 1) * da
            poly = arc.call(rr, a0, a1, 4) + arc.call(rc, a1, a0, 1)
            fc = ents.add_face(poly.map { |x, y| [x, y, z1 - t] })
            next unless fc
            fc.reverse! if fc.normal.z < 0
            fc.pushpull(t)
          end
          col = ents.add_group
          cf = col.entities.add_face(arc.call(rc, 0, 2 * Math::PI, 16)[0..-2].map { |x, y| [x, y, 0] })
          cf.reverse! if cf.normal.z < 0
          cf.pushpull(n * e)
          col.name = 'Coluna'
          col.material = H.material('lavi_Metal', '2F3A45')
          tipo = guard_type(p)
          return if tipo == 'nenhum'
          rg = rr - 3.cm
          pts = []
          steps = (n - 1) * 2
          (0..steps).each do |j|
            a = volta * j / steps
            pts << [rg * Math.cos(a), sg * rg * Math.sin(a), e + a / da * e, e * ((a / da).floor + 1)]
          end
          guards(ents, p, [{ lado: :dir, pts: pts, tipo: tipo }])
        end

        # Guarda-corpo ao longo de caminhos: corrimão, vidro, montantes, cabos ou mureta.
        # Cada caminho: pontos [x, y, z da linha de apoio, z do piso embaixo do ponto].
        # Também usado pela ferramenta Guarda-corpo (em linhas selecionadas).
        def guards(ents, p, sides, opts = {})
          sides.each do |sd|
            tipo = sd[:tipo]
            pts = sd[:pts]
            next if pts.size < 2
            h = H.cm(H.num(p['gc_alt'], tipo == 'corrimao' ? 90 : 105))
            drop = opts[:drop] || -8.cm
            g = ents.add_group
            g.name = opts[:name] || "Guarda-corpo #{sd[:lado] == :esq ? 'esquerdo' : 'direito'}"
            ge = g.entities
            segs = straight(pts).each_cons(2).reject { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) < 1e-3 }
            case tipo
            when 'corrimao'
              segs.each { |a, b| bar(ge, a, b, h, 4.cm, 4.cm) }
              posts(ge, [pts.first, pts.last], h, 4.cm)
            when 'vidro'
              vid = H.material('lavi_Vidro', 'BFD9E6', 0.35)
              segs.each { |a, b| panel(ge, a, b, drop, h - 2.cm, 1.cm, vid) }
              segs.each { |a, b| bar(ge, a, b, h, 5.cm, 2.cm) } if p['gc_corrimao'] != false && p['gc_corrimao'] != 'false'
            when 'montantes'
              esp = H.cm([H.num(p['mont_esp'], 12), 5].max)
              posts(ge, spaced(pts, esp), h, 2.cm)
              segs.each { |a, b| bar(ge, a, b, h, 5.cm, 4.cm) }
            when 'cabos'
              posts(ge, spaced(pts, 120.cm), h, 4.cm)
              k = [H.num(p['cabos_n'], 5).to_i, 2].max
              k.times { |i| segs.each { |a, b| bar(ge, a, b, 10.cm + (h - 18.cm) * i / (k - 1).to_f, 1.cm, 1.cm) } }
              segs.each { |a, b| bar(ge, a, b, h, 5.cm, 4.cm) }
            when 'mureta'
              t = H.cm(H.num(p['mureta_esp'], 12))
              alv = H.material('lavi_Alvenaria', 'EDEAE4')
              segs.each { |a, b| panel(ge, a, b, opts[:mureta_drop] || -(a[2] - a[3]) - 19.cm, h, t, alv) }
            end
            g.material = H.material('lavi_Metal', '2F3A45') unless tipo == 'mureta'
          end
        end

        # junta trechos alinhados (mesma direção e inclinação): um vidro/corrimão por lance, menos faces
        def straight(pts)
          out = []
          pts.each do |q|
            if out.size >= 2
              a = out[-2]
              b = out[-1]
              d1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
              d2 = [q[0] - b[0], q[1] - b[1], q[2] - b[2]]
              l1 = Math.sqrt(d1.sum { |v| v * v })
              l2 = Math.sqrt(d2.sum { |v| v * v })
              if l1 > 1e-6 && l2 > 1e-6 && d1.zip(d2).sum { |x, y| x * y } / (l1 * l2) > 0.99999
                out[-1] = q
                next
              end
            end
            out << q unless out.last && Math.sqrt((0..2).sum { |i| (out.last[i] - q[i])**2 }) < 1e-6
          end
          out
        end

        # pontos ao longo do caminho a cada 'esp' (sempre inclui as pontas), com z interpolado
        def spaced(pts, esp)
          out = [pts.first]
          acc = 0.0
          pts.each_cons(2) do |a, b|
            l = Math.hypot(b[0] - a[0], b[1] - a[1])
            next if l < 1e-6
            d = esp - acc
            while d < l
              t = d / l
              # o piso embaixo é o do ponto de trás (o degrau onde o montante pousa)
              out << [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3]]
              d += esp
            end
            acc = l - (d - esp)
          end
          out << pts.last
          out.uniq
        end

        def side_vec(a, b)
          dx = b[0] - a[0]
          dy = b[1] - a[1]
          l = Math.hypot(dx, dy)
          [-dy / l, dx / l]
        end

        # barra (corrimão/cabo) de seção a (altura) × b, com o topo z acima da linha de apoio
        def bar(ge, a, b, z, sa, sb)
          s = side_vec(a, b)
          q = ->(pt, dz) { [pt[0] - s[0] * sb / 2, pt[1] - s[1] * sb / 2, pt[2] + dz] }
          f = ge.add_face([q.call(a, z - sa), q.call(b, z - sa), q.call(b, z), q.call(a, z)])
          return unless f
          f.pushpull(f.normal.x * s[0] + f.normal.y * s[1] > 0 ? sb : -sb)
        end

        # placa (vidro/mureta) de z0 a z1 acima da linha de apoio, espessura t
        def panel(ge, a, b, z0, z1, t, mat)
          g = ge.add_group
          s = side_vec(a, b)
          q = ->(pt, dz) { [pt[0] - s[0] * t / 2, pt[1] - s[1] * t / 2, pt[2] + dz] }
          f = g.entities.add_face([q.call(a, z0), q.call(b, z0), q.call(b, z1), q.call(a, z1)])
          f.pushpull(f.normal.x * s[0] + f.normal.y * s[1] > 0 ? t : -t) if f
          g.material = mat
        end

        # montantes verticais quadrados (lado s), do piso embaixo até a altura do guarda-corpo
        def posts(ge, pts, h, s)
          pts.each do |x, y, zb, zf|
            z0 = zf || zb
            z1 = zb + h
            next if z1 - z0 < 1.cm
            f = ge.add_face([x - s / 2, y - s / 2, z0], [x + s / 2, y - s / 2, z0], [x + s / 2, y + s / 2, z0], [x - s / 2, y + s / 2, z0])
            next unless f
            f.reverse! if f.normal.z < 0
            f.pushpull(z1 - z0)
          end
        end

        Registry.register(:stairs, name: 'Escada', tab: :arq, package: :arq, handler: self,
                                   desc: 'Reta, em L, em U ou caracol; maciça ou flutuante; guarda-corpo de vidro, montantes, cabos, mureta ou corrimão.',
                                   steps: ['Informe o pé-direito', 'Confira o conforto', 'Clique início e direção'])
      end
    end
  end
end
