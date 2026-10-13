# Marcenaria em COMPONENTE DINÂMICO nativo do SketchUp
#
# - Estica com a ferramenta Escala (laterais, portas, gavetas e prateleiras se reajustam)
# - Edita em Janela › Opções do componente (frente, portas, gavetas, puxador, acabamentos…)
# - Portas abrem e gavetas deslizam com a ferramenta Interagir
# - Funciona sem o plugin (precisa só da extensão "Componentes dinâmicos", que vem com o SketchUp)
#
# Unidades: _lengthunits = CENTIMETERS. Fórmulas escritas em cm; valores guardados em polegadas.
# Estrutura: raiz (sem geometria) → peças-folha (cubo de 1" escalado por LenX/LenY/LenZ)
#            e agrupadores (porta, basculante, gaveta) com a animação.

module Plane
  module Plugin
    module Tools
      module Joinery
        extend self
        H = Helpers
        DA = 'dynamic_attributes'.freeze

        FRENTES = [['Portas', 1], ['Gaveta + portas', 2], ['Gavetas', 3], ['Aberto (nicho)', 4], ['Basculante', 5]].freeze
        PUXADORES = [['Perfil', 1], ['Barra', 2], ['Cava', 3], ['Toque (sem puxador)', 4]].freeze

        MAT_FRENTE = [
          ['Branco TX', 'PLN_Branco', 'F4F4F2'], ['Off-white', 'PLN_Offwhite', 'EEE8DE'],
          ['Areia', 'PLN_Areia', 'D9CBB5'], ['Rosa seco', 'PLN_RosaSeco', 'D8B4B0'],
          ['Lilás', 'PLN_Lilas', 'BBA9D6'], ['Cinza', 'PLN_Cinza', 'A7A9AC'],
          ['Grafite', 'PLN_Grafite', '4A4E54'], ['Preto', 'PLN_Preto', '1F1F21'],
          ['Freijó', 'PLN_Freijo', 'A97E55'], ['Carvalho', 'PLN_Carvalho', 'C29B6C'],
          ['Nogueira', 'PLN_Nogueira', '6E4B35'], ['Verde oliva', 'PLN_Oliva', '7C7D5B']
        ].freeze
        MAT_TAMPO = [
          ['Quartzo branco', 'PLN_QuartzoBranco', 'F1EFEB'], ['Granito preto', 'PLN_GranitoPreto', '232325'],
          ['Mármore', 'PLN_Marmore', 'E9E6E1'], ['Madeira', 'PLN_TampoMadeira', 'A97E55'],
          ['Cimento queimado', 'PLN_Cimento', '9C9A96'], ['MDF igual à frente', 'PLN_Branco', 'F4F4F2']
        ].freeze

        TIPOS = {
          'inferior'   => { nome: 'Inferior',   lx: 60, ly: 58, lz: 90,  rod: 10, tampo: 1, frente: 2, nportas: 1, ngav: 3, prat: 1, pz: 0.85 },
          'aereo'      => { nome: 'Aéreo',      lx: 80, ly: 35, lz: 70,  rod: 0,  tampo: 0, frente: 1, nportas: 2, ngav: 3, prat: 1, pz: 0.12 },
          'torre'      => { nome: 'Torre',      lx: 60, ly: 58, lz: 220, rod: 10, tampo: 0, frente: 1, nportas: 1, ngav: 3, prat: 4, pz: 0.5 },
          'gaveteiro'  => { nome: 'Gaveteiro',  lx: 45, ly: 58, lz: 90,  rod: 10, tampo: 1, frente: 3, nportas: 1, ngav: 4, prat: 0, pz: 0.85 },
          'nicho'      => { nome: 'Nicho',      lx: 60, ly: 30, lz: 40,  rod: 0,  tampo: 0, frente: 4, nportas: 1, ngav: 1, prat: 1, pz: 0.5 },
          'basculante' => { nome: 'Basculante', lx: 80, ly: 35, lz: 40,  rod: 0,  tampo: 0, frente: 5, nportas: 1, ngav: 1, prat: 0, pz: 0.15 }
        }.freeze

        LIBRARY = [
          ['Inferior 40 · 1 porta',      'inferior',   { 'lx' => 40, 'frente' => 1 }],
          ['Inferior 80 · 2 portas',     'inferior',   { 'lx' => 80, 'frente' => 1, 'nportas' => 2 }],
          ['Inferior 60 · gaveta+porta', 'inferior',   { 'lx' => 60, 'frente' => 2 }],
          ['Gaveteiro 45 · 4 gavetas',   'gaveteiro',  {}],
          ['Aéreo 40 · 1 porta',         'aereo',      { 'lx' => 40, 'nportas' => 1 }],
          ['Aéreo 80 · 2 portas',        'aereo',      {}],
          ['Aéreo 80 · basculante',      'basculante', {}],
          ['Torre 60 · forno',           'torre',      {}],
          ['Nicho 60',                   'nicho',      {}]
        ].freeze

        # ---------------------------------------------------------------------
        def handle(action, p)
          case action
          when 'insert'
            return dc_missing unless dc?
            Sketchup.active_model.select_tool(
              Pickers::PointPicker.new('Marcenaria: clique onde fica o canto frontal esquerdo do módulo', single: true) do |pts, _c|
                begin
                  inst = create(p, pts[0])
                  Dialog.push('result', tool: 'joinery', ok: true, msg: "#{inst.definition.name} inserido. Estique com a Escala ou edite em Janela › Opções do componente.")
                rescue StandardError => e
                  Dialog.push('result', tool: 'joinery', ok: false, msg: e.message)
                end
              end
            )
            H.ok('Clique no modelo onde fica o canto frontal esquerdo do módulo.', picking: true)
          when 'distribute'
            return dc_missing unless dc?
            distribute(p)
          when 'read'
            read_selected
          when 'update'
            return dc_missing unless dc?
            update_selected(p)
          when 'library'
            return dc_missing unless dc?
            save_library(p)
          when 'toggle'
            toggle_open
          else
            H.err('Ação desconhecida.')
          end
        end

        def dc?
          defined?($dc_observers) && $dc_observers && $dc_observers.respond_to?(:get_latest_class)
        end

        def dc_missing
          H.err('Ative a extensão "Componentes dinâmicos" em Janela › Gerenciador de extensões e tente de novo.')
        end

        def redraw(inst)
          $dc_observers.get_latest_class.redraw_with_undo(inst)
        end

        # ---- valores do painel → valores do componente ------------------------
        def settings(p)
          t = TIPOS[p['tipo']] || TIPOS['inferior']
          {
            tipo: p['tipo'] || 'inferior',
            nome: t[:nome],
            lx: H.num(p['lx'], t[:lx]), ly: H.num(p['ly'], t[:ly]), lz: H.num(p['lz'], t[:lz]),
            frente: H.num(p['frente'], t[:frente]).to_i, nportas: H.num(p['nportas'], t[:nportas]).to_i,
            ngav: H.num(p['ngav'], t[:ngav]).to_i, hgav: H.num(p['hgav'], 18), prat: H.num(p['prat'], t[:prat]).to_i,
            puxador: H.num(p['puxador'], 1).to_i,
            matfrente: p['matfrente'] || 'PLN_Branco', matcaixa: p['matcaixa'] || 'PLN_Branco',
            tampo: H.num(p['tampo'], t[:tampo]).to_i, mattampo: p['mattampo'] || 'PLN_QuartzoBranco',
            esptampo: H.num(p['esptampo'], 2), esp: H.num(p['esp'], 1.5), espf: H.num(p['espf'], 1.8),
            fundo: H.num(p['fundo'], 0.6), folga: H.num(p['folga'], 0.3),
            rod: H.num(p['rod'], t[:rod]), rodrec: H.num(p['rodrec'], 5), pz: t[:pz]
          }
        end

        def ensure_materials
          (MAT_FRENTE + MAT_TAMPO).each { |_l, n, hex| H.material(n, hex) }
          H.material('PLN_Aluminio', 'C8CACC')
          H.material('PLN_Cava', '2F3A45')
        end

        # ---- criação -----------------------------------------------------------
        def create(p, at = ORIGIN, rot = nil)
          s = settings(p)
          inst = nil
          H.operation('Planê · Marcenaria') do
            ensure_materials
            defn = build_definition(s)
            tr = Geom::Transformation.new(at)
            tr = tr * rot if rot
            inst = H.model.active_entities.add_instance(defn, tr)
            copy_values(defn, inst)
            inst.layer = H.tag('Planê · Marcenaria')
          end
          redraw(inst)
          inst
        end

        def build_definition(s)
          defs = H.model.definitions
          name = "Planê #{s[:nome]} #{s[:lx].round}x#{s[:lz].round}"
          defn = defs.add(defs.unique_name(name))
          defn.description = "Módulo de marcenaria #{s[:nome].downcase} · Planê Plugin"
          defn.behavior.no_scale_mask = 0 if defn.behavior.respond_to?(:no_scale_mask=)
          root(defn, s)
          H.mark(defn, 'cabinet', 'tipo' => s[:tipo])
          ents = defn.entities
          box(ents)
          fronts(ents)
          drawers(ents)
          defn
        end

        def copy_values(defn, inst)
          dict = defn.attribute_dictionary(DA)
          return unless dict
          dict.each_pair { |k, v| inst.set_attribute(DA, k, v) unless k.start_with?('_') }
          H.mark(inst, 'cabinet', 'tipo' => defn.get_attribute(H::DICT, 'tipo'))
        end

        # ---- atributos dinâmicos ---------------------------------------------
        def init_dc(ent, name)
          targets(ent).each do |t|
            t.set_attribute(DA, '_formatversion', 1.0)
            t.set_attribute(DA, '_has_movetool_behaviors', 0.0)
            t.set_attribute(DA, '_hasbehaviors', 1.0)
            t.set_attribute(DA, '_lengthunits', 'CENTIMETERS')
            t.set_attribute(DA, '_name', name)
          end
          ent.name = name if ent.respond_to?(:name=) && !ent.is_a?(Sketchup::ComponentDefinition)
        end

        def targets(ent)
          if ent.is_a?(Sketchup::Group) then [ent, ent.definition]
          else [ent]
          end
        end

        # Escreve um atributo dinâmico.
        # kind: :len (cm), :int, :float, :str
        def da(ent, name, value: nil, formula: nil, kind: :len, access: 'NONE', label: nil, options: nil)
          units, fu = case kind
                      when :len then %w[CENTIMETERS CENTIMETERS]
                      when :str then %w[STRING STRING]
                      when :int then %w[INTEGER FLOAT]
                      else %w[FLOAT FLOAT]
                      end
          v = value
          v = value.to_f / 2.54 if kind == :len && value
          v = value.to_i if kind == :int && value
          targets(ent).each do |t|
            t.set_attribute(DA, name, v) unless v.nil?
            t.set_attribute(DA, "_#{name}_label", name)
            t.set_attribute(DA, "_#{name}_access", access)
            t.set_attribute(DA, "_#{name}_units", units)
            t.set_attribute(DA, "_#{name}_formulaunits", fu)
            t.set_attribute(DA, "_#{name}_formlabel", label) if label
            t.set_attribute(DA, "_#{name}_options", options) if options
            t.set_attribute(DA, "_#{name}_formula", formula) if formula
          end
        end

        def enc(text)
          text.to_s.bytes.map { |b| b.chr =~ /[A-Za-z0-9_.-]/ ? b.chr : format('%%%02X', b) }.join
        end

        def opts(list)
          '&' + list.map { |label, val| "#{enc(label)}=#{enc(val)}" }.join('&') + '&'
        end

        # ---- raiz ---------------------------------------------------------------
        def root(defn, s)
          init_dc(defn, 'Planê Marcenaria')
          da(defn, 'lenx', value: s[:lx], access: 'TEXTBOX', label: 'Largura')
          da(defn, 'leny', value: s[:ly], access: 'TEXTBOX', label: 'Profundidade')
          da(defn, 'lenz', value: s[:lz], access: 'TEXTBOX', label: 'Altura')
          da(defn, 'frente', value: s[:frente], kind: :int, access: 'LIST', label: 'Frente', options: opts(FRENTES))
          da(defn, 'nportas', value: s[:nportas], kind: :int, access: 'LIST', label: 'Portas', options: opts([['1 porta', 1], ['2 portas', 2]]))
          da(defn, 'ngav', value: s[:ngav], kind: :int, access: 'LIST', label: 'Gavetas', options: opts((1..6).map { |i| ["#{i} gaveta#{i > 1 ? 's' : ''}", i] }))
          da(defn, 'hgav', value: s[:hgav], access: 'TEXTBOX', label: 'Altura da gaveta de cima')
          da(defn, 'prat', value: s[:prat], kind: :int, access: 'LIST', label: 'Prateleiras', options: opts((0..6).map { |i| [i.zero? ? 'Nenhuma' : i.to_s, i] }))
          da(defn, 'puxador', value: s[:puxador], kind: :int, access: 'LIST', label: 'Puxador', options: opts(PUXADORES))
          da(defn, 'matfrente', value: s[:matfrente], kind: :str, access: 'LIST', label: 'Acabamento das frentes', options: opts(MAT_FRENTE.map { |l, n, _| [l, n] }))
          da(defn, 'matcaixa', value: s[:matcaixa], kind: :str, access: 'LIST', label: 'Cor da caixa', options: opts(MAT_FRENTE.map { |l, n, _| [l, n] }))
          da(defn, 'tampo', value: s[:tampo], kind: :int, access: 'LIST', label: 'Tampo', options: opts([['Sem tampo', 0], ['Com tampo', 1]]))
          da(defn, 'mattampo', value: s[:mattampo], kind: :str, access: 'LIST', label: 'Material do tampo', options: opts(MAT_TAMPO.map { |l, n, _| [l, n] }))
          da(defn, 'esptampo', value: s[:esptampo], access: 'TEXTBOX', label: 'Espessura do tampo')
          da(defn, 'esp', value: s[:esp], access: 'TEXTBOX', label: 'MDF da caixa')
          da(defn, 'espf', value: s[:espf], access: 'TEXTBOX', label: 'MDF das frentes')
          da(defn, 'fundo', value: s[:fundo], access: 'TEXTBOX', label: 'Espessura do fundo')
          da(defn, 'folga', value: s[:folga], access: 'TEXTBOX', label: 'Folga entre frentes')
          da(defn, 'rod', value: s[:rod], access: 'TEXTBOX', label: 'Altura do rodapé')
          da(defn, 'rodrec', value: s[:rodrec], access: 'TEXTBOX', label: 'Recuo do rodapé')
          da(defn, 'pz', value: s[:pz], kind: :float)
          da(defn, 'tampovis', value: 1, kind: :float)
          # valores calculados (escondidos)
          {
            'hc' => 'LenZ-rod-tampo*esptampo',
            'pc' => 'LenY-espf',
            'vx' => 'LenX-2*esp',
            'hp' => 'IF(frente=2,hc-hgav,hc)',
            'wp' => 'IF(nportas=2,LenX/2,LenX)',
            'hg' => 'IF(frente=3,hc/ngav,hgav)',
            'zg0' => 'IF(frente=3,rod,rod+hc-hgav)',
            'hint' => 'hc-2*esp-IF(frente=2,hgav,0)'
          }.each { |k, f| da(defn, k, value: 0, formula: f) }
          da(defn, 'ng', value: 0, kind: :float, formula: 'IF(frente=3,ngav,IF(frente=2,1,0))')
          da(defn, 'temporta', value: 0, kind: :float, formula: 'IF(OR(frente=1,frente=2),1,0)')
          defn.set_attribute(DA, 'scaletool', 120.0)
          defn.set_attribute(DA, '_scaletool_formlabel', 'Escala')
          defn.set_attribute(DA, '_scaletool_access', 'NONE')
        end

        # ---- peças ---------------------------------------------------------------
        # Peça-folha: cubo de 1" que o componente dinâmico escala
        def leaf(ents, name, x:, y:, z:, lx:, ly:, lz:, mat: nil, hidden: nil, copies: nil, part: 'caixa', fixed_mat: nil)
          g = ents.add_group
          f = g.entities.add_face([0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0])
          f.reverse! if f.normal.z < 0
          f.pushpull(1)
          init_dc(g, name)
          { 'x' => x, 'y' => y, 'z' => z, 'lenx' => lx, 'leny' => ly, 'lenz' => lz }.each do |k, fm|
            da(g, k, value: 0, formula: fm.to_s)
          end
          da(g, 'material', value: '', kind: :str, formula: mat) if mat
          g.material = H.model.materials[fixed_mat] if fixed_mat
          da(g, 'hidden', value: 0, kind: :float, formula: hidden) if hidden
          da(g, 'copies', value: 0, kind: :float, formula: copies) if copies
          H.mark(g, 'part', 'part' => name, 'mk' => part)
          g
        end

        # Agrupador (porta, basculante, gaveta): sem geometria própria
        def node(ents, name, x:, y:, z:, pass: {}, hidden: nil, onclick: nil, copies: nil, y_formula: true)
          g = ents.add_group
          init_dc(g, name)
          da(g, 'x', value: 0, formula: x.to_s)
          da(g, 'y', value: 0, formula: (y_formula ? y.to_s : nil))
          da(g, 'z', value: 0, formula: z.to_s)
          da(g, 'rotx', value: 0, kind: :float)
          da(g, 'rotz', value: 0, kind: :float)
          pass.each do |k, (fm, kind)|
            da(g, k, value: (kind == :str ? '' : 0), kind: kind || :len, formula: fm)
          end
          da(g, 'hidden', value: 0, kind: :float, formula: hidden) if hidden
          da(g, 'copies', value: 0, kind: :float, formula: copies) if copies
          if onclick
            targets(g).each do |t|
              t.set_attribute(DA, 'onclick', onclick)
              t.set_attribute(DA, '_onclick_label', 'onClick')
              t.set_attribute(DA, '_onclick_formula', onclick)
              t.set_attribute(DA, '_onclick_access', 'NONE')
            end
          end
          g
        end

        def box(e)
          cm = 'Parent!matcaixa'
          leaf(e, 'Lateral esquerda', x: 0, y: 'Parent!espf', z: 'Parent!rod', lx: 'Parent!esp', ly: 'Parent!pc', lz: 'Parent!hc', mat: cm)
          leaf(e, 'Lateral direita', x: 'Parent!LenX-Parent!esp', y: 'Parent!espf', z: 'Parent!rod', lx: 'Parent!esp', ly: 'Parent!pc', lz: 'Parent!hc', mat: cm)
          leaf(e, 'Base', x: 'Parent!esp', y: 'Parent!espf', z: 'Parent!rod', lx: 'Parent!vx', ly: 'Parent!pc-Parent!fundo', lz: 'Parent!esp', mat: cm)
          leaf(e, 'Travessa superior', x: 'Parent!esp', y: 'Parent!espf', z: 'Parent!rod+Parent!hc-Parent!esp', lx: 'Parent!vx', ly: 'Parent!pc-Parent!fundo', lz: 'Parent!esp', mat: cm)
          leaf(e, 'Fundo', x: 'Parent!esp', y: 'Parent!LenY-Parent!fundo', z: 'Parent!rod+Parent!esp', lx: 'Parent!vx', ly: 'Parent!fundo', lz: 'Parent!hc-2*Parent!esp', mat: cm, part: 'fundo')
          leaf(e, 'Rodapé', x: 'Parent!esp', y: 'Parent!espf+Parent!rodrec', z: 0, lx: 'Parent!vx', ly: 'Parent!esp', lz: 'MAX(Parent!rod,0.1)', mat: cm, hidden: 'IF(Parent!rod<=0,1,0)')
          leaf(e, 'Prateleira', x: 'Parent!esp', y: 'Parent!espf+2', z: 'Parent!rod+Parent!esp+(COPY+1)*Parent!hint/(Parent!prat+1)-Parent!esp/2',
                                lx: 'Parent!vx', ly: 'Parent!pc-Parent!fundo-2', lz: 'Parent!esp', mat: cm,
                                hidden: 'IF(Parent!prat<1,1,0)', copies: 'MAX(Parent!prat-1,0)')
          leaf(e, 'Tampo', x: 0, y: 0, z: 'Parent!LenZ-Parent!esptampo', lx: 'Parent!LenX', ly: 'Parent!LenY', lz: 'MAX(Parent!esptampo,0.1)',
                           mat: 'Parent!mattampo', hidden: 'IF(AND(Parent!tampo=1,Parent!tampovis=1),0,1)', part: 'tampo')
        end

        def handles(e, side, vertical: true)
          # side: posição X da barra dentro do agrupador; vertical = barra em pé (portas)
          lx, lz = vertical ? [1.2, 16] : [16, 1.2]
          leaf(e, 'Puxador barra', x: side, y: '-Parent!ef-2.5', z: vertical ? 'MAX(Parent!hf*Parent!pz-8,1)' : 'Parent!hy',
                                   lx: lx, ly: 2.5, lz: lz, hidden: 'IF(Parent!px=2,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
          leaf(e, 'Puxador perfil', x: 0, y: '-Parent!ef-1', z: 'Parent!py', lx: 'Parent!lf', ly: 1, lz: 3,
                                    hidden: 'IF(Parent!px=1,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
          leaf(e, 'Cava', x: 0, y: '-Parent!ef-0.05', z: 'Parent!py', lx: 'Parent!lf', ly: 0.05, lz: 2.5,
                          hidden: 'IF(Parent!px=3,0,1)', part: 'acabamento', fixed_mat: 'PLN_Cava')
        end

        def door_pass(width_formula, height_formula)
          {
            'lf' => [width_formula], 'hf' => [height_formula], 'ef' => ['Parent!espf'],
            'mf' => ['Parent!matfrente', :str], 'px' => ['Parent!puxador', :float], 'pz' => ['Parent!pz', :float],
            'py' => ['IF(Parent!pz>0.5,Parent!hp-Parent!folga-3,0)']
          }
        end

        def fronts(e)
          show = 'IF(Parent!temporta=1,0,1)'
          left = node(e, 'Porta esquerda', x: 'Parent!folga/2', y: 'Parent!espf', z: 'Parent!rod+Parent!folga/2',
                                           pass: door_pass('Parent!wp-Parent!folga', 'Parent!hp-Parent!folga'),
                                           hidden: show, onclick: 'ANIMATE("rotz",0,-95)')
          leaf(left.entities, 'Porta', x: 0, y: '-Parent!ef', z: 0, lx: 'Parent!lf', ly: 'Parent!ef', lz: 'Parent!hf', mat: 'Parent!mf', part: 'porta')
          handles(left.entities, 'Parent!lf-4')

          right = node(e, 'Porta direita', x: 'Parent!LenX-Parent!folga/2', y: 'Parent!espf', z: 'Parent!rod+Parent!folga/2',
                                           pass: door_pass('Parent!wp-Parent!folga', 'Parent!hp-Parent!folga'),
                                           hidden: 'IF(AND(Parent!temporta=1,Parent!nportas=2),0,1)', onclick: 'ANIMATE("rotz",0,95)')
          leaf(right.entities, 'Porta', x: '-Parent!lf', y: '-Parent!ef', z: 0, lx: 'Parent!lf', ly: 'Parent!ef', lz: 'Parent!hf', mat: 'Parent!mf', part: 'porta')
          handles(right.entities, '-Parent!lf+2.8')
          # na porta direita o perfil e a cava começam em -lf
          right.entities.to_a.each do |g|
            next unless g.respond_to?(:name) && ['Puxador perfil', 'Cava'].include?(g.name)
            da(g, 'x', value: 0, formula: '-Parent!lf')
          end

          pass = door_pass('Parent!LenX-Parent!folga', 'Parent!hc-Parent!folga')
          pass['py'] = ['-hf']
          pass['hy'] = ['-hf+3']
          bas = node(e, 'Basculante', x: 'Parent!folga/2', y: 'Parent!espf', z: 'Parent!rod+Parent!hc-Parent!folga/2',
                                      pass: pass, hidden: 'IF(Parent!frente=5,0,1)', onclick: 'ANIMATE("rotx",0,-80)')
          leaf(bas.entities, 'Porta basculante', x: 0, y: '-Parent!ef', z: '-Parent!hf', lx: 'Parent!lf', ly: 'Parent!ef', lz: 'Parent!hf', mat: 'Parent!mf', part: 'porta')
          handles(bas.entities, 'Parent!lf/2-8', vertical: false)
        end

        def drawers(e)
          slot = node(e, 'Gaveta', x: 0, y: 0, z: 'Parent!zg0+COPY*Parent!hg',
                                   pass: {
                                     'w' => ['Parent!LenX'], 'h' => ['Parent!hg'], 'f' => ['Parent!folga'], 'ef' => ['Parent!espf'],
                                     'mf' => ['Parent!matfrente', :str], 'mc' => ['Parent!matcaixa', :str],
                                     'pc' => ['Parent!pc'], 'e' => ['Parent!esp'], 'vx' => ['Parent!vx'],
                                     'px' => ['Parent!puxador', :float], 'fd' => ['Parent!fundo']
                                   },
                                   hidden: 'IF(Parent!ng=0,1,0)', copies: 'MAX(Parent!ng-1,0)')
          body = node(slot.entities, 'Corpo da gaveta', x: 0, y: 0, z: 0, y_formula: false,
                                                        pass: {
                                                          'w' => ['Parent!w'], 'h' => ['Parent!h'], 'f' => ['Parent!f'], 'ef' => ['Parent!ef'],
                                                          'mf' => ['Parent!mf', :str], 'mc' => ['Parent!mc', :str], 'pc' => ['Parent!pc'],
                                                          'e' => ['Parent!e'], 'vx' => ['Parent!vx'], 'px' => ['Parent!px', :float],
                                                          'fd' => ['Parent!fd'], 'abre' => ['Parent!pc*0.7'],
                                                          'lf' => ['Parent!w-Parent!f'], 'py' => ['Parent!h-Parent!f-3'],
                                                          'hy' => ['Parent!h-7']
                                                        },
                                                        onclick: 'ANIMATE("y",0,-abre)')
          b = body.entities
          leaf(b, 'Frente da gaveta', x: 'Parent!f/2', y: 0, z: 'Parent!f/2', lx: 'Parent!w-Parent!f', ly: 'Parent!ef', lz: 'Parent!h-Parent!f', mat: 'Parent!mf', part: 'frente_gaveta')
          bh = 'MAX(Parent!h-6,6)'
          bd = 'Parent!pc-Parent!fd-3'
          leaf(b, 'Lateral da gaveta', x: 'Parent!e+1.3', y: 'Parent!ef', z: 2.5, lx: 1.5, ly: bd, lz: bh, mat: 'Parent!mc', part: 'gaveta')
          leaf(b, 'Lateral da gaveta', x: 'Parent!w-Parent!e-2.8', y: 'Parent!ef', z: 2.5, lx: 1.5, ly: bd, lz: bh, mat: 'Parent!mc', part: 'gaveta')
          leaf(b, 'Contrafrente', x: 'Parent!e+2.8', y: 'Parent!ef', z: 2.5, lx: 'Parent!vx-5.6', ly: 1.5, lz: bh, mat: 'Parent!mc', part: 'gaveta')
          leaf(b, 'Traseira da gaveta', x: 'Parent!e+2.8', y: "Parent!ef+#{bd}-1.5", z: 2.5, lx: 'Parent!vx-5.6', ly: 1.5, lz: bh, mat: 'Parent!mc', part: 'gaveta')
          leaf(b, 'Fundo da gaveta', x: 'Parent!e+1.3', y: 'Parent!ef', z: 1.9, lx: 'Parent!vx-2.6', ly: bd, lz: 0.6, mat: 'Parent!mc', part: 'fundo')
          leaf(b, 'Puxador barra', x: 'Parent!w/2-8', y: -2.5, z: 'Parent!hy', lx: 16, ly: 2.5, lz: 1.2,
                                   hidden: 'IF(Parent!px=2,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
          leaf(b, 'Puxador perfil', x: 'Parent!f/2', y: -1, z: 'Parent!py', lx: 'Parent!lf', ly: 1, lz: 3,
                                    hidden: 'IF(Parent!px=1,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
          leaf(b, 'Cava', x: 'Parent!f/2', y: -0.05, z: 'Parent!py', lx: 'Parent!lf', ly: 0.05, lz: 2.5,
                          hidden: 'IF(Parent!px=3,0,1)', part: 'acabamento', fixed_mat: 'PLN_Cava')
        end

        # ---- outras ações -------------------------------------------------------
        def selected_cabinet
          H.selection.to_a.find { |e| e.is_a?(Sketchup::ComponentInstance) && H.kind_of(e.definition) == 'cabinet' }
        end

        USER_KEYS = {
          'lx' => ['lenx', :len], 'ly' => ['leny', :len], 'lz' => ['lenz', :len], 'frente' => ['frente', :int],
          'nportas' => ['nportas', :int], 'ngav' => ['ngav', :int], 'hgav' => ['hgav', :len], 'prat' => ['prat', :int],
          'puxador' => ['puxador', :int], 'matfrente' => ['matfrente', :str], 'matcaixa' => ['matcaixa', :str],
          'tampo' => ['tampo', :int], 'mattampo' => ['mattampo', :str], 'esptampo' => ['esptampo', :len],
          'esp' => ['esp', :len], 'espf' => ['espf', :len], 'fundo' => ['fundo', :len], 'folga' => ['folga', :len],
          'rod' => ['rod', :len], 'rodrec' => ['rodrec', :len]
        }.freeze

        def read_selected
          inst = selected_cabinet
          return H.err('Selecione um módulo de marcenaria do Planê.') unless inst
          vals = { 'tipo' => inst.definition.get_attribute(H::DICT, 'tipo') }
          USER_KEYS.each do |k, (a, kind)|
            v = inst.get_attribute(DA, a) || inst.definition.get_attribute(DA, a)
            next if v.nil?
            vals[k] = kind == :len ? (v.to_f * 2.54).round(2) : v
          end
          H.ok('Valores do módulo carregados no painel.', values: vals)
        end

        def update_selected(p)
          insts = H.selection.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) && H.kind_of(e.definition) == 'cabinet' }
          return H.err('Selecione um ou mais módulos de marcenaria do Planê.') if insts.empty?
          H.operation('Planê · Atualizar módulo') do
            ensure_materials
            insts.each do |inst|
              USER_KEYS.each do |k, (a, kind)|
                next if p[k].nil? || p[k].to_s.empty?
                v = case kind
                    when :len then H.num(p[k]) / 2.54
                    when :int then H.num(p[k]).to_i
                    else p[k].to_s
                    end
                inst.set_attribute(DA, a, v)
              end
            end
          end
          insts.each { |i| redraw(i) }
          H.ok("#{insts.size} módulo(s) atualizado(s).")
        end

        # Distribui módulos iguais ao longo de uma linha selecionada (ex.: a parede)
        def distribute(p)
          edge = H.selection.grep(Sketchup::Edge).max_by(&:length)
          return H.err('Selecione uma linha no chão, junto à parede, com o comprimento a ocupar.') unless edge
          a = edge.start.position
          b = edge.end.position
          total = a.distance(b).to_f * 2.54
          maxw = H.num(p['maxw'], 80)
          n = [(total / maxw).ceil, 1].max
          w = total / n
          dir = b - a
          dir.normalize!
          side = Z_AXIS.cross(dir)
          s = settings(p)
          side.reverse! if p['lado'] == 'direita'
          depth = s[:ly].cm
          q = p.merge('lx' => w)
          first = nil
          n.times do |i|
            off = dir.clone
            off.length = (i * w).cm if i > 0
            origin = i.zero? ? a.clone : a.offset(off)
            back = side.clone
            back.length = depth
            origin = origin.offset(back.reverse)
            xa = dir
            ya = side
            rot = Geom::Transformation.axes(ORIGIN, xa, ya, Z_AXIS)
            if first
              inst = H.model.active_entities.add_instance(first.definition, Geom::Transformation.new(origin) * rot)
              copy_values(first.definition, inst)
              inst.layer = first.layer
            else
              first = create(q, origin, rot)
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
            q = p.merge('tipo' => tipo).merge(over)
            TIPOS[tipo].each { |k, v| q[k.to_s] = v if %i[lx ly lz rod tampo frente nportas ngav prat].include?(k) && !over.key?(k.to_s) }
            inst = create(q, Geom::Point3d.new(x.cm, -150.cm, 0))
            inst.definition.name = H.model.definitions.unique_name("Planê · #{nome}")
            file = File.join(dir, "Plane - #{nome.tr('·', '-').gsub(/[^\w\- ]/, '').squeeze(' ').strip}.skp")
            saved += 1 if inst.definition.save_as(file)
            x += H.num(q['lx'], 60) + 20
          end
          H.ok("#{saved} blocos salvos em #{dir}. Eles também ficaram no modelo, numa fila atrás da origem.")
        end

        # Abre/fecha todas as portas e gavetas dos módulos selecionados (para apresentar)
        def toggle_open
          insts = H.selection.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) && H.kind_of(e.definition) == 'cabinet' }
          return H.err('Selecione os módulos para abrir ou fechar.') if insts.empty?
          H.ok('Use a ferramenta Interagir (mãozinha) e clique na porta ou gaveta: ela abre e fecha com animação.')
        end

        Registry.register(:joinery, name: 'Marcenaria dinâmica', tab: :marc, package: :marc, handler: self,
                                    desc: 'Módulos em componente dinâmico: estica com a Escala, abre com Interagir.',
                                    steps: ['Escolha o tipo e as medidas', 'Escolha acabamentos', 'Clique para inserir'])
      end
    end
  end
end
