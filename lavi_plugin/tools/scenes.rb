# Cenas automáticas: plantas por nível, cobertura, cortes AA/BB, 4 fachadas e perspectiva

module LAVIStudio
  module Plugin
    module Tools
      module Scenes
        extend self
        H = Helpers

        def handle(action, p)
          return H.err('Ação desconhecida.') unless action == 'create'
          m = H.model
          bb = m.bounds
          return H.err('O modelo está vazio.') if bb.empty?
          levels = parse_levels(p['niveis'])
          cut = H.cm(H.num(p['corte'], 120))
          view = m.active_view
          ro = m.rendering_options
          popt = m.options['PageOptions']
          old_trans = popt['ShowTransition']
          old_cam = view.camera
          old_sec = ro['DisplaySectionPlanes']
          made = []
          H.operation('lavi · Cenas automáticas') do
            popt['ShowTransition'] = false
            ro['DisplaySectionPlanes'] = false
            tag = H.tag('lavi · Cortes')
            c = bb.center
            d = bb.diagonal
            if on?(p['plantas'])
              levels.each do |name, lv|
                sp = section(m, tag, [c.x, c.y, lv + cut], [0, 0, -1], "Planta #{name}")
                sp.activate
                look(view, [c.x, c.y, bb.max.z + d], [c.x, c.y, bb.min.z], Y_AXIS)
                made << page(m, "Planta · #{name}")
              end
            end
            if on?(p['cobertura'])
              clear_section(m)
              look(view, [c.x, c.y, bb.max.z + d], [c.x, c.y, bb.min.z], Y_AXIS)
              made << page(m, 'Planta de cobertura')
            end
            if on?(p['cortes'])
              sp = section(m, tag, [c.x, c.y, c.z], [0, 1, 0], 'Corte AA')
              sp.activate
              look(view, [c.x, bb.min.y - d, c.z], [c.x, c.y, c.z], Z_AXIS)
              made << page(m, 'Corte AA')
              sp = section(m, tag, [c.x, c.y, c.z], [1, 0, 0], 'Corte BB')
              sp.activate
              look(view, [bb.min.x - d, c.y, c.z], [c.x, c.y, c.z], Z_AXIS)
              made << page(m, 'Corte BB')
            end
            if on?(p['fachadas'])
              clear_section(m)
              [['Fachada frontal', [c.x, bb.min.y - d, c.z]], ['Fachada posterior', [c.x, bb.max.y + d, c.z]],
               ['Fachada lateral esquerda', [bb.min.x - d, c.y, c.z]], ['Fachada lateral direita', [bb.max.x + d, c.y, c.z]]].each do |n, eye|
                look(view, eye, [c.x, c.y, c.z], Z_AXIS)
                made << page(m, n)
              end
            end
            if on?(p['perspectiva'])
              clear_section(m)
              old_cam.perspective = true
              view.camera = old_cam
              made << page(m, 'Perspectiva')
            end
            ro['DisplaySectionPlanes'] = old_sec
            popt['ShowTransition'] = old_trans
          end
          return H.err('Marque pelo menos um tipo de cena.') if made.empty?
          H.ok("#{made.size} cenas criadas. Veja as abas no topo da tela do SketchUp.",
               stats: [['Cenas', made.size.to_s], ['Níveis', levels.size.to_s], ['Altura do corte', "#{H.br(H.num(p['corte'], 120), 0)} cm"]],
               list: made)
        end

        def on?(v)
          v == true || v == 'true'
        end

        # "Térreo=0; Superior=300" ou "0, 300" (cm) -> [[nome, z em polegadas], ...]
        def parse_levels(text)
          items = text.to_s.split(/[;\n]/).map(&:strip).reject(&:empty?)
          items = text.to_s.split(',').map(&:strip).reject(&:empty?) if items.size == 1 && items[0] !~ /=/
          items = ['Térreo=0'] if items.empty?
          items.map do |it|
            name, val = it.include?('=') ? it.split('=', 2) : [nil, it]
            cm = H.num(val, 0)
            name = name.to_s.strip
            name = "Nível #{cm >= 0 ? '+' : ''}#{H.br(cm / 100.0)}" if name.empty?
            [name, H.cm(cm)]
          end.sort_by(&:last)
        end

        def section(m, tag, pt, normal, name)
          sp = m.entities.add_section_plane(pt, normal)
          sp.layer = tag
          sp.name = name if sp.respond_to?(:name=)
          sp
        end

        def clear_section(m)
          m.entities.active_section_plane = nil if m.entities.respond_to?(:active_section_plane=)
        end

        def look(view, eye, target, up)
          cam = Sketchup::Camera.new(Geom::Point3d.new(*eye.to_a), Geom::Point3d.new(*target.to_a), up)
          cam.perspective = false
          view.camera = cam
          view.zoom_extents
        end

        def page(m, name)
          pg = m.pages[name]
          if pg
            pg.update
          else
            pg = m.pages.add(name)
          end
          pg.name
        end

        Registry.register(:scenes, name: 'Cenas automáticas', tab: :pres, package: :pres, handler: self,
                                   desc: 'Plantas por nível, cobertura, cortes AA/BB, 4 fachadas e perspectiva num clique.',
                                   steps: ['Informe os níveis', 'Marque o que quer', 'Criar cenas'])
      end
    end
  end
end
