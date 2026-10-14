# Selecionar iguais e substituir componentes

module LAVIStudio
  module Plugin
    module Tools
      module Replace
        extend self
        H = Helpers

        def handle(action, p)
          case action
          when 'list'
            defs = H.model.definitions.reject { |d| d.group? || d.image? || d.instances.empty? }
            H.ok("#{defs.size} componentes no modelo.", defs: defs.sort_by(&:name).map { |d| [d.name, d.instances.size] })
          when 'select_same'
            inst = H.selection.grep(Sketchup::ComponentInstance).first
            return H.err('Selecione um componente.') unless inst
            all = inst.definition.instances
            H.selection.clear
            H.selection.add(all)
            H.ok("#{all.size} cópias de \"#{inst.definition.name}\" selecionadas.")
          when 'replace'
            defn = H.model.definitions[p['def'].to_s]
            return H.err('Escolha o componente novo na lista.') unless defn
            insts = H.selection.grep(Sketchup::ComponentInstance)
            return H.err('Selecione os componentes que serão trocados.') if insts.empty?
            H.operation('lavi · Substituir') do
              insts.each do |i|
                i.definition = defn
              end
            end
            H.ok("#{insts.size} componente(s) trocado(s) por \"#{defn.name}\".")
          else
            H.err('Ação desconhecida.')
          end
        end

        Registry.register(:replace, name: 'Selecionar e substituir', tab: :base, package: :base, handler: self,
                                    desc: 'Seleciona todas as cópias e troca por outro componente mantendo a posição.',
                                    steps: ['Selecione um componente', 'Selecionar iguais', 'Escolha o novo e troque'])
      end
    end
  end
end
