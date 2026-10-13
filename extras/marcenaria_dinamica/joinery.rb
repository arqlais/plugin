# Marcenaria em COMPONENTE DINÂMICO nativo do SketchUp
#
# - O plugin calcula cada peça (core/dc_tree.rb + tools/joinery_spec.rb) e já monta o móvel no lugar.
# - As mesmas fórmulas ficam gravadas em dynamic_attributes, no padrão dos blocos dinâmicos
#   feitos no SketchUp (rótulos LenX/X/Hidden/Material…, peças como componentes),
#   então o bloco continua esticando com a Escala sem deformar, mudando em Opções do componente
#   e abrindo portas/gavetas com Interagir, mesmo sem o plugin.
# - "Atualizar" remonta pelo cálculo do plugin; "Diagnóstico" grava um relatório do bloco.

module PlaneLA
  module Plugin
    module Tools
      module Joinery
        extend self
        H = Helpers
        S = JoinerySpec
        DA = 'dynamic_attributes'.freeze

        # atributos do próprio SketchUp e o rótulo que o componente dinâmico espera
        BUILTIN = {
          'x' => 'X', 'y' => 'Y', 'z' => 'Z', 'lenx' => 'LenX', 'leny' => 'LenY', 'lenz' => 'LenZ',
          'rotx' => 'RotX', 'roty' => 'RotY', 'rotz' => 'RotZ', 'hidden' => 'Hidden',
          'material' => 'Material', 'copies' => 'Copies', 'onclick' => 'onClick', 'name' => 'Name'
        }.freeze

        LIBRARY = [
          ['Inferior 40 · 1 porta',      'inferior',   { 'lx' => 40, 'frente' => 1 }],
          ['Inferior 80 · 2 portas',     'inferior',   { 'lx' => 80, 'frente' => 1, 'nportas' => 2 }],
          ['Inferior 60 · gaveta+porta', 'inferior',   { 'lx' => 60, 'frente' => 2 }],
          ['Gaveteiro 45 · 4 gavetas',   'gaveteiro',  {}],
          ['Aéreo 40 · 1 porta',         'aereo',      { 'lx' => 40, 'nportas' => 1 }],
          ['Aéreo 80 · 2 portas',        'aereo',      {}],
          ['Aéreo 80 · basculante',      'basculante', {}],
          ['Torre 60',                   'torre',      {}],
          ['Nicho 60',                   'nicho',      {}]
        ].freeze

        USER_KEYS = {
          'lx' => 'lenx', 'ly' => 'leny', 'lz' => 'lenz', 'frente' => 'frente', 'nportas' => 'nportas',
          'ngav' => 'ngav', 'hgav' => 'hgav', 'prat' => 'prat', 'puxador' => 'puxador', 'matfrente' => 'matfrente',
          'matcaixa' => 'matcaixa', 'tampo' => 'tampo', 'mattampo' => 'mattampo', 'esptampo' => 'esptampo',
          'esp' => 'esp', 'espf' => 'espf', 'fundo' => 'fundo', 'folga' => 'folga', 'rod' => 'rod', 'rodrec' => 'rodrec'
        }.freeze
        LEN_KEYS = %w[lenx leny lenz hgav esptampo esp espf fundo folga rod rodrec].freeze

        # ---------------------------------------------------------------------
        def handle(action, p)
          case action
          when 'insert'
            Sketchup.active_model.select_tool(
              Pickers::PointPicker.new('Marcenaria: clique onde fica o canto frontal esquerdo do módulo', single: true) do |pts, _c|
                begin
                  inst = create(p, pts[0])
                  Dialog.push('result', tool: 'joinery', ok: true,
                                        msg: "#{inst.definition.name} inserido. Estique com a Escala ou edite em Janela › Opções do componente.")
                rescue StandardError => e
                  Dialog.push('result', tool: 'joinery', ok: false, msg: e.message)
                end
              end
            )
            H.ok('Clique no modelo onde fica o canto frontal esquerdo do módulo.', picking: true)
          when 'distribute' then distribute(p)
          when 'read' then read_selected
          when 'update' then update_selected(p)
          when 'library' then save_library(p)
          when 'redraw' then dc_redraw
          when 'diagnose' then diagnose
          when 'toggle'
            H.ok('Use a ferramenta Interagir (mãozinha) e clique na porta ou gaveta: ela abre e fecha com animação.')
          else
            H.err('Ação desconhecida.')
          end
        end

        # ---- painel → escolhas -------------------------------------------------
        def settings(p)
          t = S::TIPOS[p['tipo']] || S::TIPOS['inferior']
          {
            tipo: S::TIPOS.key?(p['tipo']) ? p['tipo'] : 'inferior', nome: t[:nome],
            lx: H.num(p['lx'], t[:lx]), ly: H.num(p['ly'], t[:ly]), lz: H.num(p['lz'], t[:lz]),
            frente: H.num(p['frente'], t[:frente]).to_i, nportas: H.num(p['nportas'], t[:nportas]).to_i,
            ngav: [[H.num(p['ngav'], t[:ngav]).to_i, 1].max, S::MAX_GAV].min, hgav: H.num(p['hgav'], 18),
            prat: [[H.num(p['prat'], t[:prat]).to_i, 0].max, S::MAX_PRAT].min, puxador: H.num(p['puxador'], 1).to_i,
            matfrente: p['matfrente'] || 'PLN_Branco', matcaixa: p['matcaixa'] || 'PLN_Branco',
            tampo: H.num(p['tampo'], t[:tampo]).to_i, mattampo: p['mattampo'] || 'PLN_QuartzoBranco',
            esptampo: H.num(p['esptampo'], 2), esp: H.num(p['esp'], 1.5), espf: H.num(p['espf'], 1.8),
            fundo: H.num(p['fundo'], 0.6), folga: H.num(p['folga'], 0.3),
            rod: H.num(p['rod'], t[:rod]), rodrec: H.num(p['rodrec'], 5), pz: t[:pz]
          }
        end

        def ensure_materials
          (S::MAT_FRENTE + S::MAT_TAMPO).each { |_l, n, hex| H.material(n, hex) }
          S::FIXED.each { |n, hex| H.material(n, hex) }
        end

        # ---- criação -----------------------------------------------------------
        def create(p, at = ORIGIN, rot = nil)
          s = settings(p)
          inst = nil
          H.operation('Planê · Marcenaria') do
            ensure_materials
            defs = H.model.definitions
            defn = defs.add(defs.unique_name("Planê #{s[:nome]} #{s[:lx].round}x#{s[:lz].round}"))
            defn.description = "Módulo de marcenaria #{s[:nome].downcase} · Planê Plugin"
            fill(defn, s)
            tr = Geom::Transformation.new(at)
            tr = tr * rot if rot
            inst = H.model.active_entities.add_instance(defn, tr)
            copy_root_values(defn, inst)
            inst.layer = H.tag('Planê · Marcenaria')
          end
          inst
        end

        # Monta (ou remonta) o conteúdo da definição a partir das escolhas
        def fill(defn, s)
          tree = S.build(s)
          defn.entities.clear!
          write_attrs(defn, tree, root: true)
          H.mark(defn, 'cabinet', 'tipo' => s[:tipo])
          tree.children.each { |c| build_child(defn.entities, c) }
          tree
        end

        def build_child(ents, e)
          defs = H.model.definitions
          d = defs.add(defs.unique_name(e.name))
          if e.leaf?
            f = d.entities.add_face([0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0])
            f.reverse! if f.normal.z < 0
            f.pushpull(1)
          end
          inst = ents.add_instance(d, transform_of(e))
          inst.name = e.name
          write_attrs(d, e)
          inst.hidden = e.hidden?
          if e.leaf?
            mat_name = e.attrs.key?('material') ? e.get('material') : e.meta[:fixed_mat]
            mat = mat_name && H.model.materials[mat_name.to_s]
            inst.material = mat if mat
            H.mark(inst, 'part', 'part' => e.name, 'mk' => e.meta[:part])
          end
          e.children.each { |c| build_child(d.entities, c) }
          inst
        end

        # Posição (e tamanho, nas peças) já calculados, em polegadas
        def transform_of(e)
          t = Geom::Transformation.new([e.num('x').cm, e.num('y').cm, e.num('z').cm])
          return t unless e.leaf?
          sx, sy, sz = %w[lenx leny lenz].map { |k| [e.num(k), 0.05].max.cm.to_f }
          t * Geom::Transformation.scaling(sx, sy, sz)
        end

        # Grava os atributos no padrão do componente dinâmico
        def write_attrs(target, e, root: false)
          target.set_attribute(DA, '_formatversion', 1.0)
          target.set_attribute(DA, '_has_movetool_behaviors', 0.0)
          target.set_attribute(DA, '_hasbehaviors', 1.0)
          target.set_attribute(DA, '_lengthunits', 'CENTIMETERS')
          target.set_attribute(DA, '_name', e.name)
          target.set_attribute(DA, '_name_label', 'Name')
          e.attrs.each_value do |a|
            k = a.name
            if BUILTIN.key?(k)
              target.set_attribute(DA, "_#{k}_label", BUILTIN[k])
              target.set_attribute(DA, "_#{k}_formula", a.formula) if a.formula
              if %w[lenx leny lenz].include?(k) && a.access != 'NONE'
                target.set_attribute(DA, "_#{k}_access", a.access)
                target.set_attribute(DA, "_#{k}_formlabel", a.label) if a.label
                target.set_attribute(DA, "_#{k}_units", 'CENTIMETERS')
              end
              target.set_attribute(DA, k, stored(e, a))
            else
              target.set_attribute(DA, "_#{k}_label", k)
              target.set_attribute(DA, "_#{k}_access", a.access)
              target.set_attribute(DA, "_#{k}_formlabel", a.label) if a.label
              target.set_attribute(DA, "_#{k}_units", unit_of(a))
              target.set_attribute(DA, "_#{k}_formulaunits", a.kind == :len ? 'CENTIMETERS' : a.kind == :str ? 'STRING' : 'FLOAT')
              target.set_attribute(DA, "_#{k}_options", a.options || '&')
              target.set_attribute(DA, "_#{k}_formula", a.formula) if a.formula
              target.set_attribute(DA, k, stored(e, a).to_s)
            end
          end
          if e.meta[:onclick]
            target.set_attribute(DA, '_onclick_label', 'onClick')
            target.set_attribute(DA, '_onclick_formula', e.meta[:onclick])
            target.set_attribute(DA, 'onclick', e.meta[:onclick])
          end
          return unless root
          %w[lenx leny lenz].each { |k| target.set_attribute(DA, "_#{k}_nominal", stored(e, e.attrs[k])) }
        end

        def unit_of(a)
          return 'CENTIMETERS' if a.kind == :len
          return 'STRING' if a.kind == :str
          'FLOAT'
        end

        # Valor guardado: comprimentos em polegadas (como o SketchUp guarda)
        def stored(e, a)
          v = e.get(a.name)
          return v.to_s if a.kind == :str
          return v.to_f / 2.54 if a.kind == :len
          a.kind == :int ? v.to_i : v.to_f
        end

        def copy_root_values(defn, inst)
          dict = defn.attribute_dictionary(DA)
          dict.each_pair { |k, v| inst.set_attribute(DA, k, v) unless k.start_with?('_') } if dict
          H.mark(inst, 'cabinet', 'tipo' => defn.get_attribute(H::DICT, 'tipo'))
        end

        # ---- ler / atualizar ------------------------------------------------------
        def cabinets
          H.selection.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) && H.kind_of(e.definition) == 'cabinet' }
        end

        # Valores atuais do módulo (cm), lidos da instância
        def current(inst)
          vals = { 'tipo' => inst.definition.get_attribute(H::DICT, 'tipo') }
          USER_KEYS.each do |k, a|
            v = inst.get_attribute(DA, a) || inst.definition.get_attribute(DA, a)
            next if v.nil?
            vals[k] = if LEN_KEYS.include?(a) then (v.to_f * 2.54).round(2)
                      elsif %w[matfrente matcaixa mattampo].include?(a) then v.to_s
                      else v.to_f.round
                      end
          end
          # se a Escala comum foi usada, o tamanho está na transformação
          t = inst.transformation
          { 'lx' => [1, 0, 0], 'ly' => [0, 1, 0], 'lz' => [0, 0, 1] }.each do |k, vec|
            f = Geom::Vector3d.new(*vec).transform(t).length.to_f
            vals[k] = (vals[k].to_f * f).round(2) if vals[k] && (f - 1).abs > 1e-4
          end
          vals
        end

        def read_selected
          inst = cabinets.first
          return H.err('Selecione um módulo de marcenaria do Planê.') unless inst
          H.ok('Valores do módulo carregados no painel.', values: current(inst))
        end

        def update_selected(p)
          insts = cabinets
          return H.err('Selecione um ou mais módulos de marcenaria do Planê.') if insts.empty?
          given = p.reject { |_k, v| v.nil? || v.to_s.empty? }
          H.operation('Planê · Atualizar módulo') do
            ensure_materials
            insts.each do |inst|
              vals = current(inst).merge(given)
              inst.make_unique if inst.definition.instances.size > 1
              t = inst.transformation
              xa = t.xaxis
              ya = t.yaxis
              za = t.zaxis
              inst.transformation = Geom::Transformation.axes(t.origin, xa, ya, za)
              fill(inst.definition, settings(vals))
              copy_root_values(inst.definition, inst)
            end
          end
          H.ok("#{insts.size} módulo(s) atualizado(s).")
        end

        # Redesenho pelo próprio SketchUp (para testar o bloco dinâmico)
        def dc_redraw
          insts = cabinets
          return H.err('Selecione um módulo.') if insts.empty?
          unless defined?($dc_observers) && $dc_observers
            return H.err('Ative a extensão "Componentes dinâmicos" em Janela › Gerenciador de extensões.')
          end
          insts.each { |i| $dc_observers.get_latest_class.redraw_with_undo(i) }
          H.ok('Redesenhado pelo SketchUp. Se as peças saírem do lugar, desfaça (Ctrl+Z) e me mande o Diagnóstico.')
        end

        # Relatório em texto do bloco selecionado (para mandar ao suporte)
        def diagnose
          inst = H.selection.to_a.find { |e| e.is_a?(Sketchup::ComponentInstance) }
          return H.err('Selecione o módulo.') unless inst
          path = UI.savepanel('Salvar diagnóstico', '', 'diagnostico_plane.txt')
          return H.ok('Cancelado.') unless path
          lines = ["Planê Plugin #{VERSION} · SketchUp #{Sketchup.version} · #{Time.now}",
                   "Componentes dinâmicos: #{defined?($dc_observers) && $dc_observers ? 'ativo' : 'INATIVO'}", '']
          dump(inst, 0, lines)
          File.write(path, lines.join("\n"), encoding: 'UTF-8')
          H.ok("Diagnóstico salvo em #{path}. Me mande esse arquivo.")
        end

        def dump(inst, depth, lines)
          t = inst.transformation
          o = t.origin
          sc = [[1, 0, 0], [0, 1, 0], [0, 0, 1]].map { |v| Geom::Vector3d.new(*v).transform(t).length.to_f }
          pad = '  ' * depth
          lines << format('%s- %s  origem=(%.2f, %.2f, %.2f) cm  escala=(%.3f, %.3f, %.3f)%s',
                          pad, inst.name.to_s.empty? ? inst.definition.name : inst.name,
                          o.x.to_f * 2.54, o.y.to_f * 2.54, o.z.to_f * 2.54, *sc, inst.hidden? ? '  [oculto]' : '')
          [inst, inst.definition].each_with_index do |ent, i|
            dict = ent.attribute_dictionary(DA)
            next unless dict
            dict.each_pair do |k, v|
              next if k.start_with?('_inst') || k =~ /_(access|formlabel|options|label|units|formulaunits|error|lastmodified)\z/
              lines << "#{pad}    #{i.zero? ? 'inst' : 'def '} #{k} = #{v.inspect}"
            end
          end
          inst.definition.entities.grep(Sketchup::ComponentInstance).each { |c| dump(c, depth + 1, lines) }
        end

        # ---- distribuir e biblioteca -------------------------------------------
        def distribute(p)
          edge = H.selection.grep(Sketchup::Edge).max_by(&:length)
          return H.err('Selecione uma linha no chão, junto à parede, com o comprimento a ocupar.') unless edge
          a = edge.start.position
          b = edge.end.position
          total = a.distance(b).to_f * 2.54
          n = [(total / H.num(p['maxw'], 80)).ceil, 1].max
          w = total / n
          dir = b - a
          dir.normalize!
          side = Z_AXIS.cross(dir)
          side.reverse! if p['lado'] == 'direita'
          depth = settings(p)[:ly].cm
          first = nil
          n.times do |i|
            origin = a.clone
            if i > 0
              off = dir.clone
              off.length = (i * w).cm
              origin = a.offset(off)
            end
            back = side.clone
            back.length = depth
            origin = origin.offset(back.reverse)
            rot = Geom::Transformation.axes(ORIGIN, dir, side, Z_AXIS)
            if first
              inst = H.model.active_entities.add_instance(first.definition, Geom::Transformation.new(origin) * rot)
              copy_root_values(first.definition, inst)
              inst.layer = first.layer
            else
              first = create(p.merge('lx' => w), origin, rot)
            end
          end
          H.ok("#{n} módulos de #{H.br(w, 1)} cm distribuídos em #{H.br(total / 100.0)} m.")
        end

        def save_library(p)
          dir = UI.select_directory(title: 'Pasta para salvar a biblioteca de blocos')
          return H.ok('Cancelado.') unless dir
          x = 0.0
          saved = 0
          LIBRARY.each do |nome, tipo, over|
            t = S::TIPOS[tipo]
            q = p.merge('tipo' => tipo)
            %i[lx ly lz rod tampo frente nportas ngav prat].each { |k| q[k.to_s] = t[k] }
            q.merge!(over)
            inst = create(q, Geom::Point3d.new(x.cm, -150.cm, 0))
            inst.definition.name = H.model.definitions.unique_name("Planê · #{nome}")
            file = File.join(dir, "Plane - #{nome.tr('·', '-').gsub(/[^\w\- ]/, '').squeeze(' ').strip}.skp")
            saved += 1 if inst.definition.save_as(file)
            x += H.num(q['lx'], 60) + 20
          end
          H.ok("#{saved} blocos salvos em #{dir}. Eles também ficaram no modelo, numa fila atrás da origem.")
        end

        Registry.register(:joinery, name: 'Marcenaria dinâmica', tab: :marc, package: :marc, handler: self,
                                    desc: 'Módulos em componente dinâmico: estica com a Escala sem deformar, abre com Interagir.',
                                    steps: ['Escolha o tipo e as medidas', 'Escolha acabamentos', 'Clique para inserir'])
      end
    end
  end
end
