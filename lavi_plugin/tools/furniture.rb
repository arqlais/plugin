# Ficha de mobiliário: nome, marca, cor, código, link e preço em cada componente;
# relatório por ambiente (Excel) e caderno de especificação com foto de cada item (abre no navegador → PDF).

require 'tmpdir'

module LAVIStudio
  module Plugin
    module Tools
      module Furniture
        extend self
        H = Helpers
        # (v0.12: faz parte de outra ferramenta do painel, sem botão próprio)
        D = 'plane_item'.freeze
        DEF_KEYS = %w[nome marca cor codigo link preco obs].freeze

        def handle(action, p)
          case action
          when 'apply' then apply(p)
          when 'read'
            inst = targets.first
            return H.err('Selecione um móvel (componente).') unless inst
            vals = {}
            DEF_KEYS.each { |k| vals[k] = inst.definition.get_attribute(D, k) }
            vals['ambiente'] = inst.get_attribute(D, 'ambiente')
            vals['nome'] = inst.definition.name if vals['nome'].to_s.empty?
            H.ok('Dados do móvel carregados.', values: vals.reject { |_k, v| v.nil? })
          when 'report'
            rows = report(p)
            total = rows.sum { |r| r[:total] }
            H.ok("#{rows.size} item(ns) no relatório.",
                 stats: [['Itens diferentes', rows.size.to_s], ['Peças', rows.sum { |r| r[:qtd] }.to_s], ['Total', "R$ #{H.br(total)}"]],
                 items: rows.map { |r| [r[:ambiente], r[:nome], r[:marca], r[:qtd], r[:total]] })
          when 'csv'
            rows = report(p)
            out = [%w[Ambiente Item Marca Cor/acabamento Código Qtd Preço Total Link Observação]]
            rows.each { |r| out << [r[:ambiente], r[:nome], r[:marca], r[:cor], r[:codigo], r[:qtd], r[:preco], r[:total], r[:link], r[:obs]] }
            out << ['TOTAL', '', '', '', '', rows.sum { |r| r[:qtd] }, '', rows.sum { |r| r[:total] }]
            path = H.save_csv(out, 'mobiliario.csv')
            path ? H.ok("Planilha salva em #{path}") : H.ok('Cancelado.')
          when 'sheet'
            path = sheet(p)
            UI.openURL("file:///#{path.tr('\\', '/')}")
            H.ok('Caderno de especificação aberto no navegador. Use Imprimir › Salvar como PDF.')
          else
            H.err('Ação desconhecida.')
          end
        end

        def targets
          H.selection.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) }
        end

        def apply(p)
          insts = targets
          return H.err('Selecione um ou mais móveis (componentes). Grupos não servem: transforme em componente antes.') if insts.empty?
          H.operation('lavi · Ficha de mobiliário') do
            insts.map(&:definition).uniq.each do |d|
              DEF_KEYS.each do |k|
                v = p[k]
                next if v.nil? || v.to_s.strip.empty?
                d.set_attribute(D, k, k == 'preco' ? H.num(v) : v.to_s.strip)
              end
            end
            insts.each { |i| i.set_attribute(D, 'ambiente', p['ambiente'].to_s.strip) unless p['ambiente'].to_s.strip.empty? }
          end
          H.ok("Ficha aplicada em #{insts.size} móvel(is). Cópias do mesmo componente compartilham a ficha; o ambiente é de cada cópia.")
        end

        # Agrupa por ambiente + componente
        def report(p)
          only = p['so_fichados'] != false && p['so_fichados'] != 'false'
          rows = {}
          walk(H.model.entities, rows, only)
          rows.values.sort_by { |r| [r[:ambiente], r[:nome]] }.each { |r| r[:total] = (r[:preco] * r[:qtd]).round(2) }
        end

        def walk(ents, rows, only)
          ents.each do |e|
            next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            next if e.hidden? || (e.layer && !e.layer.visible?)
            if e.is_a?(Sketchup::ComponentInstance)
              d = e.definition
              has = !d.get_attribute(D, 'nome').to_s.empty?
              if has || (!only && H.kind_of(e).nil?)
                amb = e.get_attribute(D, 'ambiente').to_s
                amb = 'Sem ambiente' if amb.empty?
                key = [amb, d.entityID]
                r = rows[key] ||= {
                  ambiente: amb, defn: d, nome: (has ? d.get_attribute(D, 'nome') : d.name).to_s,
                  marca: d.get_attribute(D, 'marca').to_s, cor: d.get_attribute(D, 'cor').to_s,
                  codigo: d.get_attribute(D, 'codigo').to_s, link: d.get_attribute(D, 'link').to_s,
                  obs: d.get_attribute(D, 'obs').to_s, preco: d.get_attribute(D, 'preco').to_f, qtd: 0
                }
                r[:qtd] += 1
                next
              end
            end
            walk(H.entities_of(e), rows, only)
          end
        end

        def esc(s)
          s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
        end

        def sheet(p)
          rows = report(p)
          dir = File.join(Dir.tmpdir, "plane_caderno_#{Time.now.to_i}")
          Dir.mkdir(dir) unless Dir.exist?(dir)
          thumbs = {}
          rows.map { |r| r[:defn] }.uniq.each_with_index do |d, i|
            f = File.join(dir, "item_#{i}.png")
            thumbs[d] = File.basename(f) if d.respond_to?(:save_thumbnail) && d.save_thumbnail(f)
          end
          logo = File.read(File.join(ROOT, 'ui', 'icon.svg')) rescue ''
          groups = rows.group_by { |r| r[:ambiente] }
          body = groups.map do |amb, list|
            cards = list.map do |r|
              img = thumbs[r[:defn]] ? "<img src=\"#{thumbs[r[:defn]]}\">" : '<div class="noimg"></div>'
              link = r[:link].start_with?('http') ? "<a href=\"#{esc(r[:link])}\">ver produto</a>" : ''
              preco = r[:preco] > 0 ? "<b>R$ #{H.br(r[:preco])}</b> × #{r[:qtd]} = R$ #{H.br(r[:total])}" : "Qtd: #{r[:qtd]}"
              "<article>#{img}<div><h3>#{esc(r[:nome])}</h3><p>#{[r[:marca], r[:cor], r[:codigo]].reject(&:empty?).map { |x| esc(x) }.join(' · ')}</p>" \
                "<p>#{preco}</p><p class=obs>#{esc(r[:obs])}</p>#{link}</div></article>"
            end.join
            "<section><h2>#{esc(amb)}</h2>#{cards}</section>"
          end.join
          total = rows.sum { |r| r[:total] }
          html = <<~HTML
            <!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Caderno de especificação</title>
            <style>
            @page{size:A4;margin:14mm}
            body{font-family:Poppins,Arial,sans-serif;color:#3E4B57;margin:0;padding:28px}
            header{display:flex;align-items:center;gap:14px;border-bottom:3px solid #3E4B57;padding-bottom:14px;margin-bottom:8px}
            header svg{width:48px;height:48px} h1{margin:0;font-size:22px} .sub{color:#8B939A;font-size:12px}
            h2{font-size:13px;letter-spacing:.12em;text-transform:uppercase;color:#3E4B57;margin:22px 0 10px}
            section{break-inside:avoid-page}
            article{display:grid;grid-template-columns:120px 1fr;gap:14px;padding:10px;border:1px solid #EEE7EE;border-radius:12px;margin-bottom:8px;break-inside:avoid}
            article img,.noimg{width:120px;height:90px;object-fit:contain;background:#EFEFEF;border-radius:8px}
            h3{margin:0 0 4px;font-size:15px} p{margin:2px 0;font-size:12px} .obs{color:#8B939A} a{font-size:12px;color:#A88A80}
            footer{margin-top:24px;font-size:12px;display:flex;justify-content:space-between;border-top:1px solid #EEE7EE;padding-top:10px}
            </style></head><body>
            <header>#{logo}<div><h1>Caderno de especificação</h1><div class="sub">#{esc(p['projeto'])} #{p['cliente'].to_s.empty? ? '' : '· ' + esc(p['cliente'])}</div></div></header>
            #{body}
            <footer><span>#{rows.sum { |r| r[:qtd] }} peças · #{rows.size} itens</span><b>#{total > 0 ? "Total R$ #{H.br(total)}" : ''}</b></footer>
            </body></html>
          HTML
          path = File.join(dir, 'caderno.html')
          File.write(path, html, encoding: 'UTF-8')
          path
        end

      end
    end
  end
end
