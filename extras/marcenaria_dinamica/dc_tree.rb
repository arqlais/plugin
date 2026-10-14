# Árvore de um componente dinâmico, independente do SketchUp.
#
# Cada Ent tem atributos (com fórmula ou valor) e filhos. A mesma árvore:
#  - é avaliada aqui (DCFormula) para saber posição e tamanho de cada peça;
#  - vira entidades no SketchUp (tools/joinery.rb), com as fórmulas gravadas
#    em dynamic_attributes para o bloco continuar dinâmico;
#  - é testada e desenhada fora do SketchUp (dev/test_core.rb, dev/render_dc.rb).
# Todas as medidas aqui são em centímetros.

module LAVIStudio
  module Plugin
    module DCTree
      ALIAS = { 'lenx' => 'lenx', 'leny' => 'leny', 'lenz' => 'lenz' }.freeze

      Attr = Struct.new(:name, :value, :formula, :kind, :access, :label, :options)

      class Ent
        attr_reader :name, :type, :attrs, :children, :meta
        attr_accessor :parent

        def initialize(name, type, meta = {})
          @name = name
          @type = type # :root, :node, :leaf
          @attrs = {}
          @children = []
          @meta = meta
          @cache = {}
        end

        def leaf?
          @type == :leaf
        end

        # kind: :len (cm), :int, :float, :str
        def set(name, value = nil, f: nil, kind: :len, access: 'NONE', label: nil, options: nil)
          @attrs[name.downcase] = Attr.new(name.downcase, value, f && f.to_s, kind, access, label, options)
          self
        end

        def add(child)
          child.parent = self
          @children << child
          child
        end

        def reset!
          @cache = {}
          @children.each(&:reset!)
        end

        def get(name, stack = [])
          key = name.to_s.downcase
          return @cache[key] if @cache.key?(key)
          a = @attrs[key]
          raise DCFormula::Error, "#{@name}: atributo \"#{name}\" não existe" unless a
          raise DCFormula::Error, "#{@name}: fórmula circular em #{key}" if stack.include?([object_id, key])
          v = if a.formula
                resolve = lambda do |ref|
                  if ref =~ /\Aparent!(.+)\z/i
                    raise DCFormula::Error, "#{@name}: sem Parent" unless @parent
                    @parent.get(Regexp.last_match(1), stack + [[object_id, key]])
                  else
                    get(ref, stack + [[object_id, key]])
                  end
                end
                DCFormula.eval(a.formula, resolve)
              else
                a.value
              end
          v = v.to_f if %i[len float int].include?(a.kind) && !v.is_a?(String)
          @cache[key] = v
        end

        def num(name, default = 0.0)
          return default unless @attrs.key?(name)
          get(name).to_f
        end

        def hidden?
          @attrs.key?('hidden') && get('hidden').to_f != 0
        end

        # Lista de caixas das peças visíveis: {name:, part:, mat:, org: [x,y,z], size: [lx,ly,lz]}
        def boxes(origin = [0.0, 0.0, 0.0], out = [])
          return out if hidden?
          here = @type == :root ? origin : [origin[0] + num('x'), origin[1] + num('y'), origin[2] + num('z')]
          if leaf?
            size = %w[lenx leny lenz].map { |k| [num(k), 0.05].max }
            mat = @attrs.key?('material') ? get('material') : @meta[:fixed_mat]
            out << { name: @name, part: @meta[:part], mat: mat, org: here, size: size, ent: self }
          end
          @children.each { |c| c.boxes(here, out) }
          out
        end

        def each(&block)
          yield self
          @children.each { |c| c.each(&block) }
        end
      end

      module_function

      def leaf(parent, name, x:, y:, z:, lx:, ly:, lz:, mat: nil, hidden: nil, part: 'caixa', fixed_mat: nil)
        e = Ent.new(name, :leaf, part: part, fixed_mat: fixed_mat)
        e.set('x', 0, f: x).set('y', 0, f: y).set('z', 0, f: z)
        e.set('lenx', 0, f: lx).set('leny', 0, f: ly).set('lenz', 0, f: lz)
        e.set('material', '', f: mat, kind: :str) if mat
        e.set('hidden', 0, f: hidden, kind: :float) if hidden
        parent.add(e)
      end

      def node(parent, name, x:, y:, z:, pass: {}, hidden: nil, onclick: nil, y_formula: true)
        e = Ent.new(name, :node, onclick: onclick)
        e.set('x', 0, f: x).set('y', 0, f: (y_formula ? y : nil)).set('z', 0, f: z)
        e.set('rotx', 0, kind: :float).set('rotz', 0, kind: :float)
        pass.each { |k, (f, kind)| e.set(k, kind == :str ? '' : 0, f: f, kind: kind || :len) }
        e.set('hidden', 0, f: hidden, kind: :float) if hidden
        parent.add(e)
      end
    end
  end
end
