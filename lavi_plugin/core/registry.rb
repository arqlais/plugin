# Catálogo de ferramentas, pacotes e abas

module LAVIStudio
  module Plugin
    module Registry
      # Pacotes vendidos separadamente. A chave PRO libera todos.
      PACKAGES = {
        base:  { name: 'Essencial',     free: true,  color: 'gray' },
        arq:   { name: 'Arquitetura',   free: false, color: 'pink' },
        rev:   { name: 'Revestimentos', free: false, color: 'lilac' },
        pres:  { name: 'Apresentação',  free: false, color: 'lilac' },
        marc:  { name: 'Marcenaria',    free: false, color: 'pink' },
        quant: { name: 'Quantitativo',  free: false, color: 'lilac' }
      }.freeze

      TABS = {
        home:  { name: 'Início' },
        pres:  { name: 'Apresentação' },
        arq:   { name: 'Arquitetura' },
        rev:   { name: 'Revestimentos' },
        marc:  { name: 'Marcenaria' },
        quant: { name: 'Quantitativo' },
        base:  { name: 'Essenciais' }
      }.freeze

      @tools = {}

      module_function

      def register(id, name:, tab:, package:, handler: nil, desc: '', status: :ready, steps: [])
        @tools[id.to_sym] = {
          id: id.to_sym, name: name, tab: tab.to_sym, package: package.to_sym,
          handler: handler, desc: desc, status: status.to_sym, steps: steps
        }
      end

      def find(id)
        @tools[id.to_s.to_sym]
      end

      def all
        @tools.values
      end

      def in_tab(tab)
        all.select { |t| t[:tab] == tab.to_sym }
      end

      # Versão segura para mandar ao painel (sem o handler)
      def to_ui
        all.map do |t|
          t.reject { |k, _| k == :handler }.merge(locked: !License.allowed?(t[:package]))
        end
      end
    end
  end
end
