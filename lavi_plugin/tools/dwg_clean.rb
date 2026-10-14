# Limpar planta DWG: achata tudo na mesma altura, tira textos/cotas/hachuras soltas,
# apaga linhas minúsculas, explode blocos e fecha as faces — deixa a planta pronta para modelar.

module LAVIStudio
  module Plugin
    module Tools
      module DwgClean
        extend self
        H = Helpers
        # (v0.12: faz parte de outra ferramenta do painel, sem botão próprio)

        def handle(action, p)
          return gaps_only(p) if action == 'gaps'
          return H.err('Ação desconhecida.') unless action == 'clean'
          sel = H.selection.to_a
          return H.err('Selecione a planta importada (o bloco do DWG ou as linhas).') if sel.empty?
          st = Hash.new(0)
          marks = []
          H.operation('lavi · Limpar DWG') do
            targets(sel, p, st).each { |ents, tr, list| clean(ents, tr, list, p, st, marks) }
          end
          stats = [['Pontos achatados', st[:flat].to_s], ['Aberturas fechadas', st[:closed].to_s], ['Faces criadas', st[:faces].to_s],
                   ['Anotações removidas', st[:notes].to_s], ['Linhas minúsculas', st[:tiny].to_s]]
          stats << ['Blocos explodidos', st[:exploded].to_s] if st[:exploded] > 0
          stats << ['Pontas ainda abertas', marks.size.to_s, false] unless marks.empty?
          msg = marks.empty? ? 'Planta limpa e fechada. Agora dá para usar DWG → Paredes ou desenhar por cima.' :
                               "Planta limpa. Ficaram #{marks.size} ponta(s) abertas longe demais para fechar sozinho: estão selecionadas e marcadas (etiqueta \"lavi · Aberturas\")."
          H.ok(msg, stats: stats)
        end

        # Só procura e mostra as pontas abertas (não mexe em nada)
        def gaps_only(p)
          sel = H.selection.to_a
          scope = sel.empty? ? [[H.model.active_entities, IDENTITY]] : sel.map { |e| H.instance?(e) ? [H.entities_of(e), e.transformation] : nil }.compact
          scope << [H.model.active_entities, IDENTITY] if sel.any? { |e| e.is_a?(Sketchup::Edge) }
          found = []
          H.operation('lavi · Mostrar aberturas') do
            scope.uniq.each do |ents, tr|
              open_ends(ents.grep(Sketchup::Edge)).each { |v| found << [ents, tr, v] }
            end
            mark(found)
          end
          return H.ok('Nenhuma ponta aberta: as linhas estão todas ligadas.') if found.empty?
          H.ok("#{found.size} ponta(s) aberta(s) marcadas e selecionadas. Use Limpar planta para fechar as que estão perto.",
               stats: [['Pontas abertas', found.size.to_s, false]])
        end

        # vértices com uma linha só (ponta solta)
        def open_ends(edges)
          edges.select(&:valid?).flat_map(&:vertices).uniq.select { |v| v.edges.size == 1 }
        end

        # liga cada ponta solta à ponta mais perto (ou à linha mais perto) dentro da tolerância
        def close_gaps(ents, edges, tol, st)
          # encontro em T: a ponta encosta no meio de outra linha, mas sem vértice → divide a linha ali
          open_ends(edges).each do |a|
            next unless a.valid? && a.edges.size == 1
            pa = a.position
            own = a.edges[0]
            hit = ents.grep(Sketchup::Edge).find do |e|
              next false if e.equal?(own) || !e.valid? || e.vertices.include?(a)
              q = closest_on(e, pa)
              pa.distance(q) < 0.01.cm && q.distance(e.start.position) > 0.01.cm && q.distance(e.end.position) > 0.01.cm
            end
            next unless hit && hit.respond_to?(:split)
            hit.split(pa)
            st[:closed] += 1
          end
          ends = open_ends(ents.grep(Sketchup::Edge))
          used = {}
          ends.each do |a|
            next if used[a] || !a.valid? || a.edges.size != 1
            pa = a.position
            best = nil
            ends.each do |b|
              next if b.equal?(a) || used[b] || !b.valid? || b.edges.size != 1
              d = pa.distance(b.position)
              best = [d, b.position, b] if d <= tol && (best.nil? || d < best[0])
            end
            unless best
              own = a.edges[0]
              ents.grep(Sketchup::Edge).each do |e|
                next if e.equal?(own) || !e.valid?
                q = closest_on(e, pa)
                d = pa.distance(q)
                best = [d, q, nil] if d <= tol && d > 1e-6 && (best.nil? || d < best[0])
              end
            end
            next unless best
            ents.add_line(pa, best[1])
            used[a] = true
            used[best[2]] = true if best[2]
            st[:closed] += 1
          end
        end

        def closest_on(e, q)
          a = e.start.position
          b = e.end.position
          d = b - a
          l2 = d.dot(d)
          return a if l2 < 1e-12
          t = [[(q - a).dot(d) / l2, 0].max, 1].min
          Geom::Point3d.new(a.x + d.x * t, a.y + d.y * t, a.z + d.z * t)
        end

        # marca as pontas abertas com um ponto-guia e seleciona as linhas delas
        def mark(found)
          layer = H.tag('lavi · Aberturas')
          sel = H.selection
          sel.clear
          found.each do |ents, _tr, v|
            c = ents.add_cpoint(v.position)
            c.layer = layer if c.respond_to?(:layer=)
            sel.add(v.edges) if ents == H.model.active_entities
          end
          if found.any?
            insts = H.selection.to_a
            H.model.active_view.zoom(insts) rescue nil unless insts.empty?
          end
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

        def clean(ents, tr, list, p, st, marks = [])
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
          if p['fechar'] != false && p['fechar'] != 'false'
            close_gaps(ents, ents.grep(Sketchup::Edge), H.cm(H.num(p['tol'], 2)), st)
          end
          if p['faces'] != false && p['faces'] != 'false'
            before = ents.grep(Sketchup::Face).size
            ents.grep(Sketchup::Edge).each { |e| e.find_faces if e.valid? && e.faces.empty? }
            st[:faces] += ents.grep(Sketchup::Face).size - before
          end
          left = open_ends(ents.grep(Sketchup::Edge))
          found = left.map { |v| [ents, tr, v] }
          mark(found) if !found.empty? && p['marcar'] != false && p['marcar'] != 'false'
          marks.concat(found)
        end

      end
    end
  end
end
