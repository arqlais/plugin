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
                  H.operation('LAVI · Escada') { build(pts[0], pts[1], c, p) }
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
            grp.material = H.material('LAVI_Madeira', 'A0754E')
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
            grp.material = H.material('LAVI_Concreto', 'C9C6C0')
          end
          if p['corrimao'] != false && p['corrimao'] != 'false'
            hc = 90.cm
            s = 4.cm
            y0 = w - 6.cm
            len = (n - 1) * pz
            rail = ents.add_group
            f = rail.entities.add_face([0, y0, e + hc], [len, y0, n * e + hc], [len, y0, n * e + hc + s], [0, y0, e + hc + s])
            f.pushpull(f.normal.y > 0 ? s : -s)
            rail.material = H.material('LAVI_Metal', '2F3A45')
            rail.name = 'Corrimão'
          end
          grp.transform!(tr)
          grp.name = 'Escada'
          grp.layer = H.tag('LAVI · Escadas')
          H.mark(grp, 'stairs', 'degraus' => n)
        end

        Registry.register(:stairs, name: 'Escada', tab: :arq, package: :arq, handler: self,
                                   desc: 'Calcula degraus pela fórmula de Blondel e desenha maciça ou flutuante.',
                                   steps: ['Informe o pé-direito', 'Confira o conforto', 'Clique início e direção'])
      end
    end
  end
end
