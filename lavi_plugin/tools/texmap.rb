# Ajustar texturização: projeta a textura em caixa (cada face pega a direção mais próxima),
# de cima (plana) ou esférica, com tamanho real e rotação — sem textura esticada ou torta.

module LAVIStudio
  module Plugin
    module Tools
      module Texmap
        extend self
        H = Helpers

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'apply'
          sel = H.selection.to_a
          return H.err('Selecione os blocos ou as faces com textura.') if sel.empty?
          size = H.cm([H.num(p['tam'], 60), 1].max)
          rot = H.num(p['rot'], 0) * Math::PI / 180
          modo = %w[caixa plana esferica].include?(p['projecao'].to_s) ? p['projecao'].to_s : 'caixa'
          done = 0
          skipped = 0
          H.operation('lavi · Ajustar texturização') do
            each_face(sel, IDENTITY, nil) do |f, tr, mat|
              m = f.material || mat
              unless m && m.texture
                skipped += 1
                next
              end
              map(f, tr, m, modo, size, rot)
              done += 1
            end
          end
          return H.err('Nenhuma face com textura na seleção. Pinte com um material de imagem antes.') if done.zero?
          H.ok("Textura ajustada em #{done} face(s).", stats: [['Faces', done.to_s], ['Tamanho', "#{H.br(H.to_cm(size), 0)} cm"],
                                                              ['Rotação', "#{H.br(H.num(p['rot'], 0), 0)}°"], ['Sem textura', skipped.to_s]])
        end

        def each_face(items, tr, mat, seen = {}, &block)
          items.each do |e|
            if e.is_a?(Sketchup::Face)
              yield e, tr, mat
            elsif H.instance?(e)
              key = [e.definition, tr.to_a]
              next if seen[key]
              seen[key] = true
              each_face(H.entities_of(e).to_a, tr * e.transformation, e.material || mat, seen, &block)
            end
          end
        end

        # coordenada de textura (em "repetições") de um ponto do modelo
        def uv(q, n, modo, size, rot, c)
          a, b =
            case modo
            when 'plana' then [q.x, q.y]
            when 'esferica'
              d = q - c
              r = [d.length, 1e-6].max
              [Math.atan2(d.y, d.x) * r, Math.asin([[d.z / r, 1].min, -1].max) * r]
            else
              if n.z.abs >= n.x.abs && n.z.abs >= n.y.abs then [q.x, q.y]
              elsif n.x.abs >= n.y.abs then [q.y, q.z]
              else [q.x, q.z]
              end
            end
          a /= size
          b /= size
          [a * Math.cos(rot) - b * Math.sin(rot), a * Math.sin(rot) + b * Math.cos(rot)]
        end

        def map(f, tr, m, modo, size, rot)
          vs = f.outer_loop.vertices.map(&:position)
          p0 = vs[0]
          e1 = vs.find { |q| q.distance(p0) > 1e-3 }
          return unless e1
          n = f.normal
          v1 = e1 - p0
          v2 = n.cross(v1)
          p1 = p0.offset(v1, 10)
          p2 = p0.offset(v2, 10)
          wn = n.transform(tr)
          c = f.bounds.center.transform(tr)
          pts = [p0, p1, p2].flat_map do |q|
            a, b = uv(q.transform(tr), wn, modo, size, rot, c)
            [q, Geom::Point3d.new(a, b, 1)]
          end
          f.position_material(m, pts, true)
        end

        Registry.register(:texmap, name: 'Ajustar texturas', tab: :render, package: :pres, handler: self,
                                   desc: 'Projeção em caixa, plana ou esférica com tamanho real e rotação; gira a textura 90°.',
                                   steps: ['Selecione o bloco com textura', 'Escolha projeção e tamanho', 'Aplicar'])
      end
    end
  end
end
