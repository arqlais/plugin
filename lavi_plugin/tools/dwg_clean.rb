# Limpar planta DWG: achata tudo na mesma altura, tira textos/cotas/hachuras soltas,
# apaga linhas minúsculas, explode blocos e fecha as faces — deixa a planta pronta para modelar.

module LAVIStudio
  module Plugin
    module Tools
      module DwgClean
        extend self
        H = Helpers

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'clean'
          sel = H.selection.to_a
          return H.err('Selecione a planta importada (o bloco do DWG ou as linhas).') if sel.empty?
          st = Hash.new(0)
          H.operation('lavi · Limpar DWG') do
            targets(sel, p, st).each { |ents, tr, list| clean(ents, tr, list, p, st) }
          end
          stats = [['Pontos achatados', st[:flat].to_s], ['Faces criadas', st[:faces].to_s],
                   ['Anotações removidas', st[:notes].to_s], ['Linhas minúsculas', st[:tiny].to_s]]
          stats << ['Blocos explodidos', st[:exploded].to_s] if st[:exploded] > 0
          H.ok('Planta limpa. Agora dá para usar DWG → Paredes ou desenhar por cima.', stats: stats)
        end

        # [[entities, transformação, entidades a tratar (nil = todas)]]
        def targets(sel, p, st)
          out = []
          loose = sel.reject { |e| H.instance?(e) }
          out << [H.model.active_entities, IDENTITY, loose] unless loose.empty?
          sel.select { |e| H.instance?(e) }.each do |inst|
            if p['explodir'] == true || p['explodir'] == 'true'
              ents = inst.parent.respond_to?(:entities) ? inst.parent.entities : H.model.active_entities
              loose2 = explode_all(inst, st)
              out << [ents, IDENTITY, loose2]
            else
              inst.make_unique if inst.respond_to?(:make_unique)
              out << [H.entities_of(inst), inst.transformation, nil]
            end
          end
          out
        end

        # explode o bloco e os blocos de dentro; devolve tudo o que sobrou solto
        def explode_all(inst, st)
          pending = [inst]
          loose = []
          until pending.empty?
            e = pending.shift
            next unless e.valid?
            st[:exploded] += 1
            Array(e.explode).each do |x|
              next unless x.respond_to?(:valid?) && x.valid?
              H.instance?(x) ? pending << x : loose << x
            end
          end
          loose
        end

        def clean(ents, tr, list, p, st)
          items = (list || ents.to_a).select(&:valid?)
          if p['anotacoes'] != false && p['anotacoes'] != 'false'
            notes = items.select { |e| e.is_a?(Sketchup::Text) || e.is_a?(Sketchup::Dimension) || e.is_a?(Sketchup::ConstructionPoint) || e.is_a?(Sketchup::ConstructionLine) }
            st[:notes] += notes.size
            ents.erase_entities(notes) unless notes.empty?
          end
          edges = items.grep(Sketchup::Edge).select(&:valid?)
          if p['achatar'] != false && p['achatar'] != 'false'
            z = H.cm(H.num(p['z'], 0))
            inv = tr.inverse
            verts = edges.flat_map(&:vertices).uniq
            vecs = verts.map do |v|
              w = v.position.transform(tr)
              Geom::Vector3d.new(0, 0, z - w.z).transform(inv)
            end
            moving = verts.each_index.select { |i| vecs[i].length > 1e-6 }
            unless moving.empty?
              ents.transform_by_vectors(moving.map { |i| verts[i] }, moving.map { |i| vecs[i] })
              st[:flat] += moving.size
            end
            edges = edges.select(&:valid?)
          end
          min = H.mm(H.num(p['minimo'], 1))
          tiny = edges.select { |e| e.valid? && e.length < min && e.faces.empty? }
          st[:tiny] += tiny.size
          ents.erase_entities(tiny) unless tiny.empty?
          return unless p['faces'] != false && p['faces'] != 'false'
          before = ents.grep(Sketchup::Face).size
          ents.grep(Sketchup::Edge).each { |e| e.find_faces if e.valid? && e.faces.empty? }
          st[:faces] += ents.grep(Sketchup::Face).size - before
        end

        Registry.register(:dwg_clean, name: 'Limpar DWG', tab: :arq, package: :arq, handler: self,
                                      desc: 'Achata a planta importada, tira textos e cotas, apaga sujeira e fecha as faces.',
                                      steps: ['Selecione o DWG importado', 'Escolha o que limpar', 'Limpar'])
      end
    end
  end
end
