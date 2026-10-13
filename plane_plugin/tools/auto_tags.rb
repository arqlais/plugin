# Etiquetas automáticas: organiza o modelo por tipo de objeto e liga/desliga com um clique

module Plane
  module Plugin
    module Tools
      module AutoTags
        extend self
        H = Helpers

        KIND_TAGS = {
          'wall' => 'Planê · Paredes', 'door' => 'Planê · Esquadrias', 'window' => 'Planê · Esquadrias',
          'stairs' => 'Planê · Escadas', 'roof' => 'Planê · Cobertura', 'floor_tiling' => 'Planê · Piso',
          'wall_tiling' => 'Planê · Revestimento parede', 'baseboard' => 'Planê · Rodapé',
          'ceiling' => 'Planê · Forro', 'cabinet' => 'Planê · Marcenaria'
        }.freeze

        KEYWORDS = [
          [/cadeira|mesa|sof[aá]|cama|poltrona|banco|banqueta|rack|estante|aparador|chair|table|sofa|bed/i, 'Mobiliário'],
          [/[aá]rvore|planta|vaso de|folhag|grama|tree|plant/i, 'Vegetação'],
          [/pessoa|people|human|homem|mulher|crian[cç]a/i, 'Pessoas'],
          [/lumin[aá]ria|l[aâ]mpada|pendente|spot|arandela|lamp|light/i, 'Iluminação'],
          [/bacia|sanit[aá]rio|cuba|pia|chuveiro|torneira|lavat[oó]rio|ducha|toilet|sink/i, 'Louças e metais'],
          [/geladeira|refrigerador|fog[aã]o|forno|micro|tv|televis|cooktop|coifa|lava/i, 'Eletros'],
          [/\bcarro|\bcar\b|\bmoto|bicicleta/i, 'Veículos'],
          [/cortina|persiana|tapete|almofada|quadro|curtain|rug/i, 'Decoração']
        ].freeze

        def handle(action, p)
          case action
          when 'organize'
            over = p['sobrescrever'] == true || p['sobrescrever'] == 'true'
            count = Hash.new(0)
            H.operation('Planê · Etiquetas') do
              H.model.entities.each do |e|
                next unless H.instance?(e)
                next unless over || e.layer.nil? || e.layer == H.model.layers[0]
                name = tag_for(e)
                next unless name
                e.layer = H.tag(name)
                count[name] += 1
              end
            end
            return H.ok('Nada novo para organizar. Marque "Refazer as já etiquetadas" para reorganizar tudo.', tags: list) if count.empty?
            H.ok("#{count.values.sum} objetos organizados em #{count.size} etiquetas.", tags: list)
          when 'list'
            H.ok('Etiquetas do modelo.', tags: list)
          when 'toggle'
            layer = H.model.layers[p['tag'].to_s]
            return H.err('Etiqueta não encontrada.') unless layer
            H.operation('Planê · Etiqueta') { layer.visible = !layer.visible? }
            H.ok("#{layer.name} #{layer.visible? ? 'visível' : 'escondida'}.", tags: list)
          else
            H.err('Ação desconhecida.')
          end
        end

        def tag_for(e)
          kind = H.kind_of(e) || (e.respond_to?(:definition) && H.kind_of(e.definition))
          return KIND_TAGS[kind] if kind && KIND_TAGS[kind]
          name = e.is_a?(Sketchup::ComponentInstance) ? e.definition.name : e.name.to_s
          KEYWORDS.each { |rx, tag| return tag if name =~ rx }
          nil
        end

        def list
          counts = Hash.new(0)
          H.model.entities.each { |e| counts[e.layer.name] += 1 if e.respond_to?(:layer) && e.layer }
          H.model.layers.to_a.drop(1).map { |l| [l.name, l.visible?, counts[l.name]] }
        end

        Registry.register(:auto_tags, name: 'Etiquetas automáticas', tab: :base, package: :base, handler: self,
                                      desc: 'Organiza móveis, plantas, luminárias e itens do Planê em etiquetas.',
                                      steps: ['Organizar', 'Ligue e desligue cada etiqueta'])
      end
    end
  end
end
