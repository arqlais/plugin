# Índices urbanísticos: taxa de ocupação, coeficiente de aproveitamento e taxa de permeabilidade

module PlaneLA
  module Plugin
    module Tools
      module UrbanIndex
        extend self
        H = Helpers

        CATS = {
          'terreno'    => { nome: 'Terreno',          cor: 'E8E2DA' },
          'projecao'   => { nome: 'Projeção',         cor: 'FFB3D1' },
          'construida' => { nome: 'Área construída',  cor: 'C9B3FF' },
          'permeavel'  => { nome: 'Área permeável',   cor: 'B3E0C9' }
        }.freeze

        def handle(action, p)
          case action
          when 'assign'
            cat = p['cat'].to_s
            return H.err('Categoria inválida.') unless CATS[cat]
            sel = H.selection.to_a.select { |e| e.is_a?(Sketchup::Face) || H.instance?(e) }
            return H.err('Selecione faces (ou grupos de pavimento) primeiro.') if sel.empty?
            H.operation('Planê · Índices') do
              sel.each do |e|
                e.set_attribute(H::DICT, 'urb_cat', cat)
                e.material = H.material("PLN_Indice_#{cat}", CATS[cat][:cor], 0.75) if p['colorir'] != false
              end
            end
            calc(p, "#{sel.size} item(ns) marcado(s) como #{CATS[cat][:nome]}.")
          when 'clear'
            H.operation('Planê · Índices') do
              H.selection.each { |e| e.delete_attribute(H::DICT, 'urb_cat') if e.respond_to?(:delete_attribute) }
            end
            calc(p, 'Marcação removida da seleção.')
          when 'calc'
            calc(p, 'Índices atualizados.')
          when 'csv'
            r = totals
            rows = [%w[Item Valor]] + table(r, p).map { |a, b, _| [a, b] }
            path = H.save_csv(rows, 'indices_urbanisticos.csv')
            path ? H.ok("Planilha salva em #{path}") : H.ok('Cancelado.')
          else
            H.err('Ação desconhecida.')
          end
        end

        def totals
          sums = Hash.new(0.0)
          walk(H.model.entities, IDENTITY, sums)
          sums
        end

        def walk(ents, tr, sums)
          ents.each do |e|
            cat = e.get_attribute(H::DICT, 'urb_cat') if e.respond_to?(:get_attribute)
            if e.is_a?(Sketchup::Face)
              sums[cat] += H.m2(H.face_area(e, tr)) if cat
            elsif H.instance?(e)
              t = tr * e.transformation
              if cat
                H.entities_of(e).grep(Sketchup::Face).each do |f|
                  n = f.normal.transform(t)
                  sums[cat] += H.m2(H.face_area(f, t)) if n.z > 0.98
                end
              else
                walk(H.entities_of(e), t, sums)
              end
            end
          end
        end

        def table(r, p)
          ter = r['terreno']
          to = ter > 0 ? r['projecao'] / ter * 100 : 0
          ca = ter > 0 ? r['construida'] / ter : 0
          tp = ter > 0 ? r['permeavel'] / ter * 100 : 0
          to_max = H.num(p['to_max'], 0)
          ca_max = H.num(p['ca_max'], 0)
          tp_min = H.num(p['tp_min'], 0)
          [
            ['Terreno', "#{H.br(ter)} m²", nil],
            ['Projeção', "#{H.br(r['projecao'])} m²", nil],
            ['Área construída', "#{H.br(r['construida'])} m²", nil],
            ['Área permeável', "#{H.br(r['permeavel'])} m²", nil],
            ['Taxa de ocupação', "#{H.br(to, 1)} %", to_max > 0 ? to <= to_max : nil],
            ['Coef. de aproveitamento', H.br(ca, 2), ca_max > 0 ? ca <= ca_max : nil],
            ['Taxa de permeabilidade', "#{H.br(tp, 1)} %", tp_min > 0 ? tp >= tp_min : nil]
          ]
        end

        def calc(p, msg)
          r = totals
          return H.ok('Marque primeiro a face do terreno.', stats: table(r, p)) if r['terreno'] <= 0
          H.ok(msg, stats: table(r, p))
        end

        Registry.register(:urban_index, name: 'Índices urbanísticos', tab: :arq, package: :arq, handler: self,
                                        desc: 'TO, CA e permeabilidade conferidos com a lei do seu terreno.',
                                        steps: ['Selecione faces', 'Marque terreno, projeção, construída, permeável', 'Compare com a lei'])
      end
    end
  end
end
