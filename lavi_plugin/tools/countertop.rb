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

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'cut'
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
          if target.is_a?(Sketchup::ComponentInstance) && defined?($dc_observers) && $dc_observers
            $dc_observers.get_latest_class.redraw_with_undo(target)
          end
          pr = PRESETS[p['tipo']] || PRESETS['cuba']
          H.ok(msg || 'Recorte feito.', stats: [['Recorte', "#{H.br(H.num(p['larg'], pr[:larg]), 1)} × #{H.br(H.num(p['prof'], pr[:prof]), 1)} cm"]])
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
                                       desc: 'Abre o furo no tampo e já encaixa a cuba ou o cooktop.',
                                       steps: ['Selecione o módulo com tampo', 'Escolha cuba ou cooktop', 'Recortar'])
      end
    end
  end
end
