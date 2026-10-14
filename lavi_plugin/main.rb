# LAVI — menu, barra de ferramentas e carregamento das ferramentas
#
# Cada arquivo é carregado separado: se um falhar, o resto do plugin abre mesmo assim
# e aparece uma mensagem com o erro (também salvo em %TEMP%/lavi_plugin_erros.txt).

require 'sketchup.rb'
require 'json'
require 'tmpdir'

module LAVIStudio
  module Plugin
    # caminho em UTF-8 (pastas de usuário com acento no Windows, ex.: C:\Users\Laís)
    ROOT = File.dirname(__FILE__.dup.force_encoding('UTF-8')).freeze
    LOAD_ERRORS = []
    TOOLBAR = [
      %i[scenes export_images room_tags],
      %i[edges materials texmap lights],
      %i[walls openings dwg_walls stairs roofs dims],
      %i[tiling baseboard ceiling],
      %i[takeoff furniture],
      %i[measure isolate shape array fix_faces model_health]
    ].freeze

    def self.safe_require(*parts)
      require File.join(ROOT, *parts)
      true
    rescue ScriptError, StandardError => e
      LOAD_ERRORS << "#{parts.join('/')}: #{e.class}: #{e.message}\n    #{Array(e.backtrace).first(3).join("\n    ")}"
      false
    end

    def self.report_errors
      return if LOAD_ERRORS.empty?
      log = File.join(Dir.tmpdir, 'lavi_plugin_erros.txt')
      text = "lavi #{VERSION} · SketchUp #{Sketchup.version} · Ruby #{RUBY_VERSION}\n\n#{LOAD_ERRORS.join("\n\n")}"
      File.write(log, text, encoding: 'UTF-8') rescue nil
      puts "[lavi] #{text}"
      UI.messagebox("lavi: algumas partes não carregaram.\n\n#{LOAD_ERRORS.map { |l| l.lines.first }.join}\n" \
                    "Tire um print desta mensagem e mande para o suporte.\nDetalhes em: #{log}")
    end

    def self.open_panel(tool = nil)
      Dialog.show(tool)
    rescue StandardError => e
      LOAD_ERRORS << "abrir painel: #{e.class}: #{e.message}\n    #{Array(e.backtrace).first(3).join("\n    ")}"
      report_errors
    end

    %w[registry license helpers geom sweep nesting pickers updater dialog].each do |f|
      safe_require('core', f)
    end
    %w[
      walls openings dwg_walls stairs roofs urban_index
      tiling baseboard ceiling
      cut_list countertop
      scenes export_images room_tags
      takeoff furniture
      model_health align replace auto_tags measure isolate
      dwg_clean dims array fix_faces smart_select
      shape edges materials texmap lights randomize
    ].each { |f| safe_require('tools', f) }

    unless file_loaded?(__FILE__)
      begin
        menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
        menu.add_item('Abrir painel') { open_panel }
        menu.add_separator
        if defined?(Registry)
          Registry::TABS.each do |tab_id, tab|
            next if tab_id == :home
            sub = menu.add_submenu(tab[:name])
            Registry.in_tab(tab_id).each do |t|
              next unless t[:status] == :ready
              sub.add_item(t[:name]) { open_panel(t[:id]) }
            end
          end
          menu.add_separator
        end
        menu.add_item('Procurar atualização') { Updater.check(true) if defined?(Updater) }
        menu.add_item('Ativar licença') { open_panel(:license) }

        # Barra: só o ícone principal colorido; o resto em traço fino, separado por grupo
        tb = UI::Toolbar.new(PLUGIN_NAME)
        cmd = UI::Command.new(PLUGIN_NAME) { open_panel }
        icon = File.join(ROOT, 'ui', 'icon.svg')
        cmd.small_icon = icon
        cmd.large_icon = icon
        cmd.tooltip = PLUGIN_NAME
        cmd.status_bar_text = 'Abre o painel do lavi'
        tb.add_item(cmd)
        TOOLBAR.each do |group|
          tb.add_separator
          group.each do |id|
            t = defined?(Registry) && Registry.find(id)
            next unless t
            c = UI::Command.new(t[:name]) { open_panel(id) }
            svg = File.join(ROOT, 'ui', 'icons', "#{id}.svg")
            c.small_icon = svg
            c.large_icon = svg
            c.tooltip = t[:name]
            c.status_bar_text = t[:desc]
            tb.add_item(c)
          end
        end
        tb.restore
      rescue StandardError => e
        LOAD_ERRORS << "menu/barra: #{e.class}: #{e.message}\n    #{Array(e.backtrace).first(3).join("\n    ")}"
      end

      # mostra erros (se houver) e procura atualização em silêncio depois que o SketchUp abrir
      UI.start_timer(3, false) { report_errors }
      UI.start_timer(20, false) { Updater.check(false) if defined?(Updater) && Updater.auto? }
      # e de novo a cada 3 h, para quem deixa o SketchUp aberto o dia todo
      UI.start_timer(3 * 3600, true) { Updater.check(false) if defined?(Updater) && Updater.auto? }
      file_loaded(__FILE__)
    end
  end
end
