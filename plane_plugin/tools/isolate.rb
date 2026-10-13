# Isolar seleção: esconde todo o resto para trabalhar numa parte; um clique mostra tudo de volta

module PlaneLA
  module Plugin
    module Tools
      module Isolate
        extend self
        H = Helpers

        def handle(action, p)
          m = H.model
          case action
          when 'isolate'
            sel = H.selection.to_a
            return H.err('Selecione o que quer manter visível.') if sel.empty?
            n = 0
            H.operation('Planê · Isolar seleção') do
              m.active_entities.each do |e|
                next if sel.include?(e) || !e.respond_to?(:hidden?) || e.hidden?
                next if e.is_a?(Sketchup::Edge) && e.faces.any? { |f| sel.include?(f) }
                e.hidden = true
                e.set_attribute(H::DICT, 'isolado', true)
                n += 1
              end
            end
            m.active_view.zoom(sel) if p['zoom'] != false && p['zoom'] != 'false'
            H.ok("#{n} itens escondidos. Clique em Mostrar tudo para voltar.")
          when 'restore'
            n = 0
            H.operation('Planê · Mostrar tudo') do
              each_marked(m.entities) do |e|
                e.hidden = false
                e.delete_attribute(H::DICT, 'isolado')
                n += 1
              end
            end
            H.ok(n.zero? ? 'Nada estava isolado.' : "#{n} itens visíveis de novo.")
          when 'xray'
            ro = m.rendering_options
            ro['ModelTransparency'] = !ro['ModelTransparency']
            H.ok(ro['ModelTransparency'] ? 'Raio X ligado.' : 'Raio X desligado.')
          else
            H.err('Ação desconhecida.')
          end
        end

        # procura no modelo inteiro (o isolamento pode ter sido feito dentro de um grupo)
        def each_marked(ents, seen = {}, &block)
          ents.each do |e|
            yield e if e.respond_to?(:get_attribute) && e.get_attribute(H::DICT, 'isolado')
            next unless H.instance?(e)
            d = e.definition
            next if seen[d]
            seen[d] = true
            each_marked(d.entities, seen, &block)
          end
        end

        Registry.register(:isolate, name: 'Isolar seleção', tab: :base, package: :base, handler: self,
                                    desc: 'Esconde todo o resto para trabalhar numa parte; Mostrar tudo devolve.',
                                    steps: ['Selecione o que quer ver', 'Isolar', 'Mostrar tudo para voltar'])
      end
    end
  end
end
