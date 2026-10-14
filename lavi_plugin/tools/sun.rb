# Estudo de sol: põe o modelo na cidade certa e cria cenas de sombra nos dias e horários escolhidos.
# Leve: não cria nenhuma geometria, só ajusta as sombras do próprio SketchUp e salva nas cenas.

module LAVIStudio
  module Plugin
    module Tools
      module Sun
        extend self
        H = Helpers

        # cidade => [latitude, longitude, fuso]
        CITIES = {
          'santo_andre' => ['Santo André', -23.663, -46.538, -3], 'sao_paulo' => ['São Paulo', -23.550, -46.633, -3],
          'campinas' => ['Campinas', -22.906, -47.061, -3], 'rio' => ['Rio de Janeiro', -22.907, -43.173, -3],
          'bh' => ['Belo Horizonte', -19.917, -43.934, -3], 'vitoria' => ['Vitória', -20.315, -40.312, -3],
          'curitiba' => ['Curitiba', -25.429, -49.271, -3], 'floripa' => ['Florianópolis', -27.595, -48.548, -3],
          'poa' => ['Porto Alegre', -30.035, -51.218, -3], 'brasilia' => ['Brasília', -15.794, -47.882, -3],
          'goiania' => ['Goiânia', -16.686, -49.264, -3], 'cuiaba' => ['Cuiabá', -15.601, -56.097, -4],
          'campo_grande' => ['Campo Grande', -20.469, -54.620, -4], 'salvador' => ['Salvador', -12.971, -38.501, -3],
          'recife' => ['Recife', -8.047, -34.877, -3], 'natal' => ['Natal', -5.795, -35.209, -3],
          'fortaleza' => ['Fortaleza', -3.732, -38.527, -3], 'belem' => ['Belém', -1.456, -48.490, -3],
          'manaus' => ['Manaus', -3.119, -60.022, -4]
        }.freeze
        DATES = { '03-21' => 'equinócio', '06-21' => 'inverno', '12-21' => 'verão' }.freeze

        def handle(action, p)
          case action
          when 'now'
            loc = place(p)
            d = (dates(p).first || ['06-21'])[0]
            h = (hours(p).first || 12)
            H.operation('lavi · Sol agora') { shade(loc, d, h, p) }
            H.ok("Sombras de #{label(d)} às #{hh(h)} em #{loc[0]}.")
          when 'scenes'
            loc = place(p)
            ds = dates(p)
            hs = hours(p)
            return H.err('Escolha pelo menos um dia.') if ds.empty?
            return H.err('Escreva os horários (ex.: 9, 12, 15).') if hs.empty?
            names = []
            H.operation('lavi · Estudo de sol') do
              ds.each do |d, _|
                hs.each do |h|
                  shade(loc, d, h, p)
                  name = "Sol · #{label(d)} · #{hh(h)}"
                  old = H.model.pages[name]
                  H.model.pages.erase(old) if old
                  pg = H.model.pages.add(name)
                  pg.use_shadow_info = true if pg.respond_to?(:use_shadow_info=)
                  names << name
                end
              end
            end
            H.ok("#{names.size} cenas de sol criadas em #{loc[0]}.", stats: [['Cenas', names.size.to_s], ['Cidade', loc[0]]], scenes: names)
          when 'off'
            H.model.shadow_info['DisplayShadows'] = false
            H.ok('Sombras desligadas.')
          else H.err('Ação desconhecida.')
          end
        end

        def place(p)
          if p['cidade'].to_s == 'outra'
            ["Lat #{H.br(H.num(p['lat'], -23.5), 3)}", H.num(p['lat'], -23.5), H.num(p['lon'], -46.6), H.num(p['fuso'], -3)]
          else
            CITIES[p['cidade'].to_s] || CITIES['santo_andre']
          end
        end

        def dates(p)
          list = DATES.keys.select { |k| p["d_#{k}"] == true || p["d_#{k}"] == 'true' }
          livre = p['data'].to_s.strip
          if livre =~ %r{\A(\d{1,2})/(\d{1,2})\z}
            list << format('%02d-%02d', Regexp.last_match(2).to_i, Regexp.last_match(1).to_i)
          end
          list.uniq.map { |k| [k, DATES[k]] }
        end

        def hours(p)
          p['horas'].to_s.scan(/(\d{1,2})(?:\s*[h:]\s*(\d{2}))?/).map { |h, mi| h.to_i + mi.to_i / 60.0 }.select { |x| x >= 5 && x <= 20 }.uniq.sort
        end

        def label(d)
          m, dd = d.split('-')
          "#{dd}/#{m}"
        end

        def hh(h)
          format('%02dh%s', h.floor, (h % 1).zero? ? '' : format('%02d', ((h % 1) * 60).round))
        end

        def shade(loc, d, h, p = {})
          si = H.model.shadow_info
          m, dd = d.split('-').map(&:to_i)
          {
            'City' => loc[0], 'Country' => 'Brasil', 'Latitude' => loc[1], 'Longitude' => loc[2], 'TZOffset' => loc[3].to_f,
            'ShadowTime' => Time.gm(Time.now.year, m, dd, h.floor, ((h % 1) * 60).round), 'DisplayShadows' => true,
            'NorthAngle' => H.num(p['norte'], 0)
          }.each do |k, v|
            begin
              si[k] = v
            rescue StandardError
              nil
            end
          end
        end

        Registry.register(:sun, name: 'Estudo de sol', tab: :pres, package: :pres, handler: self,
                                desc: 'Cidade, dia e horário: liga as sombras certas e cria as cenas do estudo de insolação.',
                                steps: ['Escolha a cidade', 'Marque dias e horários', 'Criar cenas'])
      end
    end
  end
end
