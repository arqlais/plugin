# Orçamento: quantidades do modelo × preços salvos no próprio arquivo .skp → planilha e proposta em PDF

require 'json'
require 'tmpdir'

module Plane
  module Plugin
    module Tools
      module Budget
        extend self
        H = Helpers
        DICT = 'plane_budget'.freeze

        def handle(action, p)
          case action
          when 'load' then load(p)
          when 'save'
            save(p)
            H.ok('Preços salvos neste arquivo do SketchUp.')
          when 'csv'
            save(p)
            t = totals(p)
            rows = [%w[Item Quantidade Unidade Preço Total]]
            t[:lines].each { |l| rows << [l['desc'], l['qty'].to_f, l['un'], l['preco'].to_f, l['total']] }
            rows << []
            t[:resumo].each { |k, v| rows << [k, '', '', '', v] }
            path = H.save_csv(rows, 'orcamento.csv')
            path ? H.ok("Planilha salva em #{path}") : H.ok('Cancelado.')
          when 'proposal'
            save(p)
            path = proposal(p)
            UI.openURL("file:///#{path.tr('\\', '/')}")
            H.ok('Proposta aberta no navegador. Use Imprimir › Salvar como PDF.')
          else
            H.err('Ação desconhecida.')
          end
        end

        def stored
          raw = H.model.get_attribute(DICT, 'data', '{}')
          JSON.parse(raw.to_s)
        rescue StandardError
          {}
        end

        def load(p)
          q = Tools::Takeoff.quantities(p)
          data = stored
          prices = data['precos'] || {}
          lines = []
          q[:materials].each do |name, c|
            tot = c.values.sum
            next if tot < 0.01
            id = "mat:#{name}"
            lines << { 'id' => id, 'grupo' => 'Materiais', 'desc' => name, 'qty' => tot.round(2), 'un' => 'm²', 'preco' => prices[id].to_f }
          end
          q[:items].each do |name, v, un|
            id = "item:#{name}"
            lines << { 'id' => id, 'grupo' => 'Itens', 'desc' => name, 'qty' => v, 'un' => un, 'preco' => prices[id].to_f }
          end
          q[:components].each do |name, v|
            id = "comp:#{name}"
            lines << { 'id' => id, 'grupo' => 'Componentes', 'desc' => name, 'qty' => v, 'un' => 'un', 'preco' => prices[id].to_f }
          end
          (data['extras'] || []).each { |l| lines << l.merge('grupo' => 'Serviços') }
          H.ok("#{lines.size} linhas carregadas do modelo.", lines: lines, settings: data['config'] || {})
        end

        def save(p)
          data = stored
          data['precos'] ||= {}
          Array(p['lines']).each do |l|
            next if l['id'].to_s.start_with?('extra:')
            data['precos'][l['id']] = H.num(l['preco'])
          end
          data['extras'] = Array(p['lines']).select { |l| l['id'].to_s.start_with?('extra:') }
          data['config'] = p['config'] || {}
          H.operation('Planê · Salvar orçamento') { H.model.set_attribute(DICT, 'data', JSON.generate(data)) }
        end

        def totals(p)
          cfg = p['config'] || {}
          lines = Array(p['lines']).map { |l| l.merge('total' => (H.num(l['qty']) * H.num(l['preco'])).round(2)) }
          sub = lines.sum { |l| l['total'] }
          mo = sub * H.num(cfg['mo']) / 100
          bdi = (sub + mo) * H.num(cfg['bdi']) / 100
          desc = (sub + mo + bdi) * H.num(cfg['desconto']) / 100
          total = sub + mo + bdi - desc
          resumo = [['Materiais e itens', sub.round(2)]]
          resumo << ["Mão de obra (#{H.br(H.num(cfg['mo']), 0)}%)", mo.round(2)] if mo > 0
          resumo << ["BDI (#{H.br(H.num(cfg['bdi']), 0)}%)", bdi.round(2)] if bdi > 0
          resumo << ["Desconto (#{H.br(H.num(cfg['desconto']), 0)}%)", -desc.round(2)] if desc > 0
          resumo << ['Total', total.round(2)]
          { lines: lines, resumo: resumo, total: total }
        end

        def esc(s)
          s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
        end

        def proposal(p)
          cfg = p['config'] || {}
          t = totals(p)
          rows = t[:lines].select { |l| l['total'] > 0 }.map do |l|
            "<tr><td>#{esc(l['desc'])}</td><td class=n>#{H.br(H.num(l['qty']))} #{esc(l['un'])}</td><td class=n>R$ #{H.br(H.num(l['preco']))}</td><td class=n>R$ #{H.br(l['total'])}</td></tr>"
          end.join
          res = t[:resumo].map { |k, v| "<tr#{k == 'Total' ? ' class=tot' : ''}><td colspan=3>#{esc(k)}</td><td class=n>R$ #{H.br(v)}</td></tr>" }.join
          logo = File.read(File.join(ROOT, 'ui', 'icon.svg')) rescue ''
          html = <<~HTML
            <!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Proposta · #{esc(cfg['projeto'])}</title>
            <style>
            @page{size:A4;margin:18mm}
            body{font-family:Poppins,Arial,sans-serif;color:#3E4B57;margin:0;padding:32px;background:#fff}
            header{display:flex;align-items:center;gap:16px;border-bottom:3px solid;border-image:linear-gradient(90deg,#FF2E88,#A970FF) 1;padding-bottom:16px}
            header svg{width:56px;height:56px}
            h1{margin:0;font-size:26px}
            .sub{color:#8B939A;font-size:13px}
            .meta{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:24px 0}
            .meta div{background:#F7F3F8;border-radius:10px;padding:10px 14px;font-size:13px}
            .meta b{display:block;font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:#A970FF}
            table{width:100%;border-collapse:collapse;font-size:13px}
            th{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:#8B939A;border-bottom:1px solid #E6E1E8;padding:8px 6px}
            td{padding:8px 6px;border-bottom:1px solid #F0ECF2}
            .n{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}
            .tot td{font-weight:700;font-size:16px;border-top:2px solid #3E4B57;color:#3E4B57}
            .obs{margin-top:24px;font-size:12px;color:#6B7682;white-space:pre-wrap}
            footer{margin-top:40px;font-size:11px;color:#8B939A}
            </style></head><body>
            <header>#{logo}<div><h1>Proposta de orçamento</h1><div class="sub">#{esc(cfg['estudio'] || 'Planê')}</div></div></header>
            <section class="meta">
              <div><b>Cliente</b>#{esc(cfg['cliente'])}</div>
              <div><b>Projeto</b>#{esc(cfg['projeto'])}</div>
              <div><b>Validade</b>#{esc(cfg['validade'] || '15 dias')}</div>
            </section>
            <table><thead><tr><th>Item</th><th class=n>Quantidade</th><th class=n>Preço</th><th class=n>Total</th></tr></thead>
            <tbody>#{rows}</tbody><tfoot>#{res}</tfoot></table>
            <div class="obs">#{esc(cfg['obs'])}</div>
            <footer>Gerado em #{Time.now.strftime('%d/%m/%Y')} · quantidades medidas no modelo 3D</footer>
            </body></html>
          HTML
          path = File.join(Dir.tmpdir, "proposta_#{Time.now.to_i}.html")
          File.write(path, html, encoding: 'UTF-8')
          path
        end

        Registry.register(:budget, name: 'Orçamento e proposta', tab: :quant, package: :quant, handler: self,
                                   desc: 'Preço por item salvo no arquivo, mão de obra, BDI e proposta em PDF.',
                                   steps: ['Carregar quantidades', 'Preencher preços', 'Gerar proposta'])
      end
    end
  end
end
