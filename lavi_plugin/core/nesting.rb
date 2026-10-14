# Plano de corte simples (prateleiras / guilhotina), sem depender do SketchUp.
# Testado em dev/test_geom.rb

module LAVIStudio
  module Plugin
    module Nesting
      module_function

      # pieces: [{w:, h:, label:}] em mm
      # opts: sheet_w, sheet_h, kerf, trim, rotate (true = pode girar, false = respeitar veio)
      # Devolve [{w:, h:, parts: [{x:, y:, w:, h:, label:, rot:}], used: área}]
      def pack(pieces, opts = {})
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
            sheets << { w: sw, h: sh, parts: [{ x: trim, y: trim, w: [p[:w], uw].min, h: [p[:h], uh].min, label: p[:label], rot: false, oversize: true }],
                        shelves: [], used: [p[:w], uw].min * [p[:h], uh].min, oversize: true }
            next
          end
          placed = false
          sheets.each do |s|
            next if s[:oversize]
            fits.each do |w, h, rot|
              shelf = s[:shelves].find { |sl| h <= sl[:h] + 1e-6 && sl[:x] + w <= uw + 1e-6 }
              if shelf
                s[:parts] << { x: trim + shelf[:x], y: trim + shelf[:y], w: w, h: h, label: p[:label], rot: rot }
                shelf[:x] += w + kerf
                s[:used] += w * h
                placed = true
                break
              end
              top = s[:shelves].empty? ? 0.0 : s[:shelves][-1][:y] + s[:shelves][-1][:h] + kerf
              next unless top + h <= uh + 1e-6
              s[:shelves] << { y: top, h: h, x: w + kerf }
              s[:parts] << { x: trim, y: trim + top, w: w, h: h, label: p[:label], rot: rot }
              s[:used] += w * h
              placed = true
              break
            end
            break if placed
          end
          next if placed
          w, h, rot = fits[0]
          sheets << { w: sw, h: sh, shelves: [{ y: 0.0, h: h, x: w + kerf }],
                      parts: [{ x: trim, y: trim, w: w, h: h, label: p[:label], rot: rot }], used: w * h }
        end
        sheets.each { |s| s.delete(:shelves) }
        sheets
      end
    end
  end
end
