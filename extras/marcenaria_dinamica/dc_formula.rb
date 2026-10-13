# Avaliador das fórmulas de componente dinâmico usadas pelo Planê.
# Serve para o plugin montar o móvel já no lugar certo (sem depender do redesenho
# do SketchUp) e para testar os blocos fora do SketchUp (dev/test_core.rb).
#
# Suporta: números, "textos", + - * /, = <> < > <= >=, parênteses,
# IF, MAX, MIN, AND, OR, NOT, ABS, ROUND, FLOOR, CEILING, ANIMATE (ignorado)
# e referências: nome, Parent!nome, LenX/LenY/LenZ.

module PlaneLA
  module Plugin
    module DCFormula
      class Error < StandardError; end

      TOKEN = /\s*(?:(\d+(?:\.\d+)?|\.\d+)|("(?:[^"]*)")|([A-Za-z_][A-Za-z0-9_]*(?:![A-Za-z_][A-Za-z0-9_]*)?)|(<=|>=|<>|[-+*\/=<>(),]))/

      module_function

      def tokenize(src)
        out = []
        s = src.to_s
        pos = 0
        while pos < s.size
          break if s[pos..-1].strip.empty?
          m = TOKEN.match(s, pos)
          raise Error, "fórmula inválida perto de: #{s[pos..-1]}" unless m && m.begin(0) == pos
          if m[1] then out << [:num, m[1].to_f]
          elsif m[2] then out << [:str, m[2][1..-2]]
          elsif m[3] then out << [:id, m[3]]
          else out << [:op, m[4]]
          end
          pos = m.end(0)
        end
        out
      end

      # resolve: lambda(nome) -> valor. 'Parent!x' chega inteiro.
      def eval(src, resolve)
        Parser.new(tokenize(src), resolve).parse
      end

      class Parser
        def initialize(tokens, resolve)
          @t = tokens
          @i = 0
          @resolve = resolve
        end

        def parse
          v = compare
          raise Error, "sobrou: #{@t[@i..-1].map(&:last).join}" if @i < @t.size
          v
        end

        def peek
          @t[@i]
        end

        def take(op = nil)
          tok = @t[@i]
          raise Error, "esperava #{op}" if op && (tok.nil? || tok[1] != op)
          @i += 1
          tok
        end

        def op?(*ops)
          tok = peek
          tok && tok[0] == :op && ops.include?(tok[1])
        end

        def truthy(v)
          v.is_a?(String) ? !v.empty? : v.to_f != 0
        end

        def compare
          a = sum
          while op?('=', '<>', '<', '>', '<=', '>=')
            o = take[1]
            b = sum
            a = cmp(a, o, b) ? 1.0 : 0.0
          end
          a
        end

        def cmp(a, o, b)
          if a.is_a?(String) || b.is_a?(String)
            a = a.to_s
            b = b.to_s
          else
            a = a.to_f.round(9)
            b = b.to_f.round(9)
          end
          case o
          when '=' then a == b
          when '<>' then a != b
          when '<' then a < b
          when '>' then a > b
          when '<=' then a <= b
          else a >= b
          end
        end

        def sum
          a = term
          while op?('+', '-')
            o = take[1]
            b = term
            a = o == '+' ? (a.is_a?(String) || b.is_a?(String) ? "#{a}#{b}" : a.to_f + b.to_f) : a.to_f - b.to_f
          end
          a
        end

        def term
          a = unary
          while op?('*', '/')
            o = take[1]
            b = unary
            if o == '*'
              a = a.to_f * b.to_f
            else
              raise Error, 'divisão por zero' if b.to_f.zero?
              a = a.to_f / b.to_f
            end
          end
          a
        end

        def unary
          if op?('-')
            take
            return -unary.to_f
          end
          take if op?('+')
          primary
        end

        def primary
          tok = take
          raise Error, 'fórmula incompleta' unless tok
          case tok[0]
          when :num, :str then tok[1]
          when :op
            raise Error, "não esperava #{tok[1]}" unless tok[1] == '('
            v = compare
            take(')')
            v
          when :id
            if op?('(')
              call(tok[1].upcase)
            else
              @resolve.call(tok[1])
            end
          end
        end

        def args
          take('(')
          list = []
          unless op?(')')
            list << compare
            while op?(',')
              take
              list << compare
            end
          end
          take(')')
          list
        end

        def call(name)
          a = args
          case name
          when 'IF' then truthy(a[0]) ? a[1] : a[2]
          when 'MAX' then a.map(&:to_f).max
          when 'MIN' then a.map(&:to_f).min
          when 'AND' then a.all? { |x| truthy(x) } ? 1.0 : 0.0
          when 'OR' then a.any? { |x| truthy(x) } ? 1.0 : 0.0
          when 'NOT' then truthy(a[0]) ? 0.0 : 1.0
          when 'ABS' then a[0].to_f.abs
          when 'ROUND' then a[0].to_f.round((a[1] || 0).to_i).to_f
          when 'FLOOR' then a[0].to_f.floor.to_f
          when 'CEILING' then a[0].to_f.ceil.to_f
          when 'ANIMATE', 'ANIMATESLOW', 'ANIMATEFAST' then 0.0
          else raise Error, "função desconhecida: #{name}"
          end
        end
      end
    end
  end
end
