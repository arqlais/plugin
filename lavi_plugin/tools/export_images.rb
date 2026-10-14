# Exportar imagens em lote: todas as cenas (ou só a atual) em PNG/JPG, na resolução escolhida

module LAVIStudio
  module Plugin
    module Tools
      module ExportImages
        extend self
        H = Helpers
        RATIOS = { '16:9' => 16 / 9.0, '4:3' => 4 / 3.0, '3:2' => 1.5, '1:1' => 1.0, '4:5' => 0.8, '9:16' => 9 / 16.0,
                   'A4' => 297 / 210.0, 'A4r' => 210 / 297.0 }.freeze
        # direção do olhar de cada atalho de vista (no plano, a partir do centro do modelo)
        VIEWS = { 'frente' => [0, 1], 'fundos' => [0, -1], 'esquerda' => [1, 0], 'direita' => [-1, 0], 'diagonal' => [1, 1] }.freeze

        def handle(action, p)
          return camera(p) if action == 'camera'
          return guide(p) if action == 'guide'
          return H.err('Ação desconhecida.') unless action == 'export'
          m = H.model
          pages = p['escopo'] == 'atual' || m.pages.size.zero? ? [nil] : m.pages.to_a
          dir = UI.select_directory(title: 'Pasta para salvar as imagens')
          return H.ok('Cancelado.') unless dir
          dir = dir.dup.force_encoding('UTF-8')
          view = m.active_view
          w = H.num(p['largura'], 1920).to_i.clamp(320, 10_000)
          ratio = RATIOS[p['proporcao']] || (view.vpwidth.to_f / [view.vpheight, 1].max)
          h = (w / ratio).round
          ext = p['formato'] == 'jpg' ? 'jpg' : 'png'
          popt = m.options['PageOptions']
          old_trans = popt['ShowTransition']
          old_page = m.pages.selected_page
          popt['ShowTransition'] = false
          files = []
          pages.each_with_index do |pg, i|
            if pg
              m.pages.selected_page = pg
              view.refresh if view.respond_to?(:refresh)
            end
            base = pg ? pg.name : 'Vista atual'
            name = format('%02d - %s.%s', i + 1, base.gsub(/[\\\/:*?"<>|]/, '-'), ext)
            path = File.join(dir, name)
            opts = { filename: path, width: w, height: h, antialias: p['antialias'] != false && p['antialias'] != 'false' }
            opts[:transparent] = true if ext == 'png' && (p['transparente'] == true || p['transparente'] == 'true')
            opts[:compression] = 0.9 if ext == 'jpg'
            files << name if view.write_image(opts)
          end
          popt['ShowTransition'] = old_trans
          m.pages.selected_page = old_page if old_page
          UI.openURL("file:///#{dir.tr('\\', '/')}") if p['abrir'] != false && p['abrir'] != 'false'
          H.ok("#{files.size} imagem(ns) salva(s) em #{dir}.",
               stats: [['Imagens', files.size.to_s], ['Tamanho', "#{w} × #{h} px"], ['Formato', ext.upcase]])
        end

        # Atalhos de câmera: altura do olho, abertura (graus) e perspectiva de 2 pontos (olhar na horizontal)
        def camera(p)
          m = H.model
          view = m.active_view
          cam = view.camera
          h = H.num(p['cam_alt'], 160).to_f.cm
          fov = H.num(p['cam_fov'], 35).to_f.clamp(10, 120)
          two = p['cam_2p'] == true || p['cam_2p'] == 'true'
          v = VIEWS[p['cam_vista'].to_s]
          if v
            bb = m.bounds
            c = bb.center
            d = Geom::Vector3d.new(v[0], v[1], 0)
            d.normalize!
            dist = [bb.diagonal.to_f, 300.cm.to_f].max * 1.1
            eye = Geom::Point3d.new(c.x - d.x * dist, c.y - d.y * dist, h)
            two = true
          else
            eye = Geom::Point3d.new(cam.eye.x, cam.eye.y, h)
            d = cam.target - cam.eye
          end
          d = Geom::Vector3d.new(d.x, d.y, 0) if two
          d = Geom::Vector3d.new(0, 1, 0) if d.length.to_f < 1e-6
          d.normalize!
          target = Geom::Point3d.new(eye.x + d.x * 100, eye.y + d.y * 100, eye.z + d.z * 100)
          view.camera = Sketchup::Camera.new(eye, target, Z_AXIS, true, fov)
          page = m.pages.selected_page
          saved = false
          if page && (p['cam_cena'] == true || p['cam_cena'] == 'true')
            page.update(1) # 1 = só a câmera
            saved = true
          end
          H.ok(saved ? "Câmera aplicada e salva na cena \"#{page.name}\"." : 'Câmera aplicada na vista atual.',
               stats: [['Altura do olho', "#{H.br(H.num(p['cam_alt'], 160), 0)} cm"], ['Abertura', "#{H.br(fov, 0)}°"],
                       ['Perspectiva', two ? '2 pontos' : '3 pontos']])
        end

        # Moldura do formato + grade de terços desenhada por cima da tela (SketchUp 2023+, API de Overlay)
        def guide(p)
          on = p['guia'] == true || p['guia'] == 'true'
          return H.ok('A moldura precisa do SketchUp 2023 ou mais novo.') unless defined?(Sketchup::Overlay)
          m = H.model
          @guide ||= {}
          ov = @guide[m.guid]
          unless ov
            ov = FrameOverlay.new
            m.overlays.add(ov)
            @guide[m.guid] = ov
          end
          ov.ratio = RATIOS[p['proporcao']]
          ov.enabled = on
          m.active_view.invalidate
          H.ok(on ? 'Moldura ligada.' : 'Moldura desligada.')
        end

        if defined?(Sketchup::Overlay)
          class FrameOverlay < Sketchup::Overlay
            attr_accessor :ratio

            def initialize
              super('lavi.frame', 'LAVI · moldura da imagem', description: 'Recorte do formato escolhido e grade de terços.')
            end

            def draw(view)
              vw = view.vpwidth.to_f
              vh = view.vpheight.to_f
              r = @ratio || (vw / [vh, 1].max)
              w = vw
              h = w / r
              if h > vh
                h = vh
                w = h * r
              end
              x0 = (vw - w) / 2
              y0 = (vh - h) / 2
              pt = ->(x, y) { Geom::Point3d.new(x, y, 0) }
              view.drawing_color = Sketchup::Color.new(30, 20, 25, 110)
              [[0, 0, vw, y0], [0, y0 + h, vw, vh], [0, y0, x0, y0 + h], [x0 + w, y0, vw, y0 + h]].each do |a, b, c, d|
                next if c - a < 0.5 || d - b < 0.5
                view.draw2d(GL_QUADS, [pt.call(a, b), pt.call(c, b), pt.call(c, d), pt.call(a, d)])
              end
              view.line_width = 1
              view.line_stipple = ''
              view.drawing_color = Sketchup::Color.new(225, 20, 108)
              [1, 2].each do |k|
                view.draw2d(GL_LINES, [pt.call(x0 + w * k / 3.0, y0), pt.call(x0 + w * k / 3.0, y0 + h)])
                view.draw2d(GL_LINES, [pt.call(x0, y0 + h * k / 3.0), pt.call(x0 + w, y0 + h * k / 3.0)])
              end
              view.draw2d(GL_LINE_LOOP, [pt.call(x0, y0), pt.call(x0 + w, y0), pt.call(x0 + w, y0 + h), pt.call(x0, y0 + h)])
            end
          end
        end

        Registry.register(:export_images, name: 'Exportar imagens', tab: :pres, package: :pres, handler: self,
                                          desc: 'Salva todas as cenas em PNG ou JPG de uma vez, na resolução que você escolher.',
                                          steps: ['Escolha tamanho e formato', 'Escolha a pasta', 'Pronto'])
      end
    end
  end
end
