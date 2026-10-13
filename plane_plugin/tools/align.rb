# Alinhar e distribuir grupos e componentes

module PlaneLA
  module Plugin
    module Tools
      module Align
        extend self
        H = Helpers
        AX = { 'x' => 0, 'y' => 1, 'z' => 2 }.freeze

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'run'
          objs = H.selection.to_a.select { |e| H.instance?(e) }
          return H.err('Selecione pelo menos 2 grupos ou componentes.') if objs.size < 2
          i = AX[p['eixo']] || 0
          modo = p['modo'] || 'min'
          H.operation('Planê · Alinhar') do
            if modo == 'distribuir'
              distribute(objs, i, p)
            else
              target = case modo
                       when 'max' then objs.map { |o| o.bounds.max.to_a[i] }.max
                       when 'centro' then objs.map { |o| o.bounds.center.to_a[i] }.sum / objs.size
                       else objs.map { |o| o.bounds.min.to_a[i] }.min
                       end
              objs.each do |o|
                cur = case modo
                      when 'max' then o.bounds.max.to_a[i]
                      when 'centro' then o.bounds.center.to_a[i]
                      else o.bounds.min.to_a[i]
                      end
                move(o, i, target - cur)
              end
            end
          end
          H.ok("#{objs.size} objetos #{modo == 'distribuir' ? 'distribuídos' : 'alinhados'} no eixo #{p['eixo'].to_s.upcase}.")
        end

        def move(o, i, delta)
          v = [0, 0, 0]
          v[i] = delta
          o.transform!(Geom::Transformation.translation(Geom::Vector3d.new(*v)))
        end

        def distribute(objs, i, p)
          sorted = objs.sort_by { |o| o.bounds.min.to_a[i] }
          sizes = sorted.map { |o| o.bounds.max.to_a[i] - o.bounds.min.to_a[i] }
          if p['espaco'].to_s.strip.empty?
            span = sorted[-1].bounds.max.to_a[i] - sorted[0].bounds.min.to_a[i]
            gap = (span - sizes.sum) / (sorted.size - 1)
          else
            gap = H.cm(H.num(p['espaco']))
          end
          pos = sorted[0].bounds.min.to_a[i]
          sorted.each_with_index do |o, k|
            move(o, i, pos - o.bounds.min.to_a[i]) if k > 0
            pos += sizes[k] + gap
          end
        end

        Registry.register(:align, name: 'Alinhar e distribuir', tab: :base, package: :base, handler: self,
                                  desc: 'Alinha pela borda ou centro e distribui com espaço igual.',
                                  steps: ['Selecione os objetos', 'Escolha eixo e modo', 'Aplicar'])
      end
    end
  end
end
