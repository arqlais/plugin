# Licenças por pacote
#
# Chave: PLANE-<ARQ|REV|PRES|MARC|QUANT|PRO>-<5 caracteres>-<8 hex>
# Verificador = 8 primeiros hex de SHA256("SECRET|PACOTE|SERIAL")
#
# ANTES DE VENDER: DEV_MODE = false e trocar o SECRET (o vendas/keygen.rb lê daqui).

require 'digest'
require 'json'

module PlaneLA
  module Plugin
    module License
      DEV_MODE = true
      SECRET   = 'troque-este-segredo-antes-de-vender'.freeze
      PREF     = 'PlanePlugin'.freeze
      CODES    = %w[ARQ REV PRES MARC QUANT PRO].freeze
      PATTERN  = /\APLANE-(ARQ|REV|PRES|MARC|QUANT|PRO)-([A-Z0-9]{5})-([0-9A-F]{8})\z/

      module_function

      def check_digits(pkg, serial)
        Digest::SHA256.hexdigest("#{SECRET}|#{pkg}|#{serial}")[0, 8].upcase
      end

      # Devolve o código do pacote (ex.: "MARC") ou nil
      def parse(key)
        k = key.to_s.strip.upcase.gsub(/\s+/, '')
        m = PATTERN.match(k)
        return nil unless m
        return nil unless check_digits(m[1], m[2]) == m[3]
        m[1]
      end

      def keys
        raw = Sketchup.read_default(PREF, 'licenses', '[]')
        list = JSON.parse(raw.to_s) rescue []
        list.is_a?(Array) ? list : []
      end

      def packages
        keys.map { |k| parse(k) }.compact.uniq
      end

      def activate(key)
        pkg = parse(key)
        return { ok: false, msg: 'Chave inválida. Confira se copiou inteira, com os traços.' } unless pkg
        list = (keys + [key.to_s.strip.upcase]).uniq
        Sketchup.write_default(PREF, 'licenses', JSON.generate(list))
        name = pkg == 'PRO' ? 'todos os pacotes' : "o pacote #{Registry::PACKAGES[pkg.downcase.to_sym][:name]}"
        { ok: true, msg: "Pronto! Você liberou #{name}.", package: pkg }
      end

      def allowed?(package)
        pkg = package.to_sym
        return true if DEV_MODE
        return true if Registry::PACKAGES[pkg] && Registry::PACKAGES[pkg][:free]
        owned = packages
        owned.include?('PRO') || owned.include?(pkg.to_s.upcase)
      end

      def status
        Registry::PACKAGES.map do |id, p|
          { id: id, name: p[:name], free: p[:free], active: allowed?(id) }
        end
      end
    end
  end
end
