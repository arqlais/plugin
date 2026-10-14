# Plano de corte sem depender do SketchUp. Testado em dev/test_core.rb.
#  · guilhotina (padrão): todo corte atravessa a chapa de lado a lado — serve para esquadrejadeira e seccionadora.
#    Testa prateleiras e cortes guilhotinados em várias ordens e fica com o que usar menos chapas.
#  · livre (MaxRects): encaixe mais apertado, para CNC (nesting).

module LAVIStudio
  module Plugin
    module Nesting
      module_function

      # pieces: [{w:, h:, label:}] em mm
      # opts: sheet_w, sheet_h, kerf, trim, rotate (true = pode girar, false = respeitar veio)
      # Devolve [{w:, h:, parts: [{x:, y:, w:, h:, label:, rot:}], used: área}]
      def pack(pieces, opts = {})
        method = opts[:method].to_s
        cands = []
        cands << pack_shelf(pieces, opts)
        orders(pieces.size).each do |ord|
          cands << pack_free(pieces, opts, ord, method == 'livre' ? :maxrects : :guillotine)
        end
        # menos chapas; empate: a última chapa mais vazia (sobra maior e inteira)
        cands.min_by { |sh| [sh.size, sh.empty? ? 0 : sh[-1][:used]] }
      end

      # ordens de tentativa (menos tentativas quando há muitas peças, para não travar)
      def orders(n)
        all = [
          ->(p) { [-p[:w] * p[:h], -[p[:w], p[:h]].max] },
          ->(p) { [-[p[:w], p[:h]].max, -[p[:w], p[:h]].min] },
          ->(p) { [-p[:h], -p[:w]] },
          ->(p) { [-p[:w], -p[:h]] },
          ->(p) { [-(p[:w] + p[:h]), -p[:w]] }
        ]
        n > 400 ? all.first(2) : all
      end

      # guilhotina (corte que atravessa) ou MaxRects (livre), com espessura da serra e refilo
      def pack_free(pieces, opts, order, mode)
        sw = (opts[:sheet_w] || 2750).to_f
        sh = (opts[:sheet_h] || 1840).to_f
        kerf = (opts[:kerf] || 4).to_f
        trim = (opts[:trim] || 10).to_f
        rotate = opts.fetch(:rotate, true)
        uw = sw - 2 * trim + kerf
        uh = sh - 2 * trim + kerf
        list = pieces.sort_by(&order)
        sheets = []
        list.each do |pc|
          w0 = pc[:w].to_f
          h0 = pc[:h].to_f
          fits = [[w0, h0, false]]
          fits << [h0, w0, true] if rotate && w0 != h0
          fits.select! { |w, h, _| w + kerf <= uw + 1e-6 && h + kerf <= uh + 1e-6 }
          if fits.empty?
            sheets << { w: sw, h: sh, parts: [{ x: trim, y: trim, w: [w0, uw - kerf].min, h: [h0, uh - kerf].min, label: pc[:label], id: pc[:id], rot: false, oversize: true }],
                        free: [], used: [w0, uw].min * [h0, uh].min, oversize: true }
            next
          end
          best = nil
          sheets.each do |s|
            next if s[:oversize]
            c = choose(s[:free], fits, kerf, mode)
            best = [s, *c] if c && (best.nil? || c[0] < best[1])
            break if best && mode == :guillotine && best[1] <= 0
          end
          unless best
            s = { w: sw, h: sh, parts: [], free: [[0.0, 0.0, uw, uh]], used: 0.0 }
            sheets << s
            best = [s, *choose(s[:free], fits, kerf, mode)]
          end
          s, _score, fi, w, h, rot = best
          fr = s[:free][fi]
          s[:parts] << { x: trim + fr[0], y: trim + fr[1], w: w, h: h, label: pc[:label], id: pc[:id], rot: rot }
          s[:used] += w * h
          place(s, fi, w + kerf, h + kerf, mode)
        end
        sheets.each { |s| s.delete(:free) }
        sheets
      end

      # melhor espaço livre: menor sobra no lado curto (BSSF)
      def choose(free, fits, kerf, mode)
        best = nil
        free.each_with_index do |(_x, _y, fw, fh), i|
          fits.each do |w, h, rot|
            ww = w + kerf
            hh = h + kerf
            next if ww > fw + 1e-6 || hh > fh + 1e-6
            score = mode == :guillotine ? fw * fh - ww * hh : [fw - ww, fh - hh].min
            best = [score, i, w, h, rot] if best.nil? || score < best[0]
          end
        end
        best
      end

      def place(s, fi, w, h, mode)
        x, y, fw, fh = s[:free][fi]
        if mode == :guillotine
          s[:free].delete_at(fi)
          # corta pelo lado que deixa a sobra maior inteira
          if fw - w < fh - h
            s[:free] << [x + w, y, fw - w, h] if fw - w > 1e-6
            s[:free] << [x, y + h, fw, fh - h] if fh - h > 1e-6
          else
            s[:free] << [x + w, y, fw - w, fh] if fw - w > 1e-6
            s[:free] << [x, y + h, w, fh - h] if fh - h > 1e-6
          end
          return
        end
        r = [x, y, w, h]
        nf = []
        s[:free].each do |f|
          unless overlap?(f, r)
            nf << f
            next
          end
          fx, fy, fw2, fh2 = f
          nf << [fx, fy, r[0] - fx, fh2] if r[0] > fx + 1e-6
          nf << [r[0] + r[2], fy, fx + fw2 - (r[0] + r[2]), fh2] if r[0] + r[2] < fx + fw2 - 1e-6
          nf << [fx, fy, fw2, r[1] - fy] if r[1] > fy + 1e-6
          nf << [fx, r[1] + r[3], fw2, fy + fh2 - (r[1] + r[3])] if r[1] + r[3] < fy + fh2 - 1e-6
        end
        nf.reject!.with_index { |a, i| nf.each_with_index.any? { |b, j| i != j && inside?(a, b) && (!inside?(b, a) || j < i) } }
        s[:free] = nf
      end

      def overlap?(a, b)
        a[0] < b[0] + b[2] - 1e-6 && b[0] < a[0] + a[2] - 1e-6 && a[1] < b[1] + b[3] - 1e-6 && b[1] < a[1] + a[3] - 1e-6
      end

      def inside?(a, b)
        a[0] >= b[0] - 1e-6 && a[1] >= b[1] - 1e-6 && a[0] + a[2] <= b[0] + b[2] + 1e-6 && a[1] + a[3] <= b[1] + b[3] + 1e-6
      end

      # prateleiras (o método antigo, continua como uma das tentativas)
      def pack_shelf(pieces, opts = {})
        sw = (opts[:sheet_w] || 2750).to_f
        sh = (opts[:sheet_h] || 1840).to_f
        kerf = (opts[:kerf] || 4).to_f
        trim = (opts[:trim] || 10).to_f
        rotate = opts.fetch(:rotate, true)
        uw = sw - 2 * trim
        uh = sh - 2 * trim
        list = pieces.map do |p|
          w = p[:w].to_f
          h = p[:h].to_f
          w, h = h, w if rotate && h > w
          p.merge(w: w, h: h)
        end
        list.sort_by! { |p| [-p[:h], -p[:w]] }
        sheets = []
        list.each do |p|
          fits = [[p[:w], p[:h], false]]
          fits << [p[:h], p[:w], true] if rotate && p[:w] != p[:h]
          fits.select! { |w, h, _| w <= uw + 1e-6 && h <= uh + 1e-6 }
          if fits.empty?
            sheets << { w: sw, h: sh, parts: [{ x: trim, y: trim, w: [p[:w], uw].min, h: [p[:h], uh].min, label: p[:label], id: p[:id], rot: false, oversize: true }],
                        shelves: [], used: [p[:w], uw].min * [p[:h], uh].min, oversize: true }
            next
          end
          placed = false
          sheets.each do |s|
            next if s[:oversize]
            fits.each do |w, h, rot|
              shelf = s[:shelves].find { |sl| h <= sl[:h] + 1e-6 && sl[:x] + w <= uw + 1e-6 }
              if shelf
                s[:parts] << { x: trim + shelf[:x], y: trim + shelf[:y], w: w, h: h, label: p[:label], id: p[:id], rot: rot }
                shelf[:x] += w + kerf
                s[:used] += w * h
                placed = true
                break
              end
              top = s[:shelves].empty? ? 0.0 : s[:shelves][-1][:y] + s[:shelves][-1][:h] + kerf
              next unless top + h <= uh + 1e-6
              s[:shelves] << { y: top, h: h, x: w + kerf }
              s[:parts] << { x: trim, y: trim + top, w: w, h: h, label: p[:label], id: p[:id], rot: rot }
              s[:used] += w * h
              placed = true
              break
            end
            break if placed
          end
          next if placed
          w, h, rot = fits[0]
          sheets << { w: sw, h: sh, shelves: [{ y: 0.0, h: h, x: w + kerf }],
                      parts: [{ x: trim, y: trim, w: w, h: h, label: p[:label], id: p[:id], rot: rot }], used: w * h }
        end
        sheets.each { |s| s.delete(:shelves) }
        sheets
      end
    end
  end
end
