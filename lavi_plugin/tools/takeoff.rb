# Quantitativo: m² por material (piso, parede, teto, inclinado), itens do LAVI e componentes

module LAVIStudio
  module Plugin
    module Tools
      module Takeoff
        extend self
        H = Helpers
        CATS = %w[piso parede teto inclinado].freeze
        KIND_NAMES = {
          'floor_tiling' => 'Paginação de piso', 'wall_tiling' => 'Paginação de parede',
          'baseboard' => 'Rodapé', 'ceiling' => 'Forro', 'roof' => 'Telhado',
          'door' => 'Portas', 'window' => 'Janelas', 'cabinet' => 'Módulos de marcenaria', 'stairs' => 'Escadas'
        }.freeze

        def handle(action, p)
          q = quantities(p)
          case action
          when 'run'
            mats = q[:materials].map { |m, c| [m] + CATS.map { |k| c[k].round(2) } + [c.values.sum.round(2)] }
            H.ok("#{q[:materials].size} materiais, #{q[:items].size} itens e #{q[:components].size} componentes.",
                 stats: [['Piso', "#{H.br(q[:total]['piso'])} m²"], ['Parede', "#{H.br(q[:total]['parede'])} m²"],
                         ['Teto', "#{H.br(q[:total]['teto'])} m²"], ['Inclinado', "#{H.br(q[:total]['inclinado'])} m²"]],
                 materials: mats, items: q[:items], components: q[:components].first(60))
          when 'csv'
            rows = [['Material'] + CATS.map { |c| "#{c.capitalize} (m²)" } + ['Total (m²)']]
            q[:materials].each { |m, c| rows << [m] + CATS.map { |k| c[k].round(2) } + [c.values.sum.round(2)] }
            rows << []
            rows << %w[Item Quantidade Unidade]
            q[:items].each { |i| rows << i }
            rows << []
            rows << %w[Componente Quantidade]
            q[:components].each { |c| rows << c }
            path = H.save_csv(rows, 'quantitativo.csv')
            path ? H.ok("Planilha salva em #{path}") : H.ok('Cancelado.')
          else
            H.err('Ação desconhecida.')
          end
        end

        # Usado também pelo orçamento
        def quantities(p = {})
          sel = H.selection.to_a
          src = p['escopo'] == 'selecao' && !sel.empty? ? sel : H.model.entities.to_a
          skip_joinery = p['marcenaria'] != true && p['marcenaria'] != 'true'
          mats = Hash.new { |h, k| h[k] = Hash.new(0.0).tap { |x| CATS.each { |c| x[c] = 0.0 } } }
          items = Hash.new { |h, k| h[k] = [0.0, ''] }
          comps = Hash.new(0)
          walk(src, IDENTITY, nil, mats, items, comps, skip_joinery, true)
          total = Hash.new(0.0)
          mats.each_value { |c| CATS.each { |k| total[k] += c[k] } }
          {
            materials: mats.sort_by { |_, c| -c.values.sum },
            items: items.map { |k, (v, u)| [k, v.round(2), u] },
            components: comps.sort_by { |_, v| -v },
            total: total
          }
        end

        def walk(ents, tr, inh_mat, mats, items, comps, skip_joinery, top)
          ents.each do |e|
            next if e.respond_to?(:hidden?) && e.hidden?
            next if e.respond_to?(:layer) && e.layer && !e.layer.visible?
            if e.is_a?(Sketchup::Face)
              add_face(e, tr, inh_mat, mats)
            elsif H.instance?(e)
              kind = H.kind_of(e)
              count_item(e, kind, items)
              next if kind == 'part'
              next if KIND_NAMES.key?(kind) && kind != 'cabinet'
              if e.is_a?(Sketchup::ComponentInstance)
                ck = H.kind_of(e.definition)
                if ck == 'cabinet'
                  next if skip_joinery
                elsif top || !e.definition.name.start_with?('lavi')
                  comps[e.definition.name] += 1
                end
              end
              walk(H.entities_of(e).to_a, tr * e.transformation, e.material || inh_mat, mats, items, comps, skip_joinery, false)
            end
          end
        end

        def add_face(f, tr, inh_mat, mats)
          mat = f.material || inh_mat
          name = mat ? mat.display_name : 'Sem material'
          n = f.normal.transform(tr)
          n.normalize!
          cat = if n.z > 0.98 then 'piso'
                elsif n.z < -0.98 then 'teto'
                elsif n.z.abs < 0.05 then 'parede'
                else 'inclinado'
                end
          mats[name][cat] += H.m2(H.face_area(f, tr))
        end

        def count_item(e, kind, items)
          return unless kind && KIND_NAMES[kind]
          n = KIND_NAMES[kind]
          case kind
          when 'floor_tiling', 'wall_tiling', 'ceiling', 'roof'
            items[n][0] += e.get_attribute(H::DICT, 'area_m2').to_f
            items[n][1] = 'm²'
          when 'baseboard'
            items[n][0] += e.get_attribute(H::DICT, 'metros').to_f
            items[n][1] = 'm'
          else
            items[n][0] += 1
            items[n][1] = 'un'
          end
        end

        Registry.register(:takeoff, name: 'Quantitativo', tab: :quant, package: :quant, handler: self,
                                    desc: 'm² de piso, parede e teto por material, itens e componentes, em planilha.',
                                    steps: ['Pinte o modelo com materiais', 'Gerar quantitativo', 'Exportar para Excel'])
      end
    end
  end
end
