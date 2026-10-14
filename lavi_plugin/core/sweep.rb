# Perfil puxado ao longo de um contorno (rodapé, moldura de teto, tabica): cantos em meia-esquadria.

module LAVIStudio
  module Plugin
    module Sweep
      G = Geom2

      module_function

      # ents: onde desenhar · path: pontos 2D (lado de dentro do ambiente à ESQUERDA do caminho)
      # profile: [[u, v], ...] fechado (u = distância da parede para dentro, v = altura do perfil)
      # to3: ->(ponto2d, v) { Geom::Point3d } · devolve o comprimento do caminho
      def build(ents, path, closed, profile, to3)
        path = dedupe(path, closed)
        n = path.size
        return 0.0 if n < 2 || profile.size < 3
        segs = closed ? n : n - 1
        dirs = (0...segs).map { |i| G.unit(G.sub(path[(i + 1) % n], path[i])) }
        lefts = dirs.map { |d| G.left(d) }
        miter = (0...n).map do |k|
          if !closed && k.zero? then lefts[0]
          elsif !closed && k == n - 1 then lefts[segs - 1]
          else
            a = lefts[(k - 1) % segs]
            b = lefts[k % segs]
            den = 1.0 + G.dot(a, b)
            den < 1e-6 ? a : G.mul(G.add(a, b), 1.0 / den)
          end
        end
        rings = (0...n).map { |k| profile.map { |u, v| to3.call(G.add(path[k], G.mul(miter[k], u)), v) } }
        m = profile.size
        segs.times do |i|
          r0 = rings[i]
          r1 = rings[(i + 1) % n]
          m.times do |j|
            quad(ents, r0[j], r0[(j + 1) % m], r1[(j + 1) % m], r1[j])
          end
        end
        unless closed
          [rings[0], rings[-1]].each do |r|
            begin
              ents.add_face(r)
            rescue ArgumentError
              nil
            end
          end
        end
        (0...segs).sum { |i| G.len(G.sub(path[(i + 1) % n], path[i])) }
      end

      def quad(ents, a, b, c, d)
        ents.add_face(a, b, c, d)
      rescue ArgumentError
        # não plano (ou degenerado): dois triângulos
        [[a, b, c], [a, c, d]].each do |t|
          begin
            ents.add_face(t)
          rescue ArgumentError
            nil
          end
        end
      end

      def dedupe(path, closed)
        out = []
        path.each { |q| out << q if out.empty? || G.len(G.sub(q, out[-1])) > 1e-4 }
        out.pop if closed && out.size > 2 && G.len(G.sub(out[0], out[-1])) < 1e-4
        out
      end

      # arco de (cx, cy) com raio r, de a0 até a1 (graus), em n passos
      def arc(cx, cy, r, a0, a1, n = 6)
        (0..n).map do |i|
          t = (a0 + (a1 - a0) * i / n.to_f) * Math::PI / 180
          [cx + r * Math.cos(t), cy + r * Math.sin(t)]
        end
      end
    end
  end
end
