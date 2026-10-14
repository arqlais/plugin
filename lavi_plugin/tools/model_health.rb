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
          when 'heavy' then heavy
          when 'select_heavy' then select_heavy(p)
          when 'proxy' then proxy(p)
          when 'unproxy' then unproxy
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

        # ---- peso: o que mais pesa (faces × cópias) e caixas no lugar ---------------
        def heavy
          memo = {}
          count = lambda do |d|
            memo[d] ||= begin
              memo[d] = 0
              d.entities.grep(Sketchup::Face).size +
                d.entities.to_a.select { |e| H.instance?(e) }.sum { |i| count.call(i.definition) }
            end
          end
          rows = H.model.definitions.reject { |d| d.image? || d.instances.empty? || d.get_attribute(H::DICT, 'proxy_of') }.map do |d|
            f = count.call(d)
            [d.name, f, d.instances.size, f * d.instances.size, d.group?]
          end
          rows.sort_by! { |r| -r[3] }
          total = H.model.entities.grep(Sketchup::Face).size + H.model.entities.to_a.select { |e| H.instance?(e) }.sum { |i| count.call(i.definition) }
          big = H.model.materials.count { |mt| mt.texture && [mt.texture.image_width, mt.texture.image_height].max > 2048 }
          top = rows.reject { |r| r[4] }.first(12)
          H.ok(top.empty? ? 'Nenhum componente no modelo.' : 'Os componentes que mais pesam estão em cima. Selecione e troque por caixa enquanto modela.',
               stats: [['Faces no modelo', H.br(total, 0)], ['Componentes', rows.count { |r| !r[4] }.to_s],
                       ['Texturas maiores que 2K', big.to_s, big < 6]],
               heavy: top.map { |n, f, c, t, _g| [n, f, c, total > 0 ? (100.0 * t / total).round(1) : 0] })
        end

        def select_heavy(p)
          d = H.model.definitions[p['def'].to_s]
          return H.err('Componente não encontrado.') unless d
          ins = d.instances.select { |i| i.parent == H.model.active_entities.parent || i.parent.is_a?(Sketchup::Model) }
          ins = d.instances if ins.empty?
          H.selection.clear
          H.selection.add(ins)
          H.ok("#{ins.size} cópia(s) de \"#{d.name}\" selecionada(s).")
        end

        # troca os componentes selecionados (todas as cópias) por uma caixa leve do mesmo tamanho
        def proxy(p)
          sel = H.selection.to_a.select { |e| H.instance?(e) }
          return H.err('Selecione os componentes pesados (árvores, sofás, carros…).') if sel.empty?
          todas = p['todas'] != false && p['todas'] != 'false'
          n = 0
          saved = 0
          H.operation('lavi · Trocar por caixa') do
            mat = H.material('lavi Caixa', 'D6B3AB', 0.45)
            sel.each do |i|
              i = i.to_component if i.is_a?(Sketchup::Group) && i.respond_to?(:to_component)
              next unless i.respond_to?(:definition=)
              d = i.definition
              next if d.get_attribute(H::DICT, 'proxy_of')
              targets = todas ? d.instances.to_a : [i] # antes de criar a caixa (ela guarda uma cópia do original)
              pd = box_for(d, mat)
              targets.each do |t|
                t.definition = pd
                n += 1
              end
              saved += d.entities.grep(Sketchup::Face).size * targets.size
            end
          end
          return H.err('Nada para trocar (só componentes e grupos).') if n.zero?
          H.ok("#{n} cópia(s) viraram caixa. Antes do render, clique em Voltar os originais.",
               stats: [['Trocadas', n.to_s], ['Faces a menos na tela', H.br(saved, 0)]])
        end

        # caixa com o tamanho do componente; guarda o original escondido dentro dela (não some ao limpar)
        def box_for(d, mat)
          name = "lavi caixa · #{d.name}"
          pd = H.model.definitions[name]
          return pd if pd && pd.get_attribute(H::DICT, 'proxy_of')
          pd = H.model.definitions.add(name)
          b = d.bounds
          x0, y0, z0 = b.min.x, b.min.y, b.min.z
          x1, y1, z1 = b.max.x, b.max.y, b.max.z
          z1 = z0 + 0.1 if (z1 - z0).abs < 1e-3
          f = pd.entities.add_face([x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0])
          if f
            f.reverse! if f.normal.z > 0
            f.pushpull(-(z1 - z0))
          end
          pd.entities.grep(Sketchup::Face).each { |x| x.material = mat }
          keep = pd.entities.add_instance(d, IDENTITY)
          keep.hidden = true
          pd.set_attribute(H::DICT, 'proxy_of', d.name)
          pd
        end

        def unproxy
          n = 0
          gone = []
          H.operation('lavi · Voltar os originais') do
            H.model.definitions.to_a.each do |pd|
              next unless pd.get_attribute(H::DICT, 'proxy_of')
              keep = pd.entities.to_a.find { |e| e.respond_to?(:definition) && e.hidden? }
              next unless keep
              pd.instances.each do |i|
                i.definition = keep.definition
                n += 1
              end
              gone << pd
            end
            gone.each { |pd| H.model.definitions.remove(pd) if H.model.definitions.respond_to?(:remove) }
          end
          return H.err('Não há caixas no modelo.') if n.zero?
          H.ok("#{n} cópia(s) voltaram ao original. Pronto para o render.")
        end

        Registry.register(:model_health, name: 'Saúde do modelo', tab: :base, package: :base, handler: self,
                                         desc: 'Mostra o que pesa, limpa e corrige; troca componentes pesados por caixas enquanto modela.',
                                         steps: ['Analisar', 'Marcar o que corrigir', 'Corrigir'])
      end
    end
  end
end
