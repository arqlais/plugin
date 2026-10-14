# Luzes para render: marcar superfícies como fonte de luz (com temperatura), fachos de luz
# embaixo dos spots, mancha de luz na parede e letreiro neon.

module LAVIStudio
  module Plugin
    module Tools
      module Lights
        extend self
        H = Helpers
        TEMPS = { '2700' => 'FFD08A', '3000' => 'FFDDA0', '4000' => 'FFF1D6', '5000' => 'F7F6F0', '6500' => 'EEF3FF' }.freeze

        def handle(action, p)
          case action
          when 'mark' then mark(p)
          when 'pick' then pick(p)
          when 'beam' then beam(p)
          when 'wash' then click_wall(p, :wash)
          when 'neon' then click_wall(p, :neon)
          else H.err('Ação desconhecida.')
          end
        end

        def light_mat(p)
          t = TEMPS.key?(p['temp'].to_s) ? p['temp'].to_s : '3000'
          m = H.material("lavi Luz #{t}K", TEMPS[t])
          m.set_attribute(H::DICT, 'luz', t.to_i) if m.respond_to?(:set_attribute)
          m
        end

        def mark(p)
          sel = H.selection.to_a.select { |e| e.is_a?(Sketchup::Face) || H.instance?(e) }
          return H.err('Selecione as faces (ou blocos) que acendem: fita de LED, lâmpada, luminária.') if sel.empty?
          H.operation('lavi · Marcar luz') do
            m = light_mat(p)
            sel.each { |e| e.material = m }
          end
          H.ok("#{sel.size} item(ns) marcados como luz de #{p['temp'] || 3000}K.", stats: [['Fontes de luz', sel.size.to_s]])
        end

        # conta-gotas: clicou numa face → ela e todas com o mesmo material viram luz
        def pick(p)
          Sketchup.active_model.select_tool(
            Pickers::FacePicker.new('Clique na superfície que acende (todas com o mesmo material também)') do |face, _tr, _pt, _path|
              src = face.material
              n = 0
              H.operation('lavi · Marcar luz') do
                m = light_mat(p)
                if src
                  Materials.each_entity(H.model.entities.to_a) do |e|
                    next unless e.respond_to?(:material) && e.material == src
                    e.material = m
                    n += 1
                  end
                else
                  face.material = m
                  n = 1
                end
              end
              Sketchup.active_model.select_tool(nil)
              Dialog.push('result', tool: 'lights', ok: true, msg: "#{n} superfície(s) viraram luz.")
            end
          )
          H.ok('Clique na superfície que acende.', picking: true)
        end

        # cone de luz translúcido embaixo de cada spot selecionado, até o piso
        def beam(p)
          spots = H.selection.to_a.select { |e| H.instance?(e) }
          return H.err('Selecione os spots / luminárias (blocos).') if spots.empty?
          ang = [[H.num(p['abertura'], 36), 5].max, 150].min * Math::PI / 180
          piso = H.cm(H.num(p['piso'], 0))
          seg = 24
          H.operation('lavi · Facho de luz') do
            mat = H.material('lavi Facho de luz', 'FFF4DC', [[H.num(p['intensidade'], 20) / 100.0, 0.05].max, 0.9].min)
            spots.each do |s|
              b = s.bounds
              top = Geom::Point3d.new(b.center.x, b.center.y, b.min.z)
              hgt = top.z - piso
              next if hgt < 5.cm
              r0 = [b.width, b.height].min / 4.0
              r1 = r0 + hgt * Math.tan(ang / 2)
              g = H.model.active_entities.add_group
              ring = ->(r, z) { (0...seg).map { |k| t = 2 * Math::PI * k / seg; Geom::Point3d.new(top.x + r * Math.cos(t), top.y + r * Math.sin(t), z) } }
              a = ring.call(r0, top.z)
              c = ring.call(r1, piso + 0.2.cm)
              seg.times { |k| Sweep.quad(g.entities, a[k], a[(k + 1) % seg], c[(k + 1) % seg], c[k]) }
              g.material = mat
              g.name = 'Facho de luz'
              g.layer = H.tag('lavi · Luzes')
            end
          end
          H.ok("#{spots.size} facho(s) de luz criados (etiqueta \"lavi · Luzes\").")
        end

        def click_wall(p, kind)
          Sketchup.active_model.select_tool(
            Pickers::FacePicker.new(kind == :wash ? 'Clique na parede, embaixo do spot' : 'Clique na parede onde fica o letreiro') do |face, tr, pt, _path|
              begin
                H.operation(kind == :wash ? 'lavi · Luz na parede' : 'lavi · Letreiro') do
                  kind == :wash ? wash(face, tr, pt, p) : neon(face, tr, pt, p)
                end
                Dialog.push('result', tool: 'lights', ok: true, msg: kind == :wash ? 'Mancha de luz criada.' : 'Letreiro criado.')
              rescue StandardError => e
                Dialog.push('result', tool: 'lights', ok: false, msg: e.message)
              end
            end
          )
          H.ok(kind == :wash ? 'Clique na parede, no ponto mais alto da luz.' : 'Clique na parede, no centro do letreiro.', picking: true)
        end

        # eixos da parede clicada (em coordenadas do modelo): u horizontal, n para fora
        def wall_axes(face, tr)
          n = face.normal.transform(tr)
          n.normalize!
          raise 'Clique numa parede (face em pé).' if n.z.abs > 0.3
          u = Z_AXIS.cross(n)
          u.normalize!
          [u, n]
        end

        # mancha de luz em forma de gota (parábola) colada na parede
        def wash(face, tr, pt, p)
          u, n = wall_axes(face, tr)
          w = H.cm(H.num(p['larg'], 60))
          h = H.cm(H.num(p['alt'], 120))
          o = pt.offset(n, 0.2.cm)
          # fina perto do spot, abre para baixo e termina arredondada (como a luz de um spot na parede)
          k = 12
          w0 = w * 0.12
          side = (0..k).map { |i| t = i.to_f / k; [w0 / 2 + (w - w0) / 2 * Math.sqrt(t), -t * h * 0.72] }
          bottom = (1...k).map { |i| a = Math::PI * i / k; [-(w / 2) * Math.cos(a), -h * 0.72 - h * 0.28 * Math.sin(a)] }
          prof = side.reverse.map { |x, z| [-x, z] } + bottom + side.map { |x, z| [x, z] }
          pts = prof.map { |x, z| o.offset(u, x).offset(Z_AXIS, z) }
          g = H.model.active_entities.add_group
          g.entities.add_face(pts)
          g.material = H.material('lavi Luz na parede', 'FFF1D6', 0.45)
          g.name = 'Luz na parede'
          g.layer = H.tag('lavi · Luzes')
        end

        def neon(face, tr, pt, p)
          u, n = wall_axes(face, tr)
          txt = p['texto'].to_s.strip
          raise 'Escreva o texto do letreiro.' if txt.empty?
          h = H.cm(H.num(p['letra'], 15))
          g = H.model.active_entities.add_group
          g.entities.add_3d_text(txt, TextAlignCenter, p['fonte'].to_s.empty? ? 'Arial' : p['fonte'].to_s, false, false, h, 0.0, 0.0, true, H.cm(H.num(p['prof'], 1)))
          b = g.bounds
          # centraliza o texto no clique e deita na parede
          g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(-b.center.x, -b.center.y, 0)))
          g.transform!(Geom::Transformation.axes(pt.offset(n, 0.3.cm), u, Z_AXIS, n))
          g.material = H.material("lavi Neon #{p['cor'].to_s.delete('#')}", p['cor'] || 'FF5FA2')
          g.name = "Letreiro: #{txt}"
          g.layer = H.tag('lavi · Luzes')
        end

        Registry.register(:lights, name: 'Luzes e letreiro', tab: :render, package: :pres, handler: self,
                                   desc: 'Marca o que acende (com temperatura), cria fachos de luz, mancha na parede e letreiro neon.',
                                   steps: ['Selecione ou clique', 'Escolha temperatura e forma', 'Pronto para render'])
      end
    end
  end
end
