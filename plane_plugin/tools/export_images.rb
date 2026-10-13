# Exportar imagens em lote: todas as cenas (ou só a atual) em PNG/JPG, na resolução escolhida

module PlaneLA
  module Plugin
    module Tools
      module ExportImages
        extend self
        H = Helpers
        RATIOS = { '16:9' => 16 / 9.0, '4:3' => 4 / 3.0, '1:1' => 1.0, 'A4' => 297 / 210.0 }.freeze

        def handle(action, p)
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

        Registry.register(:export_images, name: 'Exportar imagens', tab: :pres, package: :pres, handler: self,
                                          desc: 'Salva todas as cenas em PNG ou JPG de uma vez, na resolução que você escolher.',
                                          steps: ['Escolha tamanho e formato', 'Escolha a pasta', 'Pronto'])
      end
    end
  end
end
