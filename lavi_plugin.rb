# LAVI — ferramentas para arquitetura, interiores e marcenaria no SketchUp
# Arquivo de carregamento (fica na pasta Plugins do SketchUp)

require 'sketchup.rb'
require 'extensions.rb'

module LAVIStudio
  module Plugin
    PLUGIN_ID   = 'lavi_plugin'.freeze
    PLUGIN_NAME = 'lavi'.freeze
    VERSION     = '0.11.1'.freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_ID, 'main'))
      ext.description = 'Paredes, vãos, revestimentos, cenas, exportação de imagens, marcenaria e quantitativo.'
      ext.version     = VERSION
      ext.creator     = 'Laís A. Vieira · lavi'
      ext.copyright   = "© #{Time.now.year} Laís A. Vieira"
      Sketchup.register_extension(ext, true)
      EXTENSION = ext # usado no aviso de atualização (UI::Notification)
      file_loaded(__FILE__)
    end
  end
end
