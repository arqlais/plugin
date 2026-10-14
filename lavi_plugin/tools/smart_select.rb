# Seleção inteligente: a partir do que está selecionado, pega tudo do mesmo material,
# da mesma etiqueta ou do mesmo componente; inverte a seleção; acha linhas soltas e faces de costas.

module LAVIStudio
  module Plugin
    module Tools
      module SmartSelect
        extend self
        H = Helpers
        NAMES = { 'material' => 'do mesmo material', 'etiqueta' => 'da mesma etiqueta', 'componente' => 'do mesmo componente',
                  'inverter' => 'que não estavam selecionados', 'soltas' => 'linhas soltas (sem face)',
                  'costas' => 'faces de costas para cima', 'escondidos' => 'escondidos' }.freeze

        def handle(action, _p)
          return H.err('Ação desconhecida.') unless NAMES.key?(action)
          sel = H.selection
          ents = H.model.active_entities.to_a
          ref = sel.first
          if %w[material etiqueta componente].include?(action) && ref.nil?
            return H.err('Selecione primeiro um objeto de referência.')
          end
          found =
            case action
            when 'material'
              mat = ref.respond_to?(:material) ? ref.material : nil
              ents.select { |e| e.respond_to?(:material) && e.material == mat && !e.is_a?(Sketchup::Edge) }
            when 'etiqueta'
              ents.select { |e| e.respond_to?(:layer) && e.layer == ref.layer }
            when 'componente'
              return H.err('A referência precisa ser um componente.') unless ref.is_a?(Sketchup::ComponentInstance) && !ref.is_a?(Sketchup::Group)
              ref.definition.instances.select { |i| ents.include?(i) }
            when 'inverter'
              cur = sel.to_a
              ents.reject { |e| cur.include?(e) || (e.is_a?(Sketchup::Edge) && e.faces.any? { |f| cur.include?(f) }) }
            when 'soltas'
              ents.grep(Sketchup::Edge).select { |e| e.faces.empty? }
            when 'costas'
              ents.grep(Sketchup::Face).select { |f| f.normal.z < -0.98 && f.vertices.map { |v| v.position.z }.max <= lowest(ents) + 0.5.cm }
            when 'escondidos'
              ents.select { |e| e.respond_to?(:hidden?) && e.hidden? }
            end
          sel.clear
          sel.add(found)
          H.ok("#{found.size} item(ns) #{NAMES[action]} selecionado(s).", stats: [['Selecionados', found.size.to_s]])
        end

        # piso de baixo: face virada para baixo na menor altura costuma ser piso desenhado de costas
        def lowest(ents)
          zs = ents.grep(Sketchup::Face).flat_map { |f| f.vertices.map { |v| v.position.z } }
          zs.empty? ? 0 : zs.min
        end

        Registry.register(:smart_select, name: 'Seleção inteligente', tab: :base, package: :base, handler: self,
                                         desc: 'Seleciona tudo do mesmo material, etiqueta ou componente, inverte e acha sujeira.',
                                         steps: ['Selecione uma referência', 'Escolha o critério', 'Pronto'])
      end
    end
  end
end
