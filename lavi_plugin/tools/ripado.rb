# Ripado: ripas de madeira (ou MDF, metal) numa parede, forro, porta ou painel, com fundo opcional.
# Leve: cada comprimento de ripa vira UM componente e as ripas são cópias dele (não pesa o modelo).

module LAVIStudio
  module Plugin
    module Tools
      module Ripado
        extend self
        H = Helpers
        G = Geom2
        MAX_RIPAS = 4000

        def handle(action, p)
          case action
          when 'build'
            faces = H.selected_faces
            return H.err('Selecione a face (parede, forro, porta) onde vai o ripado, ou clique em Escolher a face.') if faces.empty?
            run(faces, p)
          when 'pick'
            Sketchup.active_model.select_tool(
              Pickers::FacePicker.new('Ripado: clique na face') do |face, tr, _pt, _path|
                Sketchup.active_model.select_tool(nil)
                res = begin
                  run([[face, tr]], p)
                rescue StandardError => e
                  H.err(e.message)
                end
                Dialog.push('result', res.merge(tool: 'ripado'))
              end
            )
            H.ok('Clique na face onde vai o ripado.', picking: true)
          else H.err('Ação desconhecida.')
          end
        end

        def run(faces, p)
          larg = H.cm([H.num(p['larg'], 4), 0.5].max)
          vao = H.cm([H.num(p['vao'], 2), 0].max)
          prof = H.cm([H.num(p['prof'], 2), 0.3].max)
          recuo = H.cm([H.num(p['recuo'], 0), 0].max)
          vertical = p['sentido'] != 'horizontal'
          fundo = p['fundo'] == true || p['fundo'] == 'true'
          fesp = fundo ? H.cm([H.num(p['fundo_esp'], 1.5), 0.1].max) : 0
          plan = faces.map { |f, tr| layout(f, tr, larg, vao, recuo, vertical, p['alinhar'].to_s) }
          total = plan.sum { |pl| pl[:ripas].size }
          return H.err('Nenhuma ripa coube na face. Diminua a largura ou o recuo.') if total.zero?
          return H.err("Ficariam #{total} ripas: é demais para uma vez só. Aumente o espaço entre elas ou faça por partes.") if total > MAX_RIPAS
          lens = []
          H.operation('lavi · Ripado') do
            mat = H.material("lavi Ripa #{p['cor_ripa'].to_s.delete('#')}", p['cor_ripa'] || 'B88A62')
            fmat = fundo ? H.material("lavi Fundo ripado #{p['cor_fundo'].to_s.delete('#')}", p['cor_fundo'] || '3E4B57') : nil
            cache = {}
            plan.each do |pl|
              fr = pl[:fr]
              g = H.model.active_entities.add_group
              g.name = 'Ripado'
              g.layer = H.tag('lavi · Ripado')
              if fundo
                fg = g.entities.add_group
                fg.name = 'Fundo'
                panel(fg.entities, pl[:outer], pl[:holes], fr, fesp)
                fg.material = fmat
              end
              pl[:ripas].each do |x0, y0, w, h|
                len = vertical ? h : w
                lens << len
                key = format('%s %.2f', vertical ? 'v' : 'h', H.to_cm(len))
                d = cache[key] ||= ripa_def(larg, len, prof, vertical)
                o = G.to_3d([x0, y0], fr, fesp)
                inst = g.entities.add_instance(d, Geom::Transformation.axes(o, fr[:u], fr[:v], fr[:n]))
                inst.material = mat
              end
              g.set_attribute(H::DICT, 'ripado', JSON.generate(p))
            end
          end
          barra = H.cm([H.num(p['barra'], 300), 30].max)
          bars = bars_needed(lens, barra)
          area = plan.sum { |pl| H.m2(G.area(pl[:outer]) - pl[:holes].sum { |hh| G.area(hh) }) }
          H.ok("#{total} ripas em #{plan.size} face(s).",
               stats: [['Ripas', total.to_s], ['Metros de ripa', "#{H.br(H.to_m(lens.sum))} m"],
                       ["Barras de #{H.br(H.to_cm(barra), 0)} cm", bars.to_s], ['Área', "#{H.br(area)} m²"]])
        end

        # posição das ripas (retângulos x, y, largura, altura no plano da face)
        def layout(face, tr, larg, vao, recuo, vertical, alinhar)
          fr = G.face_frame(face, tr)
          outer, holes = G.face_loops_2d(face, tr, fr)
          loops = [outer] + holes
          # trabalha em (a, b): a = atravessa as ripas, b = ao longo da ripa
          ab = ->(q) { vertical ? q : [q[1], q[0]] }
          xy = ->(a, b) { vertical ? [a, b] : [b, a] }
          lab = loops.map { |l| l.map { |q| ab.call(q) } }
          as = lab[0].map(&:first)
          amin = as.min + recuo
          amax = as.max - recuo
          pitch = larg + vao
          ripas = []
          if amax - amin >= larg
            n = ((amax - amin - larg) / pitch).floor + 1
            start = alinhar == 'inicio' ? amin : amin + (amax - amin - (n - 1) * pitch - larg) / 2.0
            eps = [larg * 0.02, 1e-3].max
            n.times do |k|
              a0 = start + k * pitch
              a1 = a0 + larg
              iv = [a0 + eps, (a0 + a1) / 2.0, a1 - eps].map { |c| intervals(lab, c) }.reduce { |x, y| intersect(x, y) }
              iv.each do |b0, b1|
                b0 += recuo
                b1 -= recuo
                next if b1 - b0 < larg * 0.5
                x, y = xy.call(a0, b0)
                ripas << (vertical ? [x, y, larg, b1 - b0] : [x, y, b1 - b0, larg])
              end
            end
          end
          { fr: fr, outer: outer, holes: holes, ripas: ripas }
        end

        # trechos de b onde a reta a = c está dentro da face (furos contam como fora)
        def intervals(loops, c)
          bs = []
          loops.each do |l|
            l.each_with_index do |p1, i|
              p2 = l[(i + 1) % l.size]
              next if (p1[0] > c) == (p2[0] > c)
              t = (c - p1[0]) / (p2[0] - p1[0])
              bs << p1[1] + t * (p2[1] - p1[1])
            end
          end
          bs.sort.each_slice(2).select { |x| x.size == 2 && x[1] - x[0] > 1e-6 }
        end

        def intersect(a, b)
          out = []
          a.each do |a0, a1|
            b.each do |b0, b1|
              lo = [a0, b0].max
              hi = [a1, b1].min
              out << [lo, hi] if hi - lo > 1e-6
            end
          end
          out
        end

        # componente de uma ripa (reaproveita se já existir com a mesma medida)
        def ripa_def(larg, len, prof, vertical)
          name = "lavi ripa #{H.br(H.to_cm(larg), 1)} × #{H.br(H.to_cm(prof), 1)} × #{H.br(H.to_cm(len), 1)} cm#{vertical ? '' : ' (deitada)'}"
          d = H.model.definitions[name]
          return d if d && d.entities.grep(Sketchup::Face).size >= 6
          d ||= H.model.definitions.add(name)
          w = vertical ? larg : len
          h = vertical ? len : larg
          f = d.entities.add_face([0, 0, 0], [w, 0, 0], [w, h, 0], [0, h, 0])
          f.reverse! if f.normal.z > 0
          f.pushpull(-prof)
          d
        end

        def panel(ents, outer, holes, fr, esp)
          f = ents.add_face(outer.map { |q| G.to_3d(q, fr) })
          return unless f
          holes.each do |hh|
            hf = ents.add_face(hh.map { |q| G.to_3d(q, fr) })
            hf.erase! if hf && hf.valid? && !hf.equal?(f)
          end
          f.reverse! if f.normal.dot(fr[:n]) > 0
          f.pushpull(-esp)
        end

        # barras comerciais (encaixa os pedaços nas barras, maior primeiro)
        def bars_needed(lens, barra)
          left = []
          lens.sort.reverse_each do |l|
            while l > barra
              left << 0
              l -= barra
            end
            i = left.index { |r| r >= l }
            i ? left[i] -= l : left << barra - l
          end
          left.size
        end

        Registry.register(:ripado, name: 'Ripado', tab: :rev, package: :rev, handler: self,
                                   desc: 'Ripas na parede, forro, porta ou painel, com fundo, recuo e conta de barras.',
                                   steps: ['Selecione ou clique na face', 'Escolha ripa, espaço e sentido', 'Criar ripado'])
      end
    end
  end
end
