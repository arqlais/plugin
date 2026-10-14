# Lista de peças + plano de corte + fita de borda + ferragens

module LAVIStudio
  module Plugin
    module Tools
      module CutList
        extend self
        H = Helpers

        SKIP = %w[puxador acabamento ferragem].freeze
        EDGE_ALL = %w[porta frente_gaveta].freeze
        EDGE_ONE = %w[caixa gaveta].freeze

        def handle(action, p)
          parts = collect(p)
          return H.err('Nenhuma peça encontrada. Selecione os móveis (ou deixe nada selecionado para ler o modelo todo).') if parts.empty?
          rows = group(parts.reject { |x| SKIP.include?(x[:mk]) || x[:mk] == 'tampo' })
          case action
          when 'list', 'plan'
            report(parts, rows, p)
          when 'labels'
            res = report(parts, rows, p)
            path = labels_html(res, rows, p)
            UI.openURL("file:///#{path.tr('\\', '/')}")
            H.ok('Etiquetas e plano abertos no navegador: imprima em A4 (Ctrl+P), escala 100%.', stats: [['Etiquetas', rows.sum { |r| r[:qty] }.to_s]])
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
              nm = e.name.to_s
              nm = e.definition.name if nm.empty? && !e.is_a?(Sketchup::Group)
              out << part_of(e, t, mat, nm.empty? ? 'Peça' : nm, 'caixa')
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


        def hardware(parts)
          hw = Hash.new(0)
          parts.each do |x|
            case x[:name]
            when 'Dobradiça' then hw['Dobradiça 35 mm com amortecedor'] += 1
            when 'Porta basculante' then hw['Pistão a gás (par)'] += 1
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
                   kerf: H.num(p['serra'], 4), trim: H.num(p['refilo'], 10), rotate: p['veio'] != true && p['veio'] != 'true',
                   method: p['metodo'].to_s == 'livre' ? 'livre' : 'guilhotina' }
          rows.each_with_index { |r, i| r[:id] = i + 1 }
          by_mat = Hash.new { |h, k| h[k] = [] }
          rows.each do |r|
            r[:qty].times { by_mat["#{r[:mat]} · #{H.br(r[:t], 1)} mm"] << { w: r[:l], h: r[:w], label: r[:name], id: r[:id] } }
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
               stats: stats, rows: rows.map { |r| r.slice(:id, :name, :qty, :l, :w, :t, :mat, :fita) },
               plans: plans, hardware: hardware(parts).to_a,
               sheet: { w: opts[:sheet_w], h: opts[:sheet_h] })
        end

        # ---- etiquetas + plano para imprimir ---------------------------------------
        def esc(s)
          s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
        end

        def fita_txt(r)
          if EDGE_ALL.include?(r[:mk]) then 'fita nos 4 lados'
          elsif EDGE_ONE.include?(r[:mk]) then 'fita em 1 lado comprido'
          else 'sem fita'
          end
        end

        def sheet_svg(sh, w = 180)
          s = w / sh[:w].to_f
          h = sh[:h] * s
          parts = sh[:parts].map do |pt|
            big = pt[:w] * s > 9 && pt[:h] * s > 5
            "<rect x='#{(pt[:x] * s).round(2)}' y='#{(pt[:y] * s).round(2)}' width='#{(pt[:w] * s).round(2)}' height='#{(pt[:h] * s).round(2)}' fill='#F4E8E5' stroke='#3E4B57' stroke-width='.25'/>" +
              (big ? "<text x='#{((pt[:x] + pt[:w] / 2) * s).round(2)}' y='#{((pt[:y] + pt[:h] / 2) * s + 1.2).round(2)}' font-size='3.2' text-anchor='middle' fill='#3E4B57'>#{pt[:id]}</text>" : '')
          end.join
          "<svg viewBox='0 0 #{w} #{h.round(2)}' width='#{w}mm' height='#{h.round(2)}mm'><rect width='#{w}' height='#{h.round(2)}' fill='#fff' stroke='#8B939A' stroke-width='.3'/>#{parts}</svg>"
        end

        def labels_html(res, rows, p)
          cols, lw, lh = p['etiqueta'].to_s == '2x7' ? [2, 99, 38] : [3, 70, 37]
          proj = esc(p['projeto'])
          labels = []
          rows.each do |r|
            r[:qty].times do |k|
              labels << "<div class='lb' style='width:#{lw}mm;height:#{lh}mm'><div class='top'><b class='id'>#{r[:id]}</b><span>#{esc(r[:name])}</span><em>#{k + 1}/#{r[:qty]}</em></div>"                         "<div class='dim'>#{H.br(r[:l], 0)} × #{H.br(r[:w], 0)} × #{H.br(r[:t], 1)} mm</div>"                         "<div class='sub'>#{esc(r[:mat])} · #{fita_txt(r)}</div><div class='pj'>#{proj}</div></div>"
            end
          end
          plan = ''
          if p['plano'] != false && p['plano'] != 'false'
            plan = res[:plans].map do |pl|
              "<section class='pl'><h2>#{esc(pl[:mat])} · #{pl[:count]} chapa(s) · #{H.br(pl[:aproveitamento], 1)}% aproveitado</h2>" +
                pl[:sheets].each_with_index.map { |sh, i| "<figure><figcaption>Chapa #{i + 1} · #{sh[:parts].size} peças</figcaption>#{sheet_svg(sh)}</figure>" }.join + '</section>'
            end.join
            plan += "<section class='pl'><h2>Peças</h2><table><tr><th>Nº</th><th>Peça</th><th>Qtd</th><th>C × L × E (mm)</th><th>Material</th><th>Fita</th></tr>" +
                    rows.map { |r| "<tr><td>#{r[:id]}</td><td>#{esc(r[:name])}</td><td>#{r[:qty]}</td><td>#{H.br(r[:l], 0)} × #{H.br(r[:w], 0)} × #{H.br(r[:t], 1)}</td><td>#{esc(r[:mat])}</td><td>#{fita_txt(r)}</td></tr>" }.join +
                    '</table></section>'
          end
          html = <<~HTML
            <!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Plano de corte e etiquetas</title>
            <style>
            @page{size:A4;margin:10mm}
            body{font-family:Poppins,Arial,sans-serif;color:#3E4B57;margin:0}
            h1{font-size:18px;margin:0 0 4px} .hd{color:#8B939A;font-size:11px;margin-bottom:10px}
            h2{font-size:11px;letter-spacing:.1em;text-transform:uppercase;margin:12px 0 6px}
            .pl{break-after:page} figure{display:inline-block;margin:0 6mm 6mm 0;vertical-align:top} figcaption{font-size:10px;margin-bottom:2px}
            table{border-collapse:collapse;font-size:10px;width:100%} td,th{border-bottom:1px solid #EBE1DC;padding:3px 4px;text-align:left}
            .grid{display:grid;grid-template-columns:repeat(#{cols},#{lw}mm);gap:0;justify-content:center}
            .lb{box-sizing:border-box;padding:2.5mm 3mm;border:.2mm dashed #D6B3AB;overflow:hidden;display:flex;flex-direction:column;justify-content:space-between;break-inside:avoid}
            .top{display:flex;gap:2mm;align-items:baseline;font-size:10px} .top span{flex:1;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
            .id{font-size:16px;color:#A88A80} em{font-style:normal;font-size:9px;color:#8B939A}
            .dim{font-family:'JetBrains Mono',monospace;font-size:12px;font-weight:600}
            .sub{font-size:8.5px;color:#3E4B57} .pj{font-size:8px;color:#8B939A}
            @media print{.lb{border-color:#eee}}
            </style></head><body>
            <h1>Plano de corte</h1><div class="hd">#{proj} · lavi</div>
            #{plan}
            <div class="grid">#{labels.join}</div>
            </body></html>
          HTML
          dir = File.join(Dir.tmpdir, "lavi_corte_#{Time.now.to_i}")
          Dir.mkdir(dir) unless Dir.exist?(dir)
          path = File.join(dir, 'plano_e_etiquetas.html')
          File.write(path, html, encoding: 'UTF-8')
          path
        end

        Registry.register(:cut_list, name: 'Lista de peças e plano de corte', tab: :marc, package: :marc, handler: self,
                                     desc: 'Peças com medidas reais, chapas encaixadas, fita de borda e ferragens.',
                                     steps: ['Selecione os móveis', 'Gerar lista', 'Ver plano de corte e exportar'])
      end
    end
  end
end
