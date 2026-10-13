# Carrega o .rbz como o SketchUp faria (com uma API simulada) e abre o painel.
# Uso: ruby -I dev/stub dev/load_test.rb [arquivo.rbz]
require 'tmpdir'
rbz = ARGV[0] || File.expand_path('../updates/plane_plugin.rbz', __dir__)
PLUGINS = Dir.mktmpdir('Plugins')
system('unzip', '-q', '-o', rbz, '-d', PLUGINS) or abort('não consegui abrir o rbz')
require_relative 'stub/su_stub'
require File.join(PLUGINS, 'plane_plugin.rb')
P = PlaneLA::Plugin
abort("ERROS AO CARREGAR:\n#{P::LOAD_ERRORS.join("\n")}") unless P::LOAD_ERRORS.empty?
puts "carregou #{P::Registry.all.size} ferramentas (Ruby #{RUBY_VERSION})"
P.open_panel
abort('painel não abriu') unless $js.last.to_s.start_with?('PLN.init(')
d = P::Dialog.instance_variable_get(:@dlg)
d.call('run', '{"req":1,"tool":"stairs","action":"calc","params":{"alt":280}}')
abort('ferramenta não respondeu') unless $js.last.include?('"ok":true')
($timers || []).each(&:call)
puts 'painel e ferramenta OK'
