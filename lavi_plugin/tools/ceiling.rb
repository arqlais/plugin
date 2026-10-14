# Forro de gesso/drywall a partir do piso, com sanca opcional

module LAVIStudio
  module Plugin
    module Tools
      module Ceiling
        extend self
        H = Helpers
        G = Geom2

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'build'
          faces = H.selected_faces.select { |f, tr| H.horizontal?(f, tr) }
          return H.err('Selecione a face do piso do ambiente.') if faces.empty?
          alt = H.cm(H.num(p['alt'], 260))
          esp = H.cm(H.num(p['esp'], 1.25))
          sanca = p['sanca'] == true || p['sanca'] == 'true'
          larg = H.cm(H.num(p['sanca_larg'], 40))
          desc = H.cm(H.num(p['sanca_desc'], 15))
          area = 0.0
          perim = 0.0
          H.operation('LAVI · Forro') do
            mat = H.material('LAVI_Gesso', 'FAFAF8')
            grp = H.model.active_entities.add_group
            e = grp.entities
            faces.each do |face, tr|
              fr = G.face_frame(face, tr)
              outer, = G.face_loops_2d(face, tr, fr)
              outer = G.ccw(G.clean(outer))
              perim += outer.each_with_index.sum { |q, i| G.len(G.sub(outer[(i + 1) % outer.size], q)) }
              if sanca
                inner = G.offset_polyline(outer, larg, true)
                raise 'A sanca é larga demais para este ambiente.' if G.signed_area(inner) <= 0
                ring(e, outer, inner, alt - desc, esp, fr)
                slab(e, inner, alt, esp, fr)
                fascia = G.offset_polyline(inner, -esp, true)
                ring_vertical(e, fascia, inner, alt - desc, desc, fr)
                area += G.area(outer)
                area += inner.each_with_index.sum { |q, i| G.len(G.sub(inner[(i + 1) % inner.size], q)) } * desc
              else
                slab(e, outer, alt, esp, fr)
                area += G.area(outer)
              end
            end
            grp.material = mat
            grp.name = sanca ? 'Forro com sanca' : 'Forro'
            grp.layer = H.tag('LAVI · Forro')
            H.mark(grp, 'ceiling', 'area_m2' => H.m2(area))
          end
          a = H.m2(area)
          placas = (a * 1.1 / 2.88).ceil
          H.ok('Forro criado.', stats: [['Área de forro', "#{H.br(a)} m²"], ['Placas 1,20 × 2,40 (+10%)', placas.to_s],
                                        ['Tabica / moldura', "#{H.br(H.to_m(perim))} m"]])
        end

        def slab(e, poly, z, esp, fr)
          f = e.add_face(poly.map { |q| G.to_3d(q, fr, z) })
          return unless f
          f.reverse! if f.normal.dot(fr[:n]) > 0
          f.pushpull(-esp)
        end

        def ring(e, outer, inner, z, esp, fr)
          g = e.add_group
          a = g.entities.add_face(outer.map { |q| G.to_3d(q, fr, z) })
          b = g.entities.add_face(inner.map { |q| G.to_3d(q, fr, z) })
          b.erase! if b && b.valid?
          return unless a && a.valid?
          a.reverse! if a.normal.dot(fr[:n]) > 0
          a.pushpull(-esp)
        end

        # Faixa vertical (espelho da sanca)
        def ring_vertical(e, outer, inner, z, h, fr)
          g = e.add_group
          a = g.entities.add_face(outer.map { |q| G.to_3d(q, fr, z) })
          b = g.entities.add_face(inner.map { |q| G.to_3d(q, fr, z) })
          small = G.area(outer) < G.area(inner) ? a : b
          big = small == a ? b : a
          small.erase! if small && small.valid?
          return unless big && big.valid?
          big.reverse! if big.normal.dot(fr[:n]) < 0
          big.pushpull(h)
        end

        Registry.register(:ceiling, name: 'Forro e sanca', tab: :rev, package: :rev, handler: self,
                                    desc: 'Forro de gesso no pé-direito certo, com sanca e conta de placas.',
                                    steps: ['Selecione o piso', 'Informe o pé-direito', 'Gerar forro'])
      end
    end
  end
end
