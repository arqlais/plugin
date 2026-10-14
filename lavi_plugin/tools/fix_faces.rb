# Corrigir faces invertidas: vira as faces "azuis" (de costas) para fora, deixa cada peça com o
# mesmo sentido e passa a pintura do verso para a frente. Essencial antes de renderizar.

module LAVIStudio
  module Plugin
    module Tools
      module FixFaces
        extend self
        H = Helpers

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'fix'
          sel = H.selection.to_a
          scope = sel.empty? ? H.model.active_entities.to_a : sel
          st = Hash.new(0)
          H.operation('lavi · Corrigir faces') do
            seen = {}
            collections(scope, seen).each { |faces| fix(faces, p, st) }
          end
          H.ok(st[:flipped].zero? && st[:paint].zero? ? 'Todas as faces já estavam viradas para fora.' : 'Faces corrigidas.',
               stats: [['Faces lidas', st[:faces].to_s], ['Faces viradas', st[:flipped].to_s], ['Pinturas passadas para a frente', st[:paint].to_s]])
        end

        # faces agrupadas por coleção (cada grupo/componente é tratado uma vez)
        def collections(items, seen)
          out = []
          loose = items.grep(Sketchup::Face)
          out << loose unless loose.empty?
          items.select { |e| H.instance?(e) }.each do |inst|
            d = inst.definition
            next if seen[d]
            seen[d] = true
            ents = H.entities_of(inst).to_a
            fs = ents.grep(Sketchup::Face)
            out << fs unless fs.empty?
            out.concat(collections(ents.select { |e| H.instance?(e) }, seen))
          end
          out
        end

        def fix(faces, p, st)
          st[:faces] += faces.size
          if p['pintura'] != false && p['pintura'] != 'false'
            faces.each do |f|
              next unless f.back_material && !f.material
              f.material = f.back_material
              f.back_material = nil
              st[:paint] += 1
            end
          end
          set = faces.map { |f| [f, true] }.to_h
          done = {}
          faces.each do |f0|
            next if done[f0]
            comp = orient_component(f0, set, done, st)
            outward(comp, st)
          end
        end

        # deixa as faces ligadas pelo mesmo sentido (cada aresta percorrida ao contrário pelas duas faces)
        def orient_component(f0, set, done, st)
          comp = [f0]
          done[f0] = true
          queue = [f0]
          until queue.empty?
            f = queue.shift
            f.edges.each do |e|
              e.faces.each do |g|
                next if g == f || done[g] || !set[g]
                if e.reversed_in?(g) == e.reversed_in?(f)
                  g.reverse!
                  st[:flipped] += 1
                end
                done[g] = true
                comp << g
                queue << g
              end
            end
          end
          comp
        end

        # vira o conjunto todo se estiver olhando para dentro
        def outward(comp, st)
          inside = comp.map { |f| [f, true] }.to_h
          closed = comp.all? { |f| f.edges.all? { |e| e.faces.count { |g| inside[g] } == 2 } }
          if closed
            vol = comp.sum do |f|
              q = f.vertices[0].position
              n = f.normal
              f.area * (q.x * n.x + q.y * n.y + q.z * n.z)
            end
            flip = vol < 0
          else
            c = Geom::BoundingBox.new.add(comp.flat_map { |f| f.vertices.map(&:position) }).center
            score = comp.sum do |f|
              fc = f.bounds.center
              f.area * f.normal.dot(fc - c)
            end
            # superfície plana (piso solto): a frente fica para cima
            score = comp.sum { |f| f.area * f.normal.z } if score.abs < 1e-6 * comp.sum(&:area)
            flip = score < 0
          end
          return unless flip
          comp.each(&:reverse!)
          st[:flipped] += comp.size
        end

        Registry.register(:fix_faces, name: 'Corrigir faces invertidas', tab: :base, package: :base, handler: self,
                                      desc: 'Vira para fora as faces de costas (azuis) e passa a pintura do verso para a frente.',
                                      steps: ['Selecione (ou nada = modelo todo)', 'Corrigir', 'Pronto para render'])
      end
    end
  end
end
