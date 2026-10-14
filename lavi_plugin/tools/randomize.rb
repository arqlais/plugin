# Variar objetos: gira, muda o tamanho e espelha de leve as cópias (plantas, cadeiras, livros, pedras)
# e mistura os materiais entre elas — para a cena não parecer copiada e colada.

module LAVIStudio
  module Plugin
    module Tools
      module Randomize
        extend self
        H = Helpers

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'run'
          insts = H.selection.to_a.select { |e| H.instance?(e) }
          return H.err('Selecione as cópias (blocos) que quer variar.') if insts.size < 1
          rnd = Random.new(H.num(p['seed'], Time.now.to_i).to_i)
          girar = H.num(p['girar'], 180)
          esc = H.num(p['escala'], 10) / 100.0
          espelhar = p['espelhar'] == true || p['espelhar'] == 'true'
          misturar = p['misturar'] == true || p['misturar'] == 'true'
          mats = insts.map(&:material).compact.uniq
          H.operation('lavi · Variar objetos') do
            insts.each do |i|
              b = i.bounds
              base = Geom::Point3d.new(b.center.x, b.center.y, b.min.z)
              t = IDENTITY
              t = Geom::Transformation.rotation(base, Z_AXIS, (rnd.rand * 2 - 1) * girar * Math::PI / 180) * t if girar > 0
              if esc > 0
                k = 1 + (rnd.rand * 2 - 1) * esc
                t = Geom::Transformation.scaling(base, k) * t
              end
              t = Geom::Transformation.scaling(base, -1, 1, 1) * t if espelhar && rnd.rand < 0.5
              i.transform!(t)
              i.material = mats[rnd.rand(mats.size)] if misturar && mats.size > 1
            end
          end
          H.ok("#{insts.size} objeto(s) variado(s). Clique de novo para outro sorteio.", stats: [['Objetos', insts.size.to_s]])
        end

        Registry.register(:randomize, name: 'Variar objetos', tab: :render, package: :pres, handler: self,
                                      desc: 'Gira, muda o tamanho e mistura materiais das cópias (plantas, cadeiras) para a cena ficar natural.',
                                      steps: ['Selecione as cópias', 'Escolha quanto variar', 'Variar'])
      end
    end
  end
end
