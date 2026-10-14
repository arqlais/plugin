# Materiais para render: conta-gotas, trocar um material por outro na cena toda,
# limpar os materiais de dentro de um bloco e materiais prontos (vidros, espelho, metais).

module LAVIStudio
  module Plugin
    module Tools
      module Materials
        extend self
        H = Helpers

        # [nome, cor, opacidade] — nomes claros ajudam o motor de render / IA a reconhecer
        PRESETS = {
          'vidro_incolor' => ['lavi Vidro incolor', 'CFE3E8', 0.25], 'vidro_fume' => ['lavi Vidro fumê', '5B6066', 0.45],
          'vidro_verde' => ['lavi Vidro verde', 'BFD8C8', 0.35], 'vidro_jateado' => ['lavi Vidro jateado', 'E9EEF0', 0.7],
          'espelho' => ['lavi Espelho', 'D9DEE2', 1.0], 'espelho_bronze' => ['lavi Espelho bronze', 'B59A7C', 1.0],
          'inox' => ['lavi Metal inox escovado', 'B8BCC0', 1.0], 'cromado' => ['lavi Metal cromado', 'E2E5E8', 1.0],
          'latao' => ['lavi Metal latão dourado', 'C9A45C', 1.0], 'cobre' => ['lavi Metal cobre', 'B87333', 1.0],
          'bronze' => ['lavi Metal bronze', '8C6A43', 1.0], 'aluminio' => ['lavi Metal alumínio', 'C4C7CA', 1.0],
          'preto_fosco' => ['lavi Metal preto fosco', '2B2B2B', 1.0], 'branco_fosco' => ['lavi Pintura branco fosco', 'F2F2F0', 1.0]
        }.freeze

        def handle(action, p)
          case action
          when 'list' then H.ok('', mats: list)
          when 'pick' then pick(p)
          when 'swap' then swap(p)
          when 'clean' then clean(p)
          when 'apply' then apply(p)
          else H.err('Ação desconhecida.')
          end
        end

        def list
          H.model.materials.map { |m| [m.name, m.display_name, m.color.to_s] }.sort_by { |x| x[1].downcase }
        end

        # conta-gotas: clique numa face e o material dela vai para o campo "Trocar este"
        def pick(_p)
          Sketchup.active_model.select_tool(
            Pickers::FacePicker.new('Conta-gotas: clique no material que quer trocar') do |face, _tr, _pt, path|
              holder = path.reverse.find { |e| e.respond_to?(:material) && e.material }
              mat = face.material || (holder ? holder.material : nil)
              Sketchup.active_model.select_tool(nil)
              Dialog.push('result', tool: 'materials', ok: !mat.nil?, msg: mat ? "Material: #{mat.display_name}" : 'Essa face está sem material.',
                                    values: mat ? { 'de' => mat.name } : {}, mats: list)
            end
          )
          H.ok('Clique no material, no modelo.', picking: true)
        end

        def swap(p)
          m = H.model
          de = m.materials[p['de'].to_s]
          para = p['para'].to_s == '' ? nil : m.materials[p['para'].to_s]
          return H.err('Escolha (ou pegue com o conta-gotas) o material a trocar.') unless de
          return H.err('Escolha o material novo.') if para.nil? && p['para'].to_s != ''
          return H.err('Os dois materiais são iguais.') if de == para
          n = 0
          H.operation('lavi · Trocar material') do
            each_entity(m.entities.to_a) do |e|
              if e.respond_to?(:material) && e.material == de
                e.material = para
                n += 1
              end
              if e.is_a?(Sketchup::Face) && e.back_material == de
                e.back_material = para
                n += 1
              end
            end
          end
          H.ok("#{n} lugar(es) trocado(s): #{de.display_name} → #{para ? para.display_name : 'sem material'}.", stats: [['Trocas', n.to_s]])
        end

        # tira os materiais das faces de dentro do bloco (o bloco fica com uma cor só)
        def clean(p)
          insts = H.selection.to_a.select { |e| H.instance?(e) }
          return H.err('Selecione o bloco (grupo ou componente).') if insts.empty?
          n = 0
          H.operation('lavi · Limpar materiais') do
            each_entity(insts.flat_map { |i| H.entities_of(i).to_a }) do |e|
              next unless e.respond_to?(:material)
              if e.material
                e.material = nil
                n += 1
              end
              e.back_material = nil if e.is_a?(Sketchup::Face) && e.back_material
            end
            insts.each { |i| i.material = nil } if p['tudo'] == true || p['tudo'] == 'true'
          end
          H.ok("#{n} material(is) removido(s) de dentro do bloco.", stats: [['Removidos', n.to_s]])
        end

        def apply(p)
          pr = PRESETS[p['preset'].to_s]
          return H.err('Escolha um material pronto.') unless pr
          sel = H.selection.to_a.select { |e| e.respond_to?(:material=) && !e.is_a?(Sketchup::Edge) }
          return H.err('Selecione as faces ou os blocos.') if sel.empty?
          H.operation('lavi · Material pronto') do
            mat = H.material(pr[0], pr[1], pr[2] < 1 ? pr[2] : nil)
            sel.each { |e| e.material = mat }
          end
          H.ok("#{pr[0].sub('lavi ', '')} aplicado em #{sel.size} item(ns).", mats: list)
        end

        def each_entity(items, seen = {}, &block)
          items.each do |e|
            yield e
            next unless H.instance?(e)
            d = e.definition
            next if seen[d]
            seen[d] = true
            each_entity(H.entities_of(e).to_a, seen, &block)
          end
        end

        Registry.register(:materials, name: 'Materiais', tab: :render, package: :pres, handler: self,
                                      desc: 'Conta-gotas, trocar material na cena toda, limpar bloco e materiais prontos (vidros, espelho, metais).',
                                      steps: ['Pegue o material com o conta-gotas', 'Escolha o novo', 'Trocar na cena toda'])
      end
    end
  end
end
