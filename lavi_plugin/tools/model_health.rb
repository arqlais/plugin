# Saúde do modelo: encontra e corrige o que deixa o arquivo pesado ou bagunçado

module LAVIStudio
  module Plugin
    module Tools
      module ModelHealth
        extend self
        H = Helpers

        def handle(action, p)
          case action
          when 'scan' then scan
          when 'fix'
            done = []
            H.operation('lavi · Saúde do modelo') do
              done << purge if p['purge'] != false
              done << loose if p['loose'] == true || p['loose'] == 'true'
              done << back if p['back'] != false
              done << tiny if p['tiny'] == true || p['tiny'] == 'true'
            end
            res = scan
            res[:msg] = done.compact.join(' · ')
            res[:msg] = 'Nada para corrigir.' if res[:msg].empty?
            res
          else
            H.err('Ação desconhecida.')
          end
        end

        def scan
          m = H.model
          s = Hash.new(0)
          depth = 0
          used_mats = {}
          walk = lambda do |ents, d|
            depth = d if d > depth
            ents.each do |e|
              case e
              when Sketchup::Face
                s[:faces] += 1
                used_mats[e.material] = true if e.material
                used_mats[e.back_material] = true if e.back_material
                s[:back] += 1 if e.material.nil? && e.back_material
              when Sketchup::Edge
                s[:edges] += 1
                s[:tiny] += 1 if e.length < 0.04
              end
              s[:hidden] += 1 if e.respond_to?(:hidden?) && e.hidden?
              if H.instance?(e)
                used_mats[e.material] = true if e.material
                walk.call(H.entities_of(e), d + 1)
              end
            end
          end
          walk.call(m.entities, 0)
          s[:loose] = m.entities.grep(Sketchup::Edge).count { |e| e.faces.empty? }
          unused_defs = m.definitions.count { |d| !d.image? && d.instances.empty? && !d.group? }
          unused_mats = m.materials.count { |mt| !used_mats[mt] }
          size = m.path.to_s.empty? ? 0 : (File.size(m.path) rescue 0)
          stats = [
            ['Faces', H.br(s[:faces], 0), nil], ['Arestas', H.br(s[:edges], 0), nil],
            ['Componentes sem uso', unused_defs.to_s, unused_defs.zero?],
            ['Materiais sem uso', unused_mats.to_s, unused_mats.zero?],
            ['Linhas soltas (fora de grupo)', s[:loose].to_s, s[:loose].zero?],
            ['Faces pintadas só no verso', s[:back].to_s, s[:back].zero?],
            ['Arestas minúsculas (< 1 mm)', s[:tiny].to_s, s[:tiny] < 20],
            ['Itens ocultos', s[:hidden].to_s, nil],
            ['Profundidade de grupos', depth.to_s, depth < 8]
          ]
          stats << ['Tamanho do arquivo', "#{H.br(size / 1048576.0, 1)} MB", size < 80 * 1048576] if size > 0
          problems = stats.count { |r| r[2] == false }
          H.ok(problems.zero? ? 'Modelo saudável!' : "#{problems} ponto(s) de atenção.", stats: stats, score: [100 - problems * 12, 10].max)
        end

        def purge
          m = H.model
          before = m.definitions.size + m.materials.size + m.layers.size
          m.definitions.purge_unused
          m.materials.purge_unused
          m.layers.purge_unused
          m.styles.purge_unused if m.styles.respond_to?(:purge_unused)
          after = m.definitions.size + m.materials.size + m.layers.size
          "#{before - after} itens sem uso removidos"
        end

        def loose
          edges = H.model.entities.grep(Sketchup::Edge).select { |e| e.faces.empty? }
          n = edges.size
          H.model.entities.erase_entities(edges) if n > 0
          "#{n} linhas soltas apagadas"
        end

        def back
          n = 0
          fix = lambda do |ents|
            ents.grep(Sketchup::Face).each do |f|
              next unless f.material.nil? && f.back_material
              f.material = f.back_material
              n += 1
            end
          end
          fix.call(H.model.entities)
          H.model.definitions.each { |d| fix.call(d.entities) unless d.image? }
          "#{n} faces com material passado para a frente"
        end

        def tiny
          n = 0
          H.model.definitions.each do |d|
            next if d.image?
            edges = d.entities.grep(Sketchup::Edge).select { |e| e.length < 0.04 && e.faces.empty? }
            n += edges.size
            d.entities.erase_entities(edges) unless edges.empty?
          end
          "#{n} arestas minúsculas soltas apagadas"
        end

        Registry.register(:model_health, name: 'Saúde do modelo', tab: :base, package: :base, handler: self,
                                         desc: 'Encontra o que pesa e bagunça o arquivo e corrige com um clique.',
                                         steps: ['Analisar', 'Marcar o que corrigir', 'Corrigir'])
      end
    end
  end
end
