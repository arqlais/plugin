# Medir seleção: soma de áreas, comprimentos, volumes e contagem do que está selecionado

module LAVIStudio
  module Plugin
    module Tools
      module Measure
        extend self
        H = Helpers
        CUIN_TO_M3 = 0.000016387064

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'run'
          sel = H.selection.to_a
          return H.err('Selecione faces, linhas, grupos ou componentes.') if sel.empty?
          deep = p['dentro'] != false && p['dentro'] != 'false'
          s = Hash.new(0.0)
          walk(sel, IDENTITY, s, deep, true)
          stats = []
          stats << ['Área total', "#{H.br(s[:area])} m²"] if s[:faces] > 0
          stats << ['Piso (faces p/ cima)', "#{H.br(s[:piso])} m²"] if s[:piso] > 0
          stats << ['Paredes (faces em pé)', "#{H.br(s[:parede])} m²"] if s[:parede] > 0
          stats << ['Faces', H.br(s[:faces], 0)] if s[:faces] > 0
          stats << ['Comprimento das linhas', "#{H.br(s[:len])} m"] if s[:edges] > 0
          stats << ['Linhas', H.br(s[:edges], 0)] if s[:edges] > 0
          stats << ['Volume (sólidos)', "#{H.br(s[:vol], 3)} m³"] if s[:solids] > 0
          stats << ['Grupos/componentes', H.br(s[:inst], 0)] if s[:inst] > 0
          bb = Geom::BoundingBox.new
          sel.each { |e| bb.add(e.bounds) if e.respond_to?(:bounds) }
          unless bb.empty?
            stats << ['Caixa (L × P × A)', "#{H.br(H.to_cm(bb.width), 1)} × #{H.br(H.to_cm(bb.height), 1)} × #{H.br(H.to_cm(bb.depth), 1)} cm"]
          end
          H.ok('Medidas da seleção.', stats: stats)
        end

        def walk(ents, tr, s, deep, top)
          ents.each do |e|
            case e
            when Sketchup::Face
              a = H.m2(H.face_area(e, tr))
              s[:area] += a
              s[:faces] += 1
              n = e.normal.transform(tr)
              n.normalize!
              s[:piso] += a if n.z > 0.98
              s[:parede] += a if n.z.abs < 0.02
            when Sketchup::Edge
              s[:len] += H.to_m(e.start.position.transform(tr).distance(e.end.position.transform(tr)))
              s[:edges] += 1
            else
              next unless H.instance?(e)
              s[:inst] += 1 if top
              if top && e.respond_to?(:manifold?) && e.manifold?
                s[:vol] += e.volume.to_f.abs * CUIN_TO_M3
                s[:solids] += 1
              end
              walk(H.entities_of(e).to_a, tr * e.transformation, s, deep, false) if deep
            end
          end
        end

        Registry.register(:measure, name: 'Medir seleção', tab: :base, package: :base, handler: self,
                                    desc: 'Soma na hora área, comprimento, volume e medidas do que está selecionado.',
                                    steps: ['Selecione o que quer medir', 'Clique em Medir'])
      end
    end
  end
end
