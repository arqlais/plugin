# LAVI Tools — suíte de ferramentas para arquitetura e interiores no SketchUp
# Arquivo de carregamento (fica na pasta Plugins do SketchUp)

require 'sketchup.rb'
require 'extensions.rb'

module LAVI
  module Tools
    PLUGIN_ID   = 'lavi_tools'.freeze
    PLUGIN_NAME = 'LAVI Tools'.freeze
    VERSION     = '0.3.0'.freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_ID, 'main'))
      ext.description = 'Ferramentas paramétricas para arquitetura, revestimentos, marcenaria e quantitativo.'
      ext.version     = VERSION
      ext.creator     = 'Laís A. Vieira · laís 3d'
      ext.copyright   = "© #{Time.now.year} Laís A. Vieira"
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
