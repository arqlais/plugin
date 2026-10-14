# Arestas para render: suavizar (as curvas ficam lisas), esconder todas as linhas de um bloco,
# mostrar de volta, e ligar/desligar as linhas no estilo da cena.

module LAVIStudio
  module Plugin
    module Tools
      module Edges
        extend self
        H = Helpers

        def handle(action, p)
          case action
          when 'estilo' then style(p)
          when 'suavizar', 'ocultar', 'mostrar' then run(action, p)
          else H.err('Ação desconhecida.')
          end
        end

        def run(action, p)
          sel = H.selection.to_a
          scope = sel.empty? ? H.model.active_entities.to_a : sel
          lim = H.num(p['angulo'], 30) * Math::PI / 180
          n = 0
          H.operation("lavi · #{{ 'suavizar' => 'Suavizar', 'ocultar' => 'Ocultar', 'mostrar' => 'Mostrar' }[action]} arestas") do
            each_edge(scope) do |e|
              case action
              when 'suavizar'
                fs = e.faces
                next unless fs.size == 2
                next if fs[0].normal.angle_between(fs[1].normal) > lim
                e.soft = true
                e.smooth = true
              when 'ocultar'
                next if e.hidden?
                e.hidden = true
              when 'mostrar'
                next unless e.hidden? || e.soft? || e.smooth?
                e.hidden = false
                e.soft = false
                e.smooth = false
              end
              n += 1
            end
          end
          where = sel.empty? ? 'no modelo todo' : 'na seleção'
          H.ok({ 'suavizar' => "#{n} aresta(s) suavizada(s) #{where}.", 'ocultar' => "#{n} aresta(s) escondida(s) #{where}.",
                 'mostrar' => "#{n} aresta(s) visível(is) de novo #{where}." }[action], stats: [['Arestas', n.to_s]])
        end

        # percorre as arestas (entrando em grupos e componentes, cada definição uma vez)
        def each_edge(items, seen = {}, &block)
          items.each do |e|
            if e.is_a?(Sketchup::Edge)
              yield e
            elsif e.is_a?(Sketchup::Face)
              e.edges.each(&block)
            elsif H.instance?(e)
              d = e.definition
              next if seen[d]
              seen[d] = true
              each_edge(H.entities_of(e).to_a, seen, &block)
            end
          end
        end

        # linhas no estilo: arestas e perfis ligados/desligados
        def style(p)
          ro = H.model.rendering_options
          on = p['linhas'] == true || p['linhas'] == 'true'
          begin
            ro['EdgeDisplayMode'] = on ? 1 : 0
            ro['DrawSilhouettes'] = on
            ro['DrawDepthQue'] = false unless on
            ro['ExtendLines'] = false unless on
          rescue StandardError
            nil
          end
          H.ok(on ? 'Linhas ligadas no estilo.' : 'Linhas desligadas no estilo (só as faces aparecem).')
        end

        Registry.register(:edges, name: 'Arestas e linhas', tab: :render, package: :pres, handler: self,
                                  desc: 'Suaviza curvas, esconde as linhas de blocos com muitas arestas e tira as linhas do estilo.',
                                  steps: ['Selecione os blocos (ou nada = tudo)', 'Suavizar ou esconder', 'Pronto para render'])
      end
    end
  end
end
