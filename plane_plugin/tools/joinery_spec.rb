# Receita do módulo de marcenaria (independente do SketchUp).
# Eixos: X = largura (0 à esquerda), Y = profundidade (0 = frente), Z = altura (0 = piso). Medidas em cm.

module Plane
  module Plugin
    module JoinerySpec
      T = DCTree

      FRENTES = [['Portas', 1], ['Gaveta + portas', 2], ['Gavetas', 3], ['Aberto (nicho)', 4], ['Basculante', 5]].freeze
      PUXADORES = [['Perfil', 1], ['Barra', 2], ['Cava', 3], ['Toque (sem puxador)', 4]].freeze
      MAX_GAV = 6
      MAX_PRAT = 6

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
      FIXED = { 'PLN_Aluminio' => 'C8CACC', 'PLN_Cava' => '2F3A45', 'PLN_Ferragem' => '9EA3A8' }.freeze

      TIPOS = {
        'inferior'   => { nome: 'Inferior',   lx: 60, ly: 58, lz: 90,  rod: 10, tampo: 1, frente: 2, nportas: 1, ngav: 3, prat: 1, pz: 0.85 },
        'aereo'      => { nome: 'Aéreo',      lx: 80, ly: 35, lz: 70,  rod: 0,  tampo: 0, frente: 1, nportas: 2, ngav: 3, prat: 1, pz: 0.12 },
        'torre'      => { nome: 'Torre',      lx: 60, ly: 58, lz: 220, rod: 10, tampo: 0, frente: 1, nportas: 1, ngav: 3, prat: 4, pz: 0.5 },
        'gaveteiro'  => { nome: 'Gaveteiro',  lx: 45, ly: 58, lz: 90,  rod: 10, tampo: 1, frente: 3, nportas: 1, ngav: 4, prat: 0, pz: 0.85 },
        'nicho'      => { nome: 'Nicho',      lx: 60, ly: 30, lz: 40,  rod: 0,  tampo: 0, frente: 4, nportas: 1, ngav: 1, prat: 1, pz: 0.5 },
        'basculante' => { nome: 'Basculante', lx: 80, ly: 35, lz: 40,  rod: 0,  tampo: 0, frente: 5, nportas: 1, ngav: 1, prat: 0, pz: 0.15 }
      }.freeze

      module_function

      def enc(text)
        text.to_s.b.each_char.map { |c| c =~ /[A-Za-z0-9_.-]/ ? c : format('%%%02X', c.ord) }.join
      end

      def opts(list)
        '&' + list.map { |label, val| "#{enc(label)}=#{enc(val)}" }.join('&') + '&'
      end

      # s: hash com as escolhas (mesmas chaves do painel); medidas em cm
      def build(s)
        r = T::Ent.new('Planê Marcenaria', :root, tipo: s[:tipo])
        r.set('lenx', s[:lx], access: 'TEXTBOX', label: 'Largura')
        r.set('leny', s[:ly], access: 'TEXTBOX', label: 'Profundidade')
        r.set('lenz', s[:lz], access: 'TEXTBOX', label: 'Altura')
        r.set('frente', s[:frente], kind: :int, access: 'LIST', label: 'Frente', options: opts(FRENTES))
        r.set('nportas', s[:nportas], kind: :int, access: 'LIST', label: 'Portas', options: opts([['1 porta', 1], ['2 portas', 2]]))
        r.set('ngav', s[:ngav], kind: :int, access: 'LIST', label: 'Gavetas', options: opts((1..MAX_GAV).map { |i| ["#{i} gaveta#{i > 1 ? 's' : ''}", i] }))
        r.set('hgav', s[:hgav], access: 'TEXTBOX', label: 'Altura da gaveta de cima')
        r.set('prat', s[:prat], kind: :int, access: 'LIST', label: 'Prateleiras', options: opts((0..MAX_PRAT).map { |i| [i.zero? ? 'Nenhuma' : i.to_s, i] }))
        r.set('puxador', s[:puxador], kind: :int, access: 'LIST', label: 'Puxador', options: opts(PUXADORES))
        r.set('matfrente', s[:matfrente], kind: :str, access: 'LIST', label: 'Acabamento das frentes', options: opts(MAT_FRENTE.map { |l, n, _| [l, n] }))
        r.set('matcaixa', s[:matcaixa], kind: :str, access: 'LIST', label: 'Cor da caixa', options: opts(MAT_FRENTE.map { |l, n, _| [l, n] }))
        r.set('tampo', s[:tampo], kind: :int, access: 'LIST', label: 'Tampo', options: opts([['Sem tampo', 0], ['Com tampo', 1]]))
        r.set('mattampo', s[:mattampo], kind: :str, access: 'LIST', label: 'Material do tampo', options: opts(MAT_TAMPO.map { |l, n, _| [l, n] }))
        r.set('esptampo', s[:esptampo], access: 'TEXTBOX', label: 'Espessura do tampo')
        r.set('esp', s[:esp], access: 'TEXTBOX', label: 'MDF da caixa')
        r.set('espf', s[:espf], access: 'TEXTBOX', label: 'MDF das frentes')
        r.set('fundo', s[:fundo], access: 'TEXTBOX', label: 'Espessura do fundo')
        r.set('folga', s[:folga], access: 'TEXTBOX', label: 'Folga entre frentes')
        r.set('rod', s[:rod], access: 'TEXTBOX', label: 'Altura do rodapé')
        r.set('rodrec', s[:rodrec], access: 'TEXTBOX', label: 'Recuo do rodapé')
        r.set('pz', s[:pz], kind: :float)
        r.set('tampovis', 1, kind: :float)
        {
          'hc' => 'LenZ-rod-tampo*esptampo', 'pc' => 'LenY-espf', 'vx' => 'LenX-2*esp',
          'hp' => 'IF(frente=2,hc-hgav,hc)', 'wp' => 'IF(nportas=2,LenX/2,LenX)',
          'hg' => 'IF(frente=3,hc/ngav,hgav)', 'zg0' => 'IF(frente=3,rod,rod+hc-hgav)',
          'hint' => 'hc-2*esp-IF(frente=2,hgav,0)'
        }.each { |k, f| r.set(k, 0, f: f) }
        r.set('ng', 0, f: 'IF(frente=3,ngav,IF(frente=2,1,0))', kind: :float)
        r.set('temporta', 0, f: 'IF(OR(frente=1,frente=2),1,0)', kind: :float)
        box(r)
        doors(r)
        flap(r)
        MAX_GAV.times { |i| drawer(r, i) }
        r
      end

      def box(r)
        c = 'Parent!matcaixa'
        T.leaf(r, 'Lateral esquerda', x: 0, y: 'Parent!espf', z: 0, lx: 'Parent!esp', ly: 'Parent!pc', lz: 'Parent!rod+Parent!hc', mat: c)
        T.leaf(r, 'Lateral direita', x: 'Parent!LenX-Parent!esp', y: 'Parent!espf', z: 0, lx: 'Parent!esp', ly: 'Parent!pc', lz: 'Parent!rod+Parent!hc', mat: c)
        T.leaf(r, 'Base', x: 'Parent!esp', y: 'Parent!espf', z: 'Parent!rod', lx: 'Parent!vx', ly: 'Parent!pc-Parent!fundo', lz: 'Parent!esp', mat: c)
        T.leaf(r, 'Travessa superior', x: 'Parent!esp', y: 'Parent!espf', z: 'Parent!rod+Parent!hc-Parent!esp', lx: 'Parent!vx', ly: 'Parent!pc-Parent!fundo', lz: 'Parent!esp', mat: c)
        T.leaf(r, 'Fundo', x: 'Parent!esp', y: 'Parent!LenY-Parent!fundo', z: 'Parent!rod+Parent!esp', lx: 'Parent!vx', ly: 'Parent!fundo', lz: 'Parent!hc-2*Parent!esp', mat: c, part: 'fundo')
        T.leaf(r, 'Rodapé', x: 'Parent!esp', y: 'Parent!espf+Parent!rodrec', z: 0, lx: 'Parent!vx', ly: 'Parent!esp', lz: 'MAX(Parent!rod,0.1)', mat: c, hidden: 'IF(Parent!rod<=0,1,0)')
        T.leaf(r, 'Travessa da gaveta', x: 'Parent!esp', y: 'Parent!espf', z: 'Parent!rod+Parent!hp-Parent!esp/2', lx: 'Parent!vx', ly: 'Parent!pc-Parent!fundo', lz: 'Parent!esp', mat: c, hidden: 'IF(Parent!frente=2,0,1)')
        (1..MAX_PRAT).each do |i|
          T.leaf(r, 'Prateleira', x: 'Parent!esp', y: 'Parent!espf+2', z: "Parent!rod+Parent!esp+#{i}*Parent!hint/(Parent!prat+1)-Parent!esp/2",
                                  lx: 'Parent!vx', ly: 'Parent!pc-Parent!fundo-2', lz: 'Parent!esp', mat: c,
                                  hidden: "IF(OR(Parent!prat<#{i},Parent!frente=3),1,0)")
        end
        T.leaf(r, 'Tampo', x: 0, y: 0, z: 'Parent!LenZ-Parent!esptampo', lx: 'Parent!LenX', ly: 'Parent!LenY', lz: 'MAX(Parent!esptampo,0.1)',
                           mat: 'Parent!mattampo', hidden: 'IF(AND(Parent!tampo=1,Parent!tampovis=1),0,1)', part: 'tampo')
      end

      def front_pass(w, h)
        {
          'lf' => [w], 'hf' => [h], 'ef' => ['Parent!espf'], 'mf' => ['Parent!matfrente', :str],
          'px' => ['Parent!puxador', :float], 'pz' => ['Parent!pz', :float], 'py' => ['IF(pz>0.5,hf-3,0)']
        }
      end

      # Puxadores de porta (barra em pé no lado que abre)
      def door_handles(n, bar_x, left_x)
        T.leaf(n, 'Puxador barra', x: bar_x, y: '-Parent!ef-2.5', z: 'MAX(Parent!hf*Parent!pz-8,1)', lx: 1.2, ly: 2.5, lz: 16,
                                   hidden: 'IF(Parent!px=2,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
        T.leaf(n, 'Puxador perfil', x: left_x, y: '-Parent!ef-1', z: 'Parent!py', lx: 'Parent!lf', ly: 1, lz: 3,
                                    hidden: 'IF(Parent!px=1,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
        T.leaf(n, 'Cava', x: left_x, y: '-Parent!ef-0.05', z: 'Parent!py', lx: 'Parent!lf', ly: 0.05, lz: 2.5,
                          hidden: 'IF(Parent!px=3,0,1)', part: 'acabamento', fixed_mat: 'PLN_Cava')
      end

      def hinges(n, x)
        [['8', nil], ['Parent!hf-13', nil], ['Parent!hf/2-2.5', 'IF(Parent!hf<100,1,0)']].each do |z, hid|
          T.leaf(n, 'Dobradiça', x: x, y: 0, z: z, lx: 3.5, ly: 1.2, lz: 5, hidden: hid, part: 'ferragem', fixed_mat: 'PLN_Ferragem')
        end
      end

      def doors(r)
        pass = front_pass('Parent!wp-Parent!folga', 'Parent!hp-Parent!folga')
        left = T.node(r, 'Porta esquerda', x: 'Parent!folga/2', y: 'Parent!espf', z: 'Parent!rod+Parent!folga/2',
                                           pass: pass, hidden: 'IF(Parent!temporta=1,0,1)', onclick: 'ANIMATE("rotz",0,-95)')
        T.leaf(left, 'Porta', x: 0, y: '-Parent!ef', z: 0, lx: 'Parent!lf', ly: 'Parent!ef', lz: 'Parent!hf', mat: 'Parent!mf', part: 'porta')
        door_handles(left, 'Parent!lf-4', 0)
        hinges(left, 1)

        right = T.node(r, 'Porta direita', x: 'Parent!LenX-Parent!folga/2', y: 'Parent!espf', z: 'Parent!rod+Parent!folga/2',
                                           pass: pass, hidden: 'IF(AND(Parent!temporta=1,Parent!nportas=2),0,1)', onclick: 'ANIMATE("rotz",0,95)')
        T.leaf(right, 'Porta', x: '-Parent!lf', y: '-Parent!ef', z: 0, lx: 'Parent!lf', ly: 'Parent!ef', lz: 'Parent!hf', mat: 'Parent!mf', part: 'porta')
        door_handles(right, '-Parent!lf+2.8', '-Parent!lf')
        hinges(right, -4.5)
      end

      def flap(r)
        pass = front_pass('Parent!LenX-Parent!folga', 'Parent!hc-Parent!folga')
        pass['py'] = ['-hf']
        pass['hy'] = ['-hf+3']
        n = T.node(r, 'Basculante', x: 'Parent!folga/2', y: 'Parent!espf', z: 'Parent!rod+Parent!hc-Parent!folga/2',
                                    pass: pass, hidden: 'IF(Parent!frente=5,0,1)', onclick: 'ANIMATE("rotx",0,-80)')
        T.leaf(n, 'Porta basculante', x: 0, y: '-Parent!ef', z: '-Parent!hf', lx: 'Parent!lf', ly: 'Parent!ef', lz: 'Parent!hf', mat: 'Parent!mf', part: 'porta')
        T.leaf(n, 'Puxador barra', x: 'Parent!lf/2-8', y: '-Parent!ef-2.5', z: 'Parent!hy', lx: 16, ly: 2.5, lz: 1.2,
                                   hidden: 'IF(Parent!px=2,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
        T.leaf(n, 'Puxador perfil', x: 0, y: '-Parent!ef-1', z: 'Parent!py', lx: 'Parent!lf', ly: 1, lz: 3,
                                    hidden: 'IF(Parent!px=1,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
        T.leaf(n, 'Cava', x: 0, y: '-Parent!ef-0.05', z: 'Parent!py', lx: 'Parent!lf', ly: 0.05, lz: 2.5,
                          hidden: 'IF(Parent!px=3,0,1)', part: 'acabamento', fixed_mat: 'PLN_Cava')
        %w[6 Parent!lf-9.5].each do |x|
          T.leaf(n, 'Dobradiça', x: x, y: 0, z: -6, lx: 3.5, ly: 1.2, lz: 5, part: 'ferragem', fixed_mat: 'PLN_Ferragem')
        end
      end

      def drawer(r, i)
        slot = T.node(r, "Gaveta #{i + 1}", x: 0, y: 0, z: "Parent!zg0+#{i}*Parent!hg",
                                            pass: {
                                              'w' => ['Parent!LenX'], 'h' => ['Parent!hg'], 'f' => ['Parent!folga'], 'ef' => ['Parent!espf'],
                                              'mf' => ['Parent!matfrente', :str], 'mc' => ['Parent!matcaixa', :str], 'pc' => ['Parent!pc'],
                                              'e' => ['Parent!esp'], 'vx' => ['Parent!vx'], 'px' => ['Parent!puxador', :float], 'fd' => ['Parent!fundo']
                                            },
                                            hidden: "IF(#{i}<Parent!ng,0,1)")
        b = T.node(slot, 'Corpo da gaveta', x: 0, y: 0, z: 0, y_formula: false,
                                            pass: {
                                              'w' => ['Parent!w'], 'h' => ['Parent!h'], 'f' => ['Parent!f'], 'ef' => ['Parent!ef'],
                                              'mf' => ['Parent!mf', :str], 'mc' => ['Parent!mc', :str], 'pc' => ['Parent!pc'], 'e' => ['Parent!e'],
                                              'vx' => ['Parent!vx'], 'px' => ['Parent!px', :float], 'fd' => ['Parent!fd'],
                                              'abre' => ['Parent!pc*0.7'], 'lf' => ['Parent!w-Parent!f'], 'py' => ['Parent!h-Parent!f-3'],
                                              'hy' => ['Parent!h-7'], 'bh' => ['MAX(Parent!h-7,6)'], 'bd' => ['Parent!pc-Parent!fd-3']
                                            },
                                            onclick: 'ANIMATE("y",0,-abre)')
        T.leaf(b, 'Frente da gaveta', x: 'Parent!f/2', y: 0, z: 'Parent!f/2', lx: 'Parent!w-Parent!f', ly: 'Parent!ef', lz: 'Parent!h-Parent!f', mat: 'Parent!mf', part: 'frente_gaveta')
        T.leaf(b, 'Lateral da gaveta', x: 'Parent!e+1.3', y: 'Parent!ef', z: 3, lx: 1.5, ly: 'Parent!bd', lz: 'Parent!bh', mat: 'Parent!mc', part: 'gaveta')
        T.leaf(b, 'Lateral da gaveta', x: 'Parent!w-Parent!e-2.8', y: 'Parent!ef', z: 3, lx: 1.5, ly: 'Parent!bd', lz: 'Parent!bh', mat: 'Parent!mc', part: 'gaveta')
        T.leaf(b, 'Contrafrente', x: 'Parent!e+2.8', y: 'Parent!ef', z: 3, lx: 'Parent!vx-5.6', ly: 1.5, lz: 'Parent!bh', mat: 'Parent!mc', part: 'gaveta')
        T.leaf(b, 'Traseira da gaveta', x: 'Parent!e+2.8', y: 'Parent!ef+Parent!bd-1.5', z: 3, lx: 'Parent!vx-5.6', ly: 1.5, lz: 'Parent!bh', mat: 'Parent!mc', part: 'gaveta')
        T.leaf(b, 'Fundo da gaveta', x: 'Parent!e+1.3', y: 'Parent!ef', z: 2.4, lx: 'Parent!vx-2.6', ly: 'Parent!bd', lz: 0.6, mat: 'Parent!mc', part: 'fundo')
        T.leaf(b, 'Corrediça', x: 'Parent!e', y: 'Parent!ef+1', z: 4, lx: 1.3, ly: 'Parent!bd-2', lz: 3.5, part: 'ferragem', fixed_mat: 'PLN_Ferragem')
        T.leaf(b, 'Corrediça', x: 'Parent!w-Parent!e-1.3', y: 'Parent!ef+1', z: 4, lx: 1.3, ly: 'Parent!bd-2', lz: 3.5, part: 'ferragem', fixed_mat: 'PLN_Ferragem')
        T.leaf(b, 'Puxador barra', x: 'Parent!w/2-8', y: -2.5, z: 'Parent!hy', lx: 16, ly: 2.5, lz: 1.2,
                                   hidden: 'IF(Parent!px=2,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
        T.leaf(b, 'Puxador perfil', x: 'Parent!f/2', y: -1, z: 'Parent!py', lx: 'Parent!lf', ly: 1, lz: 3,
                                    hidden: 'IF(Parent!px=1,0,1)', part: 'puxador', fixed_mat: 'PLN_Aluminio')
        T.leaf(b, 'Cava', x: 'Parent!f/2', y: -0.05, z: 'Parent!py', lx: 'Parent!lf', ly: 0.05, lz: 2.5,
                          hidden: 'IF(Parent!px=3,0,1)', part: 'acabamento', fixed_mat: 'PLN_Cava')
      end
    end
  end
end
