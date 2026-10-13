# Gera chaves de cliente. NUNCA vai no .rbz nem para cliente.
# Uso: ruby vendas/keygen.rb MARC 5     (pacotes: ARQ REV MARC QUANT PRO)
# O SECRET é lido de plane_plugin/core/license.rb (precisa ser o mesmo).

require 'digest'
require 'securerandom'

src = File.read(File.join(__dir__, '..', 'plane_plugin', 'core', 'license.rb'), encoding: 'UTF-8')
secret = src[/SECRET\s*=\s*'([^']+)'/, 1] or abort('SECRET não encontrado em license.rb')
pkg = (ARGV[0] || '').upcase
qtd = (ARGV[1] || 1).to_i
abort('Use: ruby vendas/keygen.rb <ARQ|REV|MARC|QUANT|PRO> [quantidade]') unless %w[ARQ REV MARC QUANT PRO].include?(pkg)
alphabet = ('A'..'Z').to_a + ('2'..'9').to_a - %w[O I]
qtd.times do
  serial = Array.new(5) { alphabet[SecureRandom.random_number(alphabet.size)] }.join
  check = Digest::SHA256.hexdigest("#{secret}|#{pkg}|#{serial}")[0, 8].upcase
  puts "PLANE-#{pkg}-#{serial}-#{check}"
end
