# Painel único (HtmlDialog) e ponte JS <-> Ruby
#
# JS chama sketchup.run(JSON {req, tool, action, params})
#   -> handler.handle(action, params) -> {ok:, msg:, ...}
#   -> PLN.onResult([req, res])
# Ruby também pode empurrar eventos: Dialog.push('update', {...}) -> PLN.on('update', {...})

require 'json'

module LAVIStudio
  module Plugin
    module Dialog
      @dlg = nil
      @open_tool = nil

      module_function

      def show(tool = nil)
        @open_tool = tool && tool.to_s
        if @dlg && @dlg.visible?
          @dlg.bring_to_front
          push('open', id: @open_tool) if @open_tool
          return
        end
        @dlg = build
        @dlg.show
      end

      def build
        d = UI::HtmlDialog.new(
          dialog_title: PLUGIN_NAME,
          preferences_key: 'LaviPluginPanel',
          scrollable: false, resizable: true,
          width: 430, height: 760, min_width: 360, min_height: 480,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        d.set_file(File.join(ROOT, 'ui', 'index.html'))

        d.add_action_callback('ready') { |_c, _a| send_state }
        d.add_action_callback('run') { |_c, payload| run(payload) }
        d.add_action_callback('favorite') do |_c, id|
          push('favorites', Helpers.toggle_favorite(id.to_s))
        end
        d.add_action_callback('theme') { |_c, theme| Helpers.set_pref('theme', theme.to_s) }
        d.add_action_callback('activate') do |_c, key|
          res = License.activate(key.to_s)
          push('license', res)
          send_state if res[:ok]
        end
        d.add_action_callback('update') do |_c, what|
          case what.to_s
          when 'check' then Updater.check(true)
          when 'install' then Updater.install_now
          when 'auto_on' then Updater.set_auto(true)
          when 'auto_off' then Updater.set_auto(false)
          end
        end
        d.add_action_callback('open_url') { |_c, url| UI.openURL(url.to_s) if url.to_s.start_with?('https://') }
        d
      end

      def send_state
        state = {
          name: PLUGIN_NAME,
          version: VERSION,
          tools: Registry.to_ui,
          packages: License.status,
          dev: License::DEV_MODE,
          favorites: Helpers.favorites,
          theme: Helpers.pref('theme', 'light'),
          auto_update: Updater.auto?,
          update: Updater.state,
          units: model_units,
          open: @open_tool
        }
        exec("PLN.init(#{JSON.generate(state)})")
        Updater.check_if_stale if Updater.auto?
        @open_tool = nil
      end

      def model_units
        Sketchup.active_model.options['UnitsOptions']['LengthUnit']
      rescue StandardError
        nil
      end

      def run(payload)
        data = JSON.parse(payload.to_s)
        req = data['req']
        tool = Registry.find(data['tool'])
        res =
          if tool.nil? || tool[:handler].nil?
            Helpers.err('Ferramenta indisponível.')
          elsif !License.allowed?(tool[:package])
            Helpers.err("Esta ferramenta faz parte do pacote #{Registry::PACKAGES[tool[:package]][:name]}. Ative sua chave em Licença.", locked: true)
          else
            begin
              tool[:handler].handle(data['action'].to_s, data['params'] || {})
            rescue StandardError => e
              puts "[LAVI] #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
              Helpers.err("Algo deu errado: #{e.message}")
            end
          end
        exec("PLN.onResult(#{JSON.generate([req, res || Helpers.ok('Feito.')])})")
      end

      def push(event, data)
        return unless @dlg && @dlg.visible?
        exec("PLN.on(#{JSON.generate(event.to_s)}, #{JSON.generate(data)})")
      end

      def exec(js)
        @dlg.execute_script(js) if @dlg
      end
    end
  end
end
