# Atualização automática
#
# O plugin lê updates/latest.json (no GitHub). Se houver versão maior que a instalada,
# baixa o .rbz, confere o SHA256 e instala com Sketchup.install_from_archive.
# Nunca instala sozinho com o SketchUp aberto: a checagem automática só AVISA (no painel);
# a instalação acontece quando a pessoa clica em atualizar. Preferência "auto_update" = só checar.

require 'json'
require 'digest'
require 'tmpdir'

module LAVIStudio
  module Plugin
    module Updater
      MANIFEST_URL = 'https://raw.githubusercontent.com/arqlais/plugin/HEAD/updates/latest.json'.freeze

      @busy = false
      @last = nil
      @state = nil
      @checked_at = nil

      module_function

      def auto?
        Helpers.pref('auto_update', true) != false # true = procurar novidades ao abrir (só avisa)
      end

      def set_auto(on)
        Helpers.set_pref('auto_update', on ? true : false)
      end

      def last
        @last
      end

      # Último aviso (o painel mostra a barra "Nova versão" mesmo se abrir depois)
      def state
        @state
      end

      # Ao abrir o painel: confere se ainda não conferiu na última hora
      def check_if_stale
        return if @checked_at && Time.now - @checked_at < 3600
        check(false)
      end

      # Botão "Atualizar" do painel: instala direto (o clique já é a confirmação)
      def install_now
        if @last && newer?(@last['version'])
          download(@last)
        else
          @install_after_check = true
          check(false)
        end
      end

      def newer?(remote, local = VERSION)
        a = remote.to_s.split('.').map(&:to_i)
        b = local.to_s.split('.').map(&:to_i)
        (a <=> b) == 1
      end

      # manual = true quando a pessoa clicou em "Procurar atualização"
      def check(manual = false)
        return if @busy
        unless defined?(Sketchup::Http::Request)
          UI.messagebox('Esta versão do SketchUp não permite atualização automática. Instale o .rbz novo pelo Gerenciador de extensões.') if manual
          return
        end
        @busy = true
        @checked_at = Time.now
        @req = Sketchup::Http::Request.new("#{MANIFEST_URL}?t=#{Time.now.to_i}", Sketchup::Http::GET)
        @req.start do |_r, res|
          @busy = false
          handle_manifest(res, manual)
        end
      rescue StandardError => e
        @busy = false
        notify(state: 'error', msg: "Não consegui procurar atualização: #{e.message}") if manual
      end

      def handle_manifest(res, manual)
        unless res && res.status_code == 200
          notify(state: 'error', msg: 'Sem conexão com o servidor de atualizações.') if manual
          return
        end
        info = JSON.parse(res.body)
        @last = info
        if newer?(info['version'])
          notify(state: 'available', version: info['version'], notes: info['notes'] || [])
          if @install_after_check
            @install_after_check = false
            download(info)
          elsif manual
            ask = UI.messagebox("LAVI #{info['version']} disponível.\n\n#{Array(info['notes']).join("\n")}\n\nAtualizar agora?", MB_YESNO)
            download(info) if ask == IDYES
          end
        else
          @install_after_check = false
          notify(state: 'latest', version: VERSION)
          UI.messagebox("Você já está na versão mais nova (#{VERSION}).") if manual
        end
      rescue StandardError => e
        notify(state: 'error', msg: "Arquivo de atualização inválido: #{e.message}") if manual
      end

      def download(info)
        notify(state: 'downloading', version: info['version'])
        @dl = Sketchup::Http::Request.new(info['url'], Sketchup::Http::GET)
        @dl.start do |_r, res|
          if res && res.status_code == 200
            install(res.body, info)
          else
            notify(state: 'error', msg: 'Falha ao baixar a atualização. Tente de novo mais tarde.')
          end
        end
      end

      def install(body, info)
        if info['sha256'] && Digest::SHA256.hexdigest(body) != info['sha256'].to_s.downcase
          notify(state: 'error', msg: 'O arquivo baixado não confere. Atualização cancelada por segurança.')
          return
        end
        path = File.join(Dir.tmpdir, "lavi_plugin_#{info['version']}.rbz")
        File.binwrite(path, body)
        begin
          Sketchup.install_from_archive(path, false)
        rescue ArgumentError
          Sketchup.install_from_archive(path)
        end
        notify(state: 'installed', version: info['version'])
        UI.messagebox("LAVI atualizado para #{info['version']}.\nFeche e abra o SketchUp para usar a versão nova.\n(Não precisa reinstalar nada.)")
      rescue StandardError => e
        notify(state: 'error', msg: "Não consegui instalar: #{e.message}")
      end

      def notify(data)
        @state = data
        Dialog.push('update', data) if defined?(Dialog)
      end
    end
  end
end
