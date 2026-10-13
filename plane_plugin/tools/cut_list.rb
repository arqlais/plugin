# Lista de peças + plano de corte + fita de borda + ferragens

module Plane
  module Plugin
    module Tools
      module CutList
        extend self
        H = Helpers

        SKIP = %w[puxador acabamento].freeze
        EDGE_ALL = %w[porta frente_gaveta].freeze
        EDGE_ONE = %w[caixa gaveta].freeze

        def handle(action, p)
          parts = collect(p)
          return H.err('Nenhuma peça encontrada. Selecione os móveis (ou deixe nada selecionado para ler o modelo todo).') if parts.empty?
          rows = group(parts.reject { |x| SKIP.include?(x[:mk]) || x[:mk] == 'tampo' })
          case action
          when 'list', 'plan'
            report(parts, rows, p)
          when 'csv'
            out = [%w[Peça Qtd Comprimento(mm) Largura(mm) Espessura(mm) Material Fita(m)]]
            rows.each { |r| out << [r[:name], r[:qty], r[:l], r[:w], r[:t], r[:mat], r[:fita]] }
            out << []
            out << %w[Ferragem Qtd]
            hardware(parts).each { |n, q| out << [n, q] }
            path = H.save_csv(out, 'lista_de_pecas.csv')
            path ? H.ok("Planilha salva em #{path}") : H.ok('Cancelado.')
          else
            H.err('Ação desconhecida.')
          end
        end

        # ---- leitura ------------------------------------------------------------
        def collect(p)
          sel = H.selection.to_a
          src = sel.empty? ? H.model.entities.to_a : sel
          out = []
          generic = p['genericos'] == true || p['genericos'] == 'true'
          walk(src, IDENTITY, out, generic, nil)
          out
        end

        def walk(ents, tr, out, generic, inherited_mat)
          ents.each do |e|
            next unless H.instance?(e)
            next if e.hidden?
            next if e.layer && !e.layer.visible?
            t = tr * e.transformation
            mat = e.material || inherited_mat
            if H.kind_of(e) == 'part'
              out << part_of(e, t, mat, e.get_attribute(H::DICT, 'part'), e.get_attribute(H::DICT, 'mk'))
            elsif generic && leaf?(e)
              out << part_of(e, t, mat, e.respond_to?(:definition) && e.is_a?(Sketchup::ComponentInstance) ? e.definition.name : (e.name.empty? ? 'Peça' : e.name), 'caixa')
            else
              walk(H.entities_of(e).to_a, t, out, generic, mat)
            end
          end
        end

        def leaf?(e)
          ents = H.entities_of(e)
          ents.none? { |x| H.instance?(x) } && ents.grep(Sketchup::Face).size >= 6
        end

        def part_of(e, t, mat, name, mk)
          bb = e.definition.bounds
          sx = Geom::Vector3d.new(1, 0, 0).transform(t).length.to_f
          sy = Geom::Vector3d.new(0, 1, 0).transform(t).length.to_f
          sz = Geom::Vector3d.new(0, 0, 1).transform(t).length.to_f
          dims = [bb.width * sx, bb.height * sy, bb.depth * sz].map { |v| (H.to_mm(v) * 2).round / 2.0 }.sort.reverse
          { name: name.to_s, mk: mk.to_s, l: dims[0], w: dims[1], t: dims[2], mat: mat ? mat.display_name : 'Sem material' }
        end

        def group(parts)
          rows = {}
          parts.each do |x|
            key = [x[:name], x[:l], x[:w], x[:t], x[:mat]]
            r = rows[key] ||= x.merge(qty: 0, fita: 0.0)
            r[:qty] += 1
            r[:fita] += edge_m(x)
          end
          rows.values.sort_by { |r| [r[:mat], -r[:t], -r[:l]] }.each { |r| r[:fita] = r[:fita].round(2) }
        end

        def edge_m(x)
          if EDGE_ALL.include?(x[:mk]) then 2 * (x[:l] + x[:w]) / 1000.0
          elsif EDGE_ONE.include?(x[:mk]) then x[:l] / 1000.0
          else 0.0
          end
        end

        def hinges(h)
          return 2 if h <= 900
          return 3 if h <= 1600
          return 4 if h <= 2200
          5
        end

        def hardware(parts)
          hw = Hash.new(0)
          parts.each do |x|
            case x[:name]
            when 'Porta' then hw['Dobradiça 35 mm com amortecedor'] += hinges(x[:l])
            when 'Porta basculante'
              hw['Dobradiça 35 mm (basculante)'] += 2
              hw['Pistão a gás (par)'] += 1
            when 'Frente da gaveta' then hw['Corrediça telescópica (par)'] += 1
            when 'Puxador barra' then hw['Puxador barra 128 mm'] += 1
            end
          end
          perfil = parts.select { |x| x[:name] == 'Puxador perfil' }.sum { |x| x[:l] } / 1000.0
          hw["Perfil puxador (m) · barras de 3 m: #{(perfil / 3.0).ceil}"] = perfil.round(2) if perfil > 0
          gav = parts.select { |x| x[:name] == 'Lateral da gaveta' }.map { |x| x[:l] }
          unless gav.empty?
            sizes = Hash.new(0)
            gav.each { |l| sizes[[[(l / 50).floor * 50, 250].max, 550].min] += 1 }
            sizes.each { |s, q| hw["  · corrediça #{s.to_i} mm"] += q / 2 }
          end
          hw
        end

        # ---- relatório + plano de corte ------------------------------------------
        def report(parts, rows, p)
          opts = { sheet_w: H.num(p['chapa_c'], 2750), sheet_h: H.num(p['chapa_l'], 1840),
                   kerf: H.num(p['serra'], 4), trim: H.num(p['refilo'], 10), rotate: p['veio'] != true && p['veio'] != 'true' }
          by_mat = Hash.new { |h, k| h[k] = [] }
          rows.each do |r|
            r[:qty].times { by_mat["#{r[:mat]} · #{H.br(r[:t], 1)} mm"] << { w: r[:l], h: r[:w], label: r[:name] } }
          end
          plans = by_mat.map do |mat, pcs|
            sheets = Nesting.pack(pcs, opts)
            area = sheets.sum { |s| s[:used] }
            total = sheets.size * opts[:sheet_w] * opts[:sheet_h]
            { mat: mat, sheets: sheets.first(40), count: sheets.size, pieces: pcs.size,
              aproveitamento: total > 0 ? (area / total * 100).round(1) : 0, oversize: sheets.any? { |s| s[:oversize] } }
          end
          fita = Hash.new(0.0)
          rows.each { |r| fita[r[:mat]] += r[:fita] }
          tampos = parts.select { |x| x[:mk] == 'tampo' }
          stats = [['Peças de chapa', rows.sum { |r| r[:qty] }.to_s], ['Chapas', plans.sum { |pl| pl[:count] }.to_s]]
          fita.each { |m, v| stats << ["Fita · #{m}", "#{H.br(v * 1.1)} m (+10%)"] if v > 0 }
          stats << ['Tampos', "#{tampos.size} · #{H.br(tampos.sum { |x| x[:l] * x[:w] } / 1e6)} m²"] unless tampos.empty?
          H.ok("#{rows.sum { |r| r[:qty] }} peças lidas.",
               stats: stats, rows: rows.map { |r| r.slice(:name, :qty, :l, :w, :t, :mat, :fita) },
               plans: plans, hardware: hardware(parts).to_a,
               sheet: { w: opts[:sheet_w], h: opts[:sheet_h] })
        end

        Registry.register(:cut_list, name: 'Lista de peças e plano de corte', tab: :marc, package: :marc, handler: self,
                                     desc: 'Peças com medidas reais, chapas encaixadas, fita de borda e ferragens.',
                                     steps: ['Selecione os móveis', 'Gerar lista', 'Ver plano de corte e exportar'])
      end
    end
  end
end
