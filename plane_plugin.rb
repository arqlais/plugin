# Planê Plugin — ferramentas para arquitetura, interiores e marcenaria no SketchUp
# Arquivo de carregamento (fica na pasta Plugins do SketchUp)

require 'sketchup.rb'
require 'extensions.rb'

module PlaneLA
  module Plugin
    PLUGIN_ID   = 'plane_plugin'.freeze
    PLUGIN_NAME = 'Planê Plugin'.freeze
    VERSION     = '0.4.2'.freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_ID, 'main'))
      ext.description = 'Paredes, vãos, revestimentos, marcenaria em blocos dinâmicos, quantitativo e orçamento.'
      ext.version     = VERSION
      ext.creator     = 'Laís A. Vieira · Planê'
      ext.copyright   = "© #{Time.now.year} Laís A. Vieira"
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
