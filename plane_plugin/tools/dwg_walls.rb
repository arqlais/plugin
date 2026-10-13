# DWG → Paredes: lê as linhas de uma planta importada, encontra pares paralelos
# (as duas faces de cada parede), levanta as paredes e coloca verga/peitoril nos vãos.

module PlaneLA
  module Plugin
    module Tools
      module DwgWalls
        extend self
        H = Helpers
        G = Geom2
        WINDOW_RX = /jan|janela|window|win|esq|caixilho/i

        def handle(action, p)
          return H.err('Ação desconhecida.') unless %w[analyze build].include?(action)
          segs = collect_segments(H.selection.to_a, IDENTITY)
          return H.err('Selecione as linhas da planta importada (pode selecionar o bloco inteiro do DWG).') if segs.size < 2
          min_len = H.cm(H.num(p['minlen'], 10))
          segs.reject! { |s| G.len(G.sub(s[:b], s[:a])) < min_len }
          segs = merge_collinear(segs)
          walls = pair(segs, H.cm(H.num(p['espmin'], 8)), H.cm(H.num(p['espmax'], 30)), min_len)
          gaps = find_gaps(walls, H.cm(H.num(p['vaomin'], 50)), H.cm(H.num(p['vaomax'], 400)), segs)
          stats = [['Linhas lidas', segs.size.to_s], ['Paredes', walls.size.to_s],
                   ['Portas/passagens', gaps.count { |g| !g[:window] }.to_s], ['Janelas', gaps.count { |g| g[:window] }.to_s]]
          return H.ok('Análise pronta. Se os números fizerem sentido, clique em Levantar paredes.', stats: stats) if action == 'analyze'
          return H.err('Não encontrei pares de linhas paralelas na faixa de espessura informada.') if walls.empty?
          z = H.cm(H.num(p['z'], 0))
          H.operation('Planê · DWG → Paredes') { build(walls, gaps, z, p) }
          H.ok("#{walls.size} paredes levantadas e #{gaps.size} vãos tratados.", stats: stats)
        end

        # Segmentos 2D (coordenadas do modelo) com a camada de origem
        def collect_segments(ents, tr)
          out = []
          ents.each do |e|
            if e.is_a?(Sketchup::Edge)
              a = e.start.position.transform(tr)
              b = e.end.position.transform(tr)
              out << { a: [a.x.to_f, a.y.to_f], b: [b.x.to_f, b.y.to_f], layer: e.layer ? e.layer.name : '' }
            elsif H.instance?(e)
              name = e.respond_to?(:definition) ? e.definition.name : ''
              sub = collect_segments(H.entities_of(e).to_a, tr * e.transformation)
              if name =~ WINDOW_RX || (e.layer && e.layer.name =~ WINDOW_RX)
                sub.each { |s| s[:layer] = 'janela' }
              end
              out.concat(sub)
            end
          end
          out
        end

        # Junta segmentos colineares que se tocam ou se sobrepõem (limpa DWG picotado)
        def merge_collinear(segs, tol = 0.05)
          groups = {}
          segs.each do |s|
            d = G.unit(G.sub(s[:b], s[:a]))
            d = G.mul(d, -1) if d[0] < -1e-9 || (d[0].abs < 1e-9 && d[1] < 0)
            n = G.left(d)
            off = G.dot(n, s[:a])
            key = [(Math.atan2(d[1], d[0]) * 1000).round, (off / tol).round, s[:layer] =~ WINDOW_RX ? 1 : 0]
            (groups[key] ||= []) << [s, d]
          end
          out = []
          groups.each_value do |list|
            d = list[0][1]
            ivs = list.map do |s, _|
              t = [G.dot(d, s[:a]), G.dot(d, s[:b])].sort
              [t[0], t[1], s]
            end.sort_by { |iv| iv[0] }
            cur = nil
            ivs.each do |t0, t1, s|
              if cur && t0 <= cur[1] + tol
                cur[1] = [cur[1], t1].max
              else
                out << finish(cur, d) if cur
                cur = [t0, t1, s]
              end
            end
            out << finish(cur, d) if cur
          end
          out
        end

        def finish(cur, d)
          t0, t1, s = cur
          n = G.left(d)
          off = G.dot(n, s[:a])
          base = G.mul(n, off)
          { a: G.add(base, G.mul(d, t0)), b: G.add(base, G.mul(d, t1)), layer: s[:layer] }
        end

        def pair(segs, esp_min, esp_max, min_len)
          cands = []
          segs.each_with_index do |s, i|
            next if s[:layer] =~ WINDOW_RX
            d = G.unit(G.sub(s[:b], s[:a]))
            n = G.left(d)
            segs.each_with_index do |q, j|
              next if j <= i || q[:layer] =~ WINDOW_RX
              dq = G.unit(G.sub(q[:b], q[:a]))
              next if G.cross(d, dq).abs > 0.01
              dist = G.dot(n, G.sub(q[:a], s[:a]))
              next if dist.abs < esp_min || dist.abs > esp_max
              a0, a1 = [G.dot(d, s[:a]), G.dot(d, s[:b])].sort
              b0, b1 = [G.dot(d, q[:a]), G.dot(d, q[:b])].sort
              o0 = [a0, b0].max
              o1 = [a1, b1].min
              next if o1 - o0 < min_len
              lo = [a0, b0].min
              hi = [a1, b1].max
              s0 = o0 - lo <= esp_max * 1.05 ? lo : o0
              s1 = hi - o1 <= esp_max * 1.05 ? hi : o1
              cands << { i: i, j: j, d: d, n: n, base: s[:a], t0: s0, t1: s1, o0: o0, o1: o1, dist: dist }
            end
          end
          covered = Hash.new { |h, k| h[k] = [] }
          walls = []
          cands.sort_by { |c| c[:dist].abs }.each do |c|
            next if covered_frac(covered[c[:i]], c[:o0], c[:o1]) > 0.5
            next if covered_frac(covered[c[:j]], c[:o0], c[:o1]) > 0.5
            covered[c[:i]] << [c[:o0], c[:o1]]
            covered[c[:j]] << [c[:o0], c[:o1]]
            walls << c
          end
          walls
        end

        def covered_frac(list, t0, t1)
          len = t1 - t0
          return 1.0 if len <= 0
          sum = list.sum { |a, b| [[b, t1].min - [a, t0].max, 0].max }
          sum / len
        end

        # Retângulo da parede em 2D
        def rect(w)
          base0 = G.sub(w[:base], G.mul(w[:d], G.dot(w[:d], w[:base])))
          p0 = G.add(base0, G.mul(w[:d], w[:t0]))
          p1 = G.add(base0, G.mul(w[:d], w[:t1]))
          off = G.mul(w[:n], w[:dist])
          [p0, p1, G.add(p1, off), G.add(p0, off)]
        end

        # Vãos = espaços entre paredes alinhadas na mesma linha e mesma espessura
        def find_gaps(walls, gmin, gmax, segs)
          lines = {}
          walls.each do |w|
            d = w[:d]
            d = G.mul(d, -1) if d[0] < -1e-9 || (d[0].abs < 1e-9 && d[1] < 0)
            n = G.left(d)
            r = rect(w)
            offs = r.map { |q| G.dot(n, q) }
            key = [(Math.atan2(d[1], d[0]) * 100).round, (offs.min / 1.0).round, (offs.max / 1.0).round]
            ts = r.map { |q| G.dot(d, q) }
            (lines[key] ||= []) << { t0: ts.min, t1: ts.max, d: d, n: n, o0: offs.min, o1: offs.max }
          end
          gaps = []
          win_pts = segs.select { |s| s[:layer] =~ WINDOW_RX }.map { |s| G.mul(G.add(s[:a], s[:b]), 0.5) }
          lines.each_value do |list|
            list.sort_by! { |x| x[:t0] }
            list.each_cons(2) do |a, b|
              g = b[:t0] - a[:t1]
              next if g < gmin || g > gmax
              poly = [[a[:t1], a[:o0]], [b[:t0], a[:o0]], [b[:t0], a[:o1]], [a[:t1], a[:o1]]].map do |t, o|
                G.add(G.mul(a[:d], t), G.mul(a[:n], o))
              end
              window = win_pts.any? { |pt| G.point_in_poly?(pt, poly) }
              gaps << { poly: poly, window: window }
            end
          end
          gaps
        end

        def build(walls, gaps, z, p)
          alt = H.cm(H.num(p['alt'], 280))
          h_door = H.cm(H.num(p['altporta'], 210))
          sill = H.cm(H.num(p['peit'], 110))
          h_win_top = H.cm(H.num(p['altjanela'], 210))
          ents = H.model.active_entities
          root = ents.add_group
          root.name = 'Paredes (DWG)'
          mat = H.material('PLN_Parede', 'F2F0EC')
          walls.each { |w| box(root.entities, rect(w), z, alt, mat, 'Parede') }
          if p['vergas'] != false && p['vergas'] != 'false'
            gaps.each do |g|
              top = g[:window] ? h_win_top : h_door
              box(root.entities, g[:poly], z + top, alt - top, mat, 'Verga') if alt - top > 0.5.cm
              box(root.entities, g[:poly], z, sill, mat, 'Peitoril') if g[:window] && sill > 0
            end
          end
          root.layer = H.tag('Planê · Paredes')
          H.mark(root, 'wall', 'alt_cm' => H.to_cm(alt))
        end

        def box(ents, poly, z, h, mat, name)
          return if h <= 0
          g = ents.add_group
          f = g.entities.add_face(poly.map { |q| Geom::Point3d.new(q[0], q[1], z) })
          return g.erase! unless f
          f.reverse! if f.normal.z < 0
          f.pushpull(h)
          g.material = mat
          g.name = name
          H.mark(g, 'wall') if name == 'Parede'
          g
        end

        Registry.register(:dwg_walls, name: 'DWG → Paredes', tab: :arq, package: :arq, handler: self,
                                      desc: 'Transforma a planta importada do AutoCAD em paredes 3D com vergas e peitoris.',
                                      steps: ['Importe o DWG e selecione as linhas', 'Clique em Analisar', 'Clique em Levantar paredes'])
      end
    end
  end
end
