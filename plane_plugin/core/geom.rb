# Matemática 2D pura (pontos como [x, y]) + referencial de uma face.
# A parte 2D não depende do SketchUp e é testada em dev/test_geom.rb.

module Plane
  module Plugin
    module Geom2
      EPS = 1e-9

      module_function

      def signed_area(poly)
        s = 0.0
        poly.each_with_index do |p, i|
          q = poly[(i + 1) % poly.size]
          s += p[0] * q[1] - q[0] * p[1]
        end
        s / 2.0
      end

      def area(poly)
        signed_area(poly).abs
      end

      def ccw(poly)
        signed_area(poly) < 0 ? poly.reverse : poly
      end

      def sub(a, b)  [a[0] - b[0], a[1] - b[1]] end
      def add(a, b)  [a[0] + b[0], a[1] + b[1]] end
      def mul(a, k)  [a[0] * k, a[1] * k] end
      def dot(a, b)  a[0] * b[0] + a[1] * b[1] end
      def cross(a, b) a[0] * b[1] - a[1] * b[0] end
      def len(a)     Math.sqrt(dot(a, a)) end
      def unit(a)
        l = len(a)
        l < EPS ? [0.0, 0.0] : [a[0] / l, a[1] / l]
      end
      # normal à esquerda de uma direção
      def left(a) [-a[1], a[0]] end

      def rotate(p, ang, c = [0.0, 0.0])
        s = Math.sin(ang)
        co = Math.cos(ang)
        x = p[0] - c[0]
        y = p[1] - c[1]
        [c[0] + x * co - y * s, c[1] + x * s + y * co]
      end

      # Interseção das retas (p + t*r) e (q + u*s)
      def line_intersection(p, r, q, s)
        d = cross(r, s)
        return nil if d.abs < EPS
        t = cross(sub(q, p), s) / d.to_f
        add(p, mul(r, t))
      end

      # Desloca uma polilinha d unidades para a esquerda (d negativo = direita),
      # com cantos em meia-esquadria. closed = contorno fechado.
      def offset_polyline(pts, d, closed = false, miter_limit = 4.0)
        n = pts.size
        return pts.dup if n < 2
        segs = []
        count = closed ? n : n - 1
        count.times do |i|
          a = pts[i]
          b = pts[(i + 1) % n]
          dir = unit(sub(b, a))
          off = mul(left(dir), d)
          segs << [add(a, off), dir]
        end
        out = []
        n.times do |i|
          if !closed && i.zero?
            out << segs[0][0]
          elsif !closed && i == n - 1
            last = segs[-1]
            out << add(last[0], mul(last[1], len(sub(pts[-1], pts[-2]))))
          else
            prev = segs[(i - 1) % count]
            cur = segs[i % count]
            x = line_intersection(prev[0], prev[1], cur[0], cur[1])
            if x.nil? || len(sub(x, pts[i])) > miter_limit * d.abs
              out << add(pts[i], mul(left(cur[1]), d))
            else
              out << x
            end
          end
        end
        out
      end

      # Sutherland–Hodgman: recorta 'subject' (qualquer polígono simples)
      # pelo polígono convexo 'clip' (anti-horário).
      def clip(subject, clip)
        output = subject
        clip.each_with_index do |a, i|
          b = clip[(i + 1) % clip.size]
          input = output
          output = []
          break if input.empty?
          s = input[-1]
          input.each do |e|
            e_in = cross(sub(b, a), sub(e, a)) >= -EPS
            s_in = cross(sub(b, a), sub(s, a)) >= -EPS
            if e_in
              output << seg_line(s, e, a, b) unless s_in
              output << e
            elsif s_in
              output << seg_line(s, e, a, b)
            end
            s = e
          end
        end
        output.compact
      end

      def seg_line(p1, p2, a, b)
        line_intersection(p1, sub(p2, p1), a, sub(b, a)) || p2
      end

      def point_in_poly?(pt, poly)
        inside = false
        j = poly.size - 1
        poly.each_with_index do |pi, i|
          pj = poly[j]
          if ((pi[1] > pt[1]) != (pj[1] > pt[1])) &&
             (pt[0] < (pj[0] - pi[0]) * (pt[1] - pi[1]) / (pj[1] - pi[1] + 0.0) + pi[0])
            inside = !inside
          end
          j = i
        end
        inside
      end

      def bbox(poly)
        xs = poly.map { |p| p[0] }
        ys = poly.map { |p| p[1] }
        [xs.min, ys.min, xs.max, ys.max]
      end

      def centroid(poly)
        x = poly.sum { |p| p[0] } / poly.size.to_f
        y = poly.sum { |p| p[1] } / poly.size.to_f
        [x, y]
      end

      # Remove pontos repetidos e colineares
      def clean(poly, tol = 1e-4)
        pts = []
        poly.each { |p| pts << p if pts.empty? || len(sub(p, pts[-1])) > tol }
        pts.pop if pts.size > 1 && len(sub(pts[0], pts[-1])) <= tol
        changed = true
        while changed && pts.size > 3
          changed = false
          pts.each_index do |i|
            a = pts[i - 1]
            b = pts[i]
            c = pts[(i + 1) % pts.size]
            next unless cross(sub(b, a), sub(c, b)).abs < tol * tol * 10
            pts.delete_at(i)
            changed = true
            break
          end
        end
        pts
      end

      # ---- referencial de face (precisa do SketchUp) ---------------------------
      # Devolve um hash com origem e eixos u/v no plano da face (coordenadas do modelo):
      #  piso/teto: u = X, v = Y ; parede: u = horizontal, v = Z
      def face_frame(face, tr)
        n = face.normal.transform(tr)
        n.normalize!
        origin = face.vertices[0].position.transform(tr)
        if n.z.abs > 0.98
          u = Geom::Vector3d.new(1, 0, 0)
          v = n.z > 0 ? Geom::Vector3d.new(0, 1, 0) : Geom::Vector3d.new(0, -1, 0)
        else
          z = Geom::Vector3d.new(0, 0, 1)
          u = z.cross(n)
          u = Geom::Vector3d.new(1, 0, 0) if u.length < 1e-6
          u.normalize!
          v = n.cross(u)
          v.normalize!
        end
        { origin: origin, u: u, v: v, n: n }
      end

      def to_2d(pt, fr)
        d = pt - fr[:origin]
        [d.dot(fr[:u]), d.dot(fr[:v])]
      end

      def to_3d(p, fr, lift = 0.0)
        o = fr[:origin]
        Geom::Point3d.new(
          o.x + fr[:u].x * p[0] + fr[:v].x * p[1] + fr[:n].x * lift,
          o.y + fr[:u].y * p[0] + fr[:v].y * p[1] + fr[:n].y * lift,
          o.z + fr[:u].z * p[0] + fr[:v].z * p[1] + fr[:n].z * lift
        )
      end

      # Contorno externo e furos de uma face em 2D
      def face_loops_2d(face, tr, fr)
        outer = face.outer_loop.vertices.map { |vx| to_2d(vx.position.transform(tr), fr) }
        holes = face.loops.reject(&:outer?).map do |lp|
          lp.vertices.map { |vx| to_2d(vx.position.transform(tr), fr) }
        end
        [outer, holes]
      end
    end
  end
end
