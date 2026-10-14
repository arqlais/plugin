# Escada reta calculada pela fórmula de Blondel (2e + p entre 63 e 64 cm)

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

        def build(a, b, c, p)
          xdir = Geom::Vector3d.new(b.x - a.x, b.y - a.y, 0)
          raise 'Clique dois pontos diferentes.' unless xdir.valid?
          xdir.normalize!
          ydir = Z_AXIS.cross(xdir)
          tr = Geom::Transformation.axes(Geom::Point3d.new(a.x, a.y, a.z), xdir, ydir, Z_AXIS)
          n = c[:n]
          e = c[:e].cm
          pz = c[:piso].cm
          w = H.cm(H.num(p['larg'], 90))
          grp = H.model.active_entities.add_group
          ents = grp.entities
          if p['tipo'] == 'flutuante'
            t = H.cm(H.num(p['espdegrau'], 4))
            (n - 1).times do |i|
              x0 = i * pz
              z1 = (i + 1) * e
              f = ents.add_face([x0, 0, z1 - t], [x0 + pz, 0, z1 - t], [x0 + pz, 0, z1], [x0, 0, z1])
              f.pushpull(f.normal.y < 0 ? -w : w)
            end
            grp.material = H.material('lavi_Madeira', 'A0754E')
          else
            slab = H.cm(H.num(p['laje'], 12))
            pts = [[0, 0]]
            (n - 1).times do |i|
              pts << [i * pz, (i + 1) * e]
              pts << [(i + 1) * pz, (i + 1) * e]
            end
            len = (n - 1) * pz
            pts << [len, n * e]
            ang = Math.atan2(n * e, len)
            hv = slab / Math.cos(ang)
            pts << [len, [n * e - hv, 0].max]
            xs = [hv / Math.tan(ang), len].min
            pts << [xs, 0]
            face = ents.add_face(pts.map { |x, z| Geom::Point3d.new(x, 0, z) })
            face.pushpull(face.normal.y < 0 ? -w : w)
            grp.material = H.material('lavi_Concreto', 'C9C6C0')
          end
          guards(ents, p, n, e, pz, w)
          grp.transform!(tr)
          grp.name = 'Escada'
          grp.layer = H.tag('lavi · Escadas')
          H.mark(grp, 'stairs', 'degraus' => n)
        end

        # Guarda-corpo: corrimão, vidro, montantes, cabos ou mureta, de um lado ou dos dois.
        # Coordenadas locais: x = subida, y = largura (y = 0 é o lado direito de quem sobe), z = altura.
        def guards(ents, p, n, e, pz, w)
          tipo = p['guarda'].to_s
          tipo = (p['corrimao'] == false || p['corrimao'] == 'false') ? 'nenhum' : 'corrimao' if tipo.empty?
          return if tipo == 'nenhum'
          h = H.cm(H.num(p['gc_alt'], tipo == 'corrimao' ? 90 : 105))
          len = (n - 1) * pz
          base = ->(x) { e + x * e / pz } # linha dos bocéis
          lados = { 'direito' => [:dir], 'esquerdo' => [:esq], 'ambos' => %i[dir esq] }[p['lados'].to_s] || [:dir]
          lados.each do |lado|
            g = ents.add_group
            g.name = "Guarda-corpo #{lado == :dir ? 'direito' : 'esquerdo'}"
            ge = g.entities
            # y do eixo do elemento (3 cm para dentro da borda)
            yc = lado == :dir ? 3.cm : w - 3.cm
            case tipo
            when 'corrimao'
              bar(ge, 0, len, base, h, yc, 4.cm, 4.cm)
              posts(ge, [0, len], base, h, yc, 4.cm)
            when 'vidro'
              t = 1.cm
              panel(ge, 0, len, base, -8.cm, h - 2.cm, yc, t, H.material('lavi_Vidro', 'BFD9E6', 0.35))
              bar(ge, 0, len, base, h, yc, 5.cm, 2.cm) if p['gc_corrimao'] != false && p['gc_corrimao'] != 'false'
            when 'montantes'
              esp = H.cm([H.num(p['mont_esp'], 12), 5].max)
              xs = (0..(len / esp).floor).map { |k| k * esp }
              posts(ge, xs, base, h, yc, 2.cm, ->(x) { e * ((x / pz).floor + 1) })
              bar(ge, 0, len, base, h, yc, 5.cm, 4.cm)
            when 'cabos'
              posts(ge, (0..(len / 120.cm).ceil).map { |k| [k * 120.cm, len].min }.uniq, base, h, yc, 4.cm)
              k = [H.num(p['cabos_n'], 5).to_i, 2].max
              k.times { |i| bar(ge, 0, len, base, 10.cm + (h - 18.cm) * i / (k - 1).to_f, yc, 1.cm, 1.cm) }
              bar(ge, 0, len, base, h, yc, 5.cm, 4.cm)
            when 'mureta'
              t = H.cm(H.num(p['mureta_esp'], 12))
              y0 = lado == :dir ? t / 2.0 : w - t / 2.0
              panel(ge, 0, len + pz, base, -e - 2.cm, h, y0, t, H.material('lavi_Alvenaria', 'EDEAE4'))
            end
            g.material = H.material('lavi_Metal', '2F3A45') unless tipo == 'mureta'
          end
        end

        # barra inclinada (corrimão/cabo) com seção a × b, centrada em yc, topo na altura base + z
        def bar(ge, x0, x1, base, z, yc, a, b)
          pts = [[x0, yc - b / 2, base.call(x0) + z - a], [x1, yc - b / 2, base.call(x1) + z - a],
                 [x1, yc - b / 2, base.call(x1) + z], [x0, yc - b / 2, base.call(x0) + z]]
          f = ge.add_face(pts)
          f.pushpull(f.normal.y > 0 ? b : -b) if f
        end

        # placa inclinada (vidro/mureta) de z0 a z1 acima dos bocéis, espessura t centrada em yc
        def panel(ge, x0, x1, base, z0, z1, yc, t, mat)
          g = ge.add_group
          pts = [[x0, yc - t / 2, base.call(x0) + z0], [x1, yc - t / 2, base.call(x1) + z0],
                 [x1, yc - t / 2, base.call(x1) + z1], [x0, yc - t / 2, base.call(x0) + z1]]
          f = g.entities.add_face(pts)
          f.pushpull(f.normal.y > 0 ? t : -t) if f
          g.material = mat
        end

        # montantes verticais quadrados (lado s) nas posições xs, do degrau até a altura do guarda-corpo
        def posts(ge, xs, base, h, yc, s, floor_at = nil)
          xs.each do |x|
            z0 = floor_at ? floor_at.call(x) : base.call(x) - 2.cm
            z1 = base.call(x) + h
            next if z1 - z0 < 1.cm
            f = ge.add_face([x - s / 2, yc - s / 2, z0], [x + s / 2, yc - s / 2, z0], [x + s / 2, yc + s / 2, z0], [x - s / 2, yc + s / 2, z0])
            next unless f
            f.reverse! if f.normal.z < 0
            f.pushpull(z1 - z0)
          end
        end

        Registry.register(:stairs, name: 'Escada', tab: :arq, package: :arq, handler: self,
                                   desc: 'Blondel, maciça ou flutuante, com guarda-corpo de vidro, montantes, cabos, mureta ou só corrimão.',
                                   steps: ['Informe o pé-direito', 'Confira o conforto', 'Clique início e direção'])
      end
    end
  end
end
