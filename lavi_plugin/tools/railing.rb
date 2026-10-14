# Guarda-corpo em qualquer lugar: varanda, mezanino, sacada, borda de laje.
# Usa os mesmos modelos da escada (corrimão, vidro, montantes, cabos, mureta) ao longo das linhas
# selecionadas ou de pontos clicados.

module LAVIStudio
  module Plugin
    module Tools
      module Railing
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          case action
          when 'build'
            paths = chains(H.selection.to_a)
            return H.err('Selecione as linhas (arestas) da borda: da varanda, do mezanino ou da laje.') if paths.empty?
            make(paths, p)
          when 'draw'
            Sketchup.active_model.select_tool(
              Pickers::PointPicker.new('Guarda-corpo: clique os pontos da borda') do |pts, closed|
                Sketchup.active_model.select_tool(nil)
                res = begin
                  path = pts.map { |q| [q.x, q.y, q.z] }
                  path << path.first if closed
                  make([path], p)
                rescue StandardError => e
                  H.err(e.message)
                end
                Dialog.push('result', res.merge(tool: 'railing'))
              end
            )
            H.ok('Clique os pontos da borda. Enter termina.', picking: true)
          else H.err('Ação desconhecida.')
          end
        end

        def make(paths, p)
          tipo = %w[corrimao vidro montantes cabos mureta].include?(p['guarda'].to_s) ? p['guarda'].to_s : 'vidro'
          recuo = H.cm(H.num(p['recuo'], 0))
          lado = p['lado'].to_s == 'direita' ? -1 : 1
          total = 0.0
          H.operation('lavi · Guarda-corpo') do
            paths.each do |path|
              next if path.size < 2
              closed = path.size > 2 && dist3(path.first, path.last) < 1e-3
              pts = path.dup
              pts.pop if closed
              if recuo > 0
                xy = G.offset_polyline(pts.map { |q| [q[0], q[1]] }, recuo * lado, closed)
                pts = xy.each_with_index.map { |q, i| [q[0], q[1], pts[i][2]] } if xy.size == pts.size
              end
              pts << pts.first if closed
              total += pts.each_cons(2).sum { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }
              side = { lado: :dir, tipo: tipo, pts: pts.map { |x, y, z| [x, y, z, z] } }
              Stairs.guards(H.model.active_entities, p, [side], drop: 0, mureta_drop: 0, name: 'Guarda-corpo').each do |g|
                g.layer = H.tag('lavi · Guarda-corpos')
              end
            end
          end
          H.ok("Guarda-corpo de #{H.br(H.to_m(total))} m criado.",
               stats: [['Comprimento', "#{H.br(H.to_m(total))} m"], ['Altura', "#{H.br(H.num(p['gc_alt'], 110), 0)} cm"], ['Trechos', paths.size.to_s]])
        end

        def dist3(a, b)
          Math.sqrt((0..2).sum { |i| (a[i] - b[i])**2 })
        end

        # junta as arestas selecionadas em linhas contínuas (cada uma vira um guarda-corpo)
        def chains(sel)
          edges = sel.grep(Sketchup::Edge)
          return [] if edges.empty?
          key = ->(pt) { [pt.x.round(3), pt.y.round(3), pt.z.round(3)] }
          adj = Hash.new { |h, k| h[k] = [] }
          pos = {}
          edges.each do |e|
            a = key.call(e.start.position)
            b = key.call(e.end.position)
            adj[a] << [b, e]
            adj[b] << [a, e]
            pos[a] = e.start.position
            pos[b] = e.end.position
          end
          used = {}
          out = []
          starts = adj.keys.select { |k| adj[k].size != 2 } + adj.keys
          starts.each do |s|
            adj[s].each do |n0, e0|
              next if used[e0]
              path = [s]
              cur = s
              nxt = n0
              e = e0
              loop do
                used[e] = true
                path << nxt
                cur = nxt
                cand = adj[cur].reject { |_, ee| used[ee] }
                break if cand.size != 1 || adj[cur].size > 2
                nxt, e = cand.first
              end
              out << path.map { |k| q = pos[k]; [q.x, q.y, q.z] }
            end
          end
          out
        end

        Registry.register(:railing, name: 'Guarda-corpo', tab: :arq, package: :arq, handler: self,
                                    desc: 'Vidro, montantes, cabos, mureta ou corrimão na varanda, mezanino ou borda de laje.',
                                    steps: ['Selecione as linhas da borda (ou clique)', 'Escolha o modelo e a altura', 'Criar'])
      end
    end
  end
end
