# Recorte de cuba e cooktop no tampo (de um módulo LAVI ou de qualquer grupo de tampo)

module LAVIStudio
  module Plugin
    module Tools
      module Countertop
        extend self
        H = Helpers
        DA = 'dynamic_attributes'.freeze

        PRESETS = {
          'cuba'       => { larg: 50, prof: 40, fundo: 18 },
          'cuba_dupla' => { larg: 80, prof: 40, fundo: 18 },
          'cooktop'    => { larg: 56, prof: 49, fundo: 0 }
        }.freeze

        SINK = /cuba|pia|lavat|cook|fog[aã]o|tanque|sink|torneira-?cuba|cuba-?esculpida|ralo-?linear/i

        def handle(action, p)
          case action
          when 'run' then p['modo'] == 'medida' ? by_size(p) : by_block(p)
          when 'block' then by_block(p)
          when 'auto'
            on = p['auto'] != false && p['auto'] != 'false'
            H.set_pref('auto_recorte', on)
            H.ok(on ? 'Recorte automático ligado.' : 'Recorte automático desligado.')
          when 'mark' then mark_block(true)
          when 'unmark' then mark_block(false)
          when 'auto_on' then H.set_pref('auto_recorte', true); H.ok('Recorte automático ligado.')
          when 'auto_off' then H.set_pref('auto_recorte', false); H.ok('Recorte automático desligado.')
          when 'cut' then by_size(p)
          else H.err('Ação desconhecida.')
          end
        end

        def auto?
          H.pref('auto_recorte', true) != false
        end

        # o bloco é de cuba / cooktop? (pelo nome ou marcado pela pessoa)
        def sink?(inst)
          return false unless inst.is_a?(Sketchup::ComponentInstance) && !inst.is_a?(Sketchup::Group)
          d = inst.definition
          v = d.get_attribute(H::DICT, 'recorte')
          return v == true || v == 'true' unless v.nil?
          !!(d.name.to_s =~ SINK || inst.name.to_s =~ SINK)
        end

        def mark_block(on)
          blocks = H.selection.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) && !e.is_a?(Sketchup::Group) }
          return H.err('Selecione o bloco (componente) da cuba ou do cooktop.') if blocks.empty?
          blocks.map(&:definition).uniq.each { |d| d.set_attribute(H::DICT, 'recorte', on) }
          H.ok(on ? "Pronto: \"#{blocks[0].definition.name}\" sempre vai recortar o tampo ao ser colocado." :
                    "\"#{blocks[0].definition.name}\" não recorta mais sozinho.")
        end

        # ---- recorte pelo formato do bloco ---------------------------------------
        def by_block(p)
          blocks = H.selection.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) && !e.is_a?(Sketchup::Group) }
          blocks = H.selection.to_a.select { |e| H.instance?(e) && sink?(e) } if blocks.empty?
          return H.err('Selecione a cuba (ou o cooktop) que você colocou em cima do tampo.') if blocks.empty?
          done = []
          errs = []
          H.operation('lavi · Recorte pelo bloco') do
            blocks.each do |b|
              r = cut_for(b, p)
              r.is_a?(String) ? errs << r : done << r
            end
          end
          return H.err(errs.first) if done.empty?
          H.ok("Recorte feito em #{done.size} tampo(s) no formato do bloco.#{errs.empty? ? '' : " (#{errs.size} sem tampo embaixo)"}",
               stats: [['Recortes', done.size.to_s], ['Furo', done.map { |d| "#{H.br(d[0], 1)} × #{H.br(d[1], 1)} cm" }.uniq.join(', ')]])
        end

        # chamado pelo observador quando um bloco de cuba é colocado
        def auto_cut(inst)
          return unless inst.valid? && sink?(inst)
          m = H.model
          m.start_operation('lavi · Recorte automático', true, false, true)
          r = cut_for(inst, {})
          r.is_a?(String) ? m.abort_operation : m.commit_operation
          Sketchup.status_text = r.is_a?(String) ? '' : 'lavi: tampo recortado no formato da cuba.'
        rescue StandardError => e
          m.abort_operation rescue nil
          puts "[lavi] recorte automático: #{e.message}"
        end

        # recorta o tampo embaixo do bloco; devolve [larg_cm, prof_cm] ou a mensagem de erro
        def cut_for(block, p)
          bb = block.bounds
          slab = find_top(block)
          return "Não achei o tampo embaixo de \"#{block.definition.name}\". O bloco precisa estar encostado no tampo." unless slab
          top_z = slab.bounds.max.z
          folga = H.cm(H.num(p['folga'], 0))
          loops = section(block, top_z - 0.05.cm)
          loops = section(block, [bb.min.z + 1.cm, top_z - 0.05.cm].min) if loops.empty?
          if loops.empty? # bloco todo acima do tampo: usa a projeção (caixa) com 2 cm de aba
            m = 2.cm
            loops = [[[bb.min.x + m, bb.min.y + m], [bb.max.x - m, bb.min.y + m], [bb.max.x - m, bb.max.y - m], [bb.min.x + m, bb.max.y - m]]]
          end
          loops = loops.map { |l| folga.abs > 0 ? Geom2.offset_polyline(Geom2.ccw(l), -folga, true) : Geom2.ccw(l) }
          slab.make_unique if slab.respond_to?(:make_unique)
          inv = slab.transformation.inverse
          ents = H.entities_of(slab)
          top = ents.grep(Sketchup::Face).select { |f| f.normal.transform(slab.transformation).z > 0.99 }.max_by { |f| f.bounds.max.z }
          return 'O tampo não tem face de cima.' unless top
          lz = top.vertices[0].position.z
          # espessura = até a face de baixo do tampo (não a altura do grupo todo)
          c0 = Geom::Point3d.new(*Geom2.centroid(loops[0]), top_z).transform(inv)
          unders = ents.grep(Sketchup::Face).select { |f| f.normal.z < -0.99 && f.vertices[0].position.z < lz - 1e-4 }
          below = unders.select { |f| [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge].include?(f.classify_point(Geom::Point3d.new(c0.x, c0.y, f.vertices[0].position.z))) }
          zb = (below.empty? ? unders : below).map { |f| f.vertices[0].position.z }.max
          thick = zb ? lz - zb : slab.bounds.depth
          loops.each do |l|
            pts = l.map { |x, y| Geom::Point3d.new(x, y, top_z).transform(inv) }
            pts = pts.map { |q| Geom::Point3d.new(q.x, q.y, lz) }
            hole = ents.add_face(pts)
            next unless hole
            hole.reverse! if hole.normal.transform(slab.transformation).z < 0
            hole.pushpull(-thick)
          end
          ext = Geom::BoundingBox.new
          loops.each { |l| l.each { |x, y| ext.add(Geom::Point3d.new(x, y, 0)) } }
          [H.to_cm(ext.width), H.to_cm(ext.height)]
        end

        # o grupo/componente cujo topo está na altura do bloco e embaixo dele
        def find_top(block)
          bb = block.bounds
          c = bb.center
          ents = block.parent.respond_to?(:entities) ? block.parent.entities : H.model.active_entities
          cands = ents.to_a.select do |e|
            next false unless H.instance?(e) && !e.equal?(block) && !sink?(e)
            b = e.bounds
            next false if b.max.x < c.x || b.min.x > c.x || b.max.y < c.y || b.min.y > c.y
            b.max.z >= bb.min.z - 0.5.cm && b.max.z <= bb.max.z + 0.5.cm
          end
          cands.max_by { |e| e.bounds.max.z }
        end

        # corte horizontal do bloco na altura z: contornos (x, y) em coordenadas do modelo
        def section(block, z)
          segs = []
          H.each_face(H.entities_of(block), block.transformation) do |f, tr, _|
            pts = f.outer_loop.vertices.map { |v| v.position.transform(tr) }
            hits = []
            pts.each_with_index do |a, i|
              b = pts[(i + 1) % pts.size]
              da = a.z - z
              db = b.z - z
              next if (da > 0) == (db > 0)
              t = da / (da - db)
              hits << [a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t]
            end
            next if hits.size < 2
            d = [hits[-1][0] - hits[0][0], hits[-1][1] - hits[0][1]]
            hits.sort_by! { |q| (q[0] - hits[0][0]) * d[0] + (q[1] - hits[0][1]) * d[1] }
            hits.each_slice(2) { |a, b| segs << [a, b] if b && Geom2.len(Geom2.sub(a, b)) > 1e-4 }
          end
          loops = chain(segs)
          loops = loops.select { |l| Geom2.area(l) > H.cm(2) * H.cm(2) }
          # só os de fora (a borda interna da cuba fica dentro da externa)
          loops.reject { |l| loops.any? { |o| !o.equal?(l) && Geom2.area(o) > Geom2.area(l) && Geom2.point_in_poly?(Geom2.centroid(l), o) } }
        end

        def chain(segs)
          key = ->(q) { [(q[0] / 0.01).round, (q[1] / 0.01).round] }
          adj = Hash.new { |h, k| h[k] = [] }
          segs.each_with_index { |(a, b), i| adj[key.call(a)] << i; adj[key.call(b)] << i }
          used = {}
          loops = []
          segs.each_index do |s0|
            next if used[s0]
            used[s0] = true
            a, b = segs[s0]
            ring = [a, b]
            loop do
              k = key.call(ring.last)
              nxt = adj[k].find { |i| !used[i] }
              break unless nxt
              used[nxt] = true
              p0, p1 = segs[nxt]
              q = key.call(p0) == k ? p1 : p0
              break if key.call(q) == key.call(ring.first)
              ring << q
            end
            loops << ring if ring.size >= 3
          end
          loops
        end

        # ---- recorte por medida (sem bloco) ---------------------------------------
        def by_size(p)
          sel = H.selection.to_a.select { |e| H.instance?(e) }
          return H.err('Selecione o módulo com tampo (ou o grupo do tampo).') if sel.size != 1
          target = sel[0]
          msg = nil
          H.operation('lavi · Recorte no tampo') do
            slab = target
            if target.is_a?(Sketchup::ComponentInstance) && H.kind_of(target.definition) == 'cabinet'
              slab = detach_top(target)
              msg = 'O tampo do módulo foi trocado por um tampo com recorte (grupo "Tampo com recorte").'
            end
            cut(slab, p)
          end
          pr = PRESETS[p['tipo']] || PRESETS['cuba']
          H.ok(msg || 'Recorte feito.', stats: [['Recorte', "#{H.br(H.num(p['larg'], pr[:larg]), 1)} × #{H.br(H.num(p['prof'], pr[:prof]), 1)} cm"]])
        end

        # Observa o modelo: cuba colocada em cima de tampo → recorte automático
        class AutoCutObserver < (defined?(Sketchup::EntitiesObserver) ? Sketchup::EntitiesObserver : Object)
          def onElementAdded(_ents, e)
            return unless Countertop.auto? && e.is_a?(Sketchup::ComponentInstance) && Countertop.sink?(e)
            UI.start_timer(0.3, false) { Countertop.auto_cut(e) if e.valid? }
          rescue StandardError => err
            puts "[lavi] observador do recorte: #{err.message}"
          end
        end

        class AppWatch < (defined?(Sketchup::AppObserver) ? Sketchup::AppObserver : Object)
          def onNewModel(m) Countertop.watch(m) end
          def onOpenModel(m) Countertop.watch(m) end
        end

        def watch(model)
          return unless model && defined?(Sketchup::EntitiesObserver)
          @watched ||= {}
          return if @watched[model.guid]
          @watched[model.guid] = true
          model.entities.add_observer(AutoCutObserver.new)
        rescue StandardError => e
          puts "[lavi] não consegui observar o modelo: #{e.message}"
        end

        unless @started
          @started = true
          begin
            Sketchup.add_observer(AppWatch.new) if defined?(Sketchup::AppObserver) && Sketchup.respond_to?(:add_observer)
            watch(Sketchup.active_model) if Sketchup.respond_to?(:active_model)
          rescue StandardError => e
            puts "[lavi] recorte automático indisponível: #{e.message}"
          end
        end

        # Copia o tampo dinâmico para um grupo comum e esconde o original
        def detach_top(inst)
          leaf = inst.definition.entities.to_a.find { |e| H.instance?(e) && e.get_attribute(H::DICT, 'part') == 'Tampo' }
          raise 'Este módulo está sem tampo. Ative "Tampo" nas opções antes.' unless leaf && !leaf.hidden?
          bb = Geom::BoundingBox.new
          [[0, 0, 0], [1, 1, 1]].each { |q| bb.add(Geom::Point3d.new(*q).transform(leaf.transformation)) }
          grp = H.model.active_entities.add_group
          f = grp.entities.add_face([bb.min.x, bb.min.y, bb.min.z], [bb.max.x, bb.min.y, bb.min.z],
                                    [bb.max.x, bb.max.y, bb.min.z], [bb.min.x, bb.max.y, bb.min.z])
          f.reverse! if f.normal.z < 0
          f.pushpull(bb.depth)
          grp.transformation = inst.transformation
          grp.material = leaf.material
          grp.name = 'Tampo com recorte'
          grp.layer = inst.layer
          H.mark(grp, 'part', 'part' => 'Tampo', 'mk' => 'tampo')
          inst.set_attribute(DA, 'tampovis', 0)
          grp
        end

        def cut(slab, p)
          pr = PRESETS[p['tipo']] || PRESETS['cuba']
          w = H.cm(H.num(p['larg'], pr[:larg]))
          d = H.cm(H.num(p['prof'], pr[:prof]))
          recuo = H.cm(H.num(p['recuo'], 8))
          slab.make_unique if slab.is_a?(Sketchup::ComponentInstance)
          ents = H.entities_of(slab)
          bb = Geom::BoundingBox.new
          ents.each { |e| bb.add(e.bounds) }
          top = ents.grep(Sketchup::Face).select { |f| f.normal.z > 0.99 }.max_by { |f| f.bounds.max.z }
          raise 'Não encontrei a face de cima do tampo.' unless top
          thick = bb.depth
          raise 'O recorte é maior que o tampo.' if w > bb.width - 2.cm || d > bb.height - recuo - 1.cm
          cx = if p['pos'] == 'esquerda' then bb.min.x + H.cm(H.num(p['desloc'], 30)) + w / 2.0
               elsif p['pos'] == 'direita' then bb.max.x - H.cm(H.num(p['desloc'], 30)) - w / 2.0
               else (bb.min.x + bb.max.x) / 2.0
               end
          y0 = bb.min.y + recuo
          z = top.bounds.max.z
          pts = [[cx - w / 2, y0, z], [cx + w / 2, y0, z], [cx + w / 2, y0 + d, z], [cx - w / 2, y0 + d, z]]
          hole = ents.add_face(pts)
          hole.reverse! if hole.normal.z < 0
          hole.pushpull(-thick)
          return unless p['inserir'] != false && p['inserir'] != 'false'
          if p['tipo'] == 'cooktop'
            g = ents.add_group
            m = 2.cm
            f = g.entities.add_face([cx - w / 2 - m, y0 - m, z], [cx + w / 2 + m, y0 - m, z], [cx + w / 2 + m, y0 + d + m, z], [cx - w / 2 - m, y0 + d + m, z])
            f.reverse! if f.normal.z < 0
            f.pushpull(0.6.cm)
            g.material = H.material('lavi_VidroPreto', '151517')
            g.name = 'Cooktop'
          else
            g = ents.add_group
            depth = H.cm(pr[:fundo])
            zb = z - thick - depth
            e = g.entities
            b = [[cx - w / 2, y0, zb], [cx + w / 2, y0, zb], [cx + w / 2, y0 + d, zb], [cx - w / 2, y0 + d, zb]]
            t = b.map { |x, y, _| [x, y, z - thick] }
            e.add_face(b)
            4.times { |i| e.add_face(b[i], b[(i + 1) % 4], t[(i + 1) % 4], t[i]) }
            g.material = H.material('lavi_Inox', 'C9CDD1')
            g.name = p['tipo'] == 'cuba_dupla' ? 'Cuba dupla' : 'Cuba'
            if p['tipo'] == 'cuba_dupla'
              mid = e.add_face([cx - 0.5.cm, y0, zb], [cx + 0.5.cm, y0, zb], [cx + 0.5.cm, y0 + d, zb], [cx - 0.5.cm, y0 + d, zb])
              mid.pushpull(depth - 3.cm) if mid
            end
          end
        end

        Registry.register(:countertop, name: 'Recorte de cuba e cooktop', tab: :marc, package: :marc, handler: self,
                                       desc: 'Coloque o bloco da cuba ou do cooktop no tampo: o furo sai no formato dele, sozinho.',
                                       steps: ['Coloque o bloco em cima do tampo', 'O recorte sai sozinho', 'Ou selecione e clique em Recortar'])
      end
    end
  end
end
