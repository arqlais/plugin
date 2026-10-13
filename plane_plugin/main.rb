# Planê Plugin — menu, barra de ferramentas e carregamento das ferramentas

require 'sketchup.rb'
require 'json'

module Plane
  module Plugin
    ROOT = File.dirname(__FILE__).freeze

    require File.join(ROOT, 'core', 'registry')
    require File.join(ROOT, 'core', 'license')
    require File.join(ROOT, 'core', 'helpers')
    require File.join(ROOT, 'core', 'geom')
    require File.join(ROOT, 'core', 'nesting')
    require File.join(ROOT, 'core', 'pickers')
    require File.join(ROOT, 'core', 'updater')
    require File.join(ROOT, 'core', 'dialog')

    %w[
      walls openings dwg_walls stairs roofs urban_index
      tiling baseboard ceiling
      joinery cut_list countertop
      takeoff budget
      model_health align replace auto_tags
    ].each { |f| require File.join(ROOT, 'tools', f) }

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
      menu.add_item('Abrir painel') { Dialog.show }
      menu.add_separator
      Registry::TABS.each do |tab_id, tab|
        next if tab_id == :home
        sub = menu.add_submenu(tab[:name])
        Registry.in_tab(tab_id).each do |t|
          next unless t[:status] == :ready
          sub.add_item(t[:name]) { Dialog.show(t[:id]) }
        end
      end
      menu.add_separator
      menu.add_item('Procurar atualização') { Updater.check(true) }
      menu.add_item('Ativar licença') { Dialog.show(:license) }

      tb = UI::Toolbar.new(PLUGIN_NAME)
      cmd = UI::Command.new(PLUGIN_NAME) { Dialog.show }
      icon = File.join(ROOT, 'ui', 'icon.svg')
      cmd.small_icon = icon
      cmd.large_icon = icon
      cmd.tooltip = PLUGIN_NAME
      cmd.status_bar_text = 'Abre o painel do Planê Plugin'
      tb.add_item(cmd)
      tb.restore

      # procura atualização em silêncio alguns segundos depois de abrir o SketchUp
      UI.start_timer(8, false) { Updater.check(false) }
      file_loaded(__FILE__)
    end
  end
end
