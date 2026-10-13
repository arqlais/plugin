# Ferramentas de clique no modelo usadas pelas ferramentas do plugin

module PlaneLA
  module Plugin
    module Pickers
      # Clica pontos em sequência (paredes, rodapé manual…).
      # Enter ou duplo clique termina · clicar no 1º ponto fecha · Backspace volta · Esc cancela
      # Digitar um número no campo de medidas posiciona o próximo ponto naquela distância.
      class PointPicker
        def initialize(hint, single: false, max: nil, &on_done)
          @hint = hint
          @single = single
          @max = single ? 1 : max
          @on_done = on_done
          @pts = []
          @ip = Sketchup::InputPoint.new
          @ip_prev = Sketchup::InputPoint.new
        end

        def activate
          @pts = []
          status
        end

        def deactivate(view)
          view.invalidate
        end

        def resume(view)
          status
          view.invalidate
        end

        def status
          return Sketchup.status_text = "#{@hint} · Esc cancela" if @single
          Sketchup.status_text = "#{@hint} · Enter termina · clique no 1º ponto para fechar · Backspace volta · Esc cancela"
          Sketchup.vcb_label = 'Comprimento'
        end

        def onMouseMove(_flags, x, y, view)
          if @pts.empty?
            @ip.pick(view, x, y)
          else
            @ip.pick(view, x, y, @ip_prev)
          end
          view.tooltip = @ip.tooltip if @ip.valid?
          if @pts.any? && @ip.valid?
            Sketchup.vcb_value = @pts[-1].distance(@ip.position).to_l.to_s
          end
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y, @pts.empty? ? nil : @ip_prev)
          return unless @ip.valid?
          pt = @ip.position
          if @pts.size >= 3 && pt.distance(@pts[0]) < view.pixels_to_model(10, pt)
            finish(true)
            return
          end
          add_point(pt)
          return finish(false) if @max && @pts.size >= @max
          view.invalidate
        end

        def onLButtonDoubleClick(_flags, _x, _y, _view)
          finish(false)
        end

        def add_point(pt)
          @pts << pt
          @ip_prev.copy!(@ip)
        end

        def onUserText(text, view)
          return if @pts.empty?
          dist = text.to_l rescue nil
          return unless dist && @ip.valid?
          dir = @ip.position - @pts[-1]
          return unless dir.valid?
          dir.length = dist
          add_point(@pts[-1].offset(dir))
          view.invalidate
        end

        def onKeyDown(key, _repeat, _flags, view)
          if key == 13
            finish(false)
          elsif key == 8
            @pts.pop
            view.invalidate
          end
        end

        def onReturn(_view)
          finish(false)
        end

        def onCancel(_reason, view)
          @pts = []
          Sketchup.active_model.select_tool(nil)
          view.invalidate
        end

        def finish(closed)
          pts = @pts.dup
          # duplo clique adiciona o mesmo ponto duas vezes
          pts.pop while pts.size > 1 && pts[-1] == pts[-2]
          @pts = []
          Sketchup.active_model.select_tool(nil)
          @on_done.call(pts, closed) if pts.size >= (@single ? 1 : 2)
        end

        def draw(view)
          @ip.draw(view) if @ip.valid?
          return if @pts.empty?
          view.line_width = 3
          view.drawing_color = Sketchup::Color.new(255, 46, 136)
          line = @pts + (@ip.valid? ? [@ip.position] : [])
          view.draw(GL_LINE_STRIP, line) if line.size >= 2
          view.draw_points(@pts, 8, 2, Sketchup::Color.new(169, 112, 255))
        end

        def getExtents
          bb = Geom::BoundingBox.new
          @pts.each { |p| bb.add(p) }
          bb.add(@ip.position) if @ip.valid?
          bb
        end
      end

      # Clica numa face (pode estar dentro de grupo). Fica ativa até Esc.
      class FacePicker
        def initialize(hint, &on_pick)
          @hint = hint
          @on_pick = on_pick
          @ip = Sketchup::InputPoint.new
        end

        def activate
          Sketchup.status_text = "#{@hint} · Esc termina"
        end

        def resume(_view)
          activate
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          ph = view.pick_helper
          ph.do_pick(x, y)
          face = ph.picked_face
          @ip.pick(view, x, y)
          return UI.beep unless face && @ip.valid?
          path = nil
          tr = IDENTITY
          ph.count.times do |i|
            p = ph.path_at(i)
            next unless p && p.include?(face)
            path = p
            tr = ph.transformation_at(i)
            break
          end
          @on_pick.call(face, tr, @ip.position, path || [face])
          view.invalidate
        end

        def onCancel(_reason, _view)
          Sketchup.active_model.select_tool(nil)
        end

        def draw(view)
          @ip.draw(view) if @ip.valid?
        end
      end
    end
  end
end
