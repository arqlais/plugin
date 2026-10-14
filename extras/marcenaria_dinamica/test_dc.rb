# Testes da marcenaria dinâmica (guardada à parte, fora do plugin por enquanto).
# Rodar: ruby extras/marcenaria_dinamica/test_dc.rb
require 'minitest/autorun'
module LAVIStudio; module Plugin; end; end
%w[dc_formula dc_tree joinery_spec].each { |f| require File.join(__dir__, f) }
P = LAVIStudio::Plugin

class TestDC < Minitest::Test
  def test_dc_option_encoding
    s = P::JoinerySpec.opts([['Gaveta + portas', 2], ['Freijó', 'LAVI_Freijo']])
    assert_equal '&Gaveta%20%2B%20portas=2&Freij%C3%B3=LAVI_Freijo&', s
  end

  def test_dc_formulas
    f = ->(src, vars = {}) { P::DCFormula.eval(src, ->(n) { vars.fetch(n.downcase) }) }
    assert_equal 7.0, f.call('1+2*3')
    assert_equal 1.0, f.call('IF(AND(a=2,OR(b>5,b<1)),1,0)', 'a' => 2, 'b' => 0)
    assert_equal 'x', f.call('IF(1,"x","y")')
    assert_equal 4.0, f.call('MAX(1,4,-2)')
    assert_equal 1.0, f.call('m="LAVI_Freijo"', 'm' => 'LAVI_Freijo')
  end

  # Todas as combinações: nada pode sair da caixa do módulo (puxadores podem ficar na frente)
  def test_cabinet_layouts
    spec = P::JoinerySpec
    count = 0
    spec::TIPOS.each do |tipo, t|
      [1, 2, 3, 4, 5].each do |frente|
        [1, 2].each do |np|
          [1, 2, 3, 4].each do |pux|
            [40, 60, 120].each do |lx|
              s = { tipo: tipo, nome: t[:nome], lx: lx, ly: t[:ly], lz: t[:lz], frente: frente, nportas: np, ngav: 4, hgav: 18,
                    prat: 2, puxador: pux, matfrente: 'LAVI_Freijo', matcaixa: 'LAVI_Branco', tampo: t[:tampo], mattampo: 'LAVI_Marmore',
                    esptampo: 2, esp: 1.5, espf: 1.8, fundo: 0.6, folga: 0.3, rod: t[:rod], rodrec: 5, pz: t[:pz] }
              boxes = spec.build(s).boxes
              count += 1
              boxes.each do |b|
                min = b[:org]
                max = b[:org].zip(b[:size]).map { |o, l| o + l }
                tol = 0.01
                assert min[0] >= -tol && max[0] <= lx + tol, "#{tipo}/#{frente}: #{b[:name]} sai na largura (#{min[0]}..#{max[0]})"
                assert min[2] >= -tol && max[2] <= s[:lz] + tol, "#{tipo}/#{frente}: #{b[:name]} sai na altura"
                assert max[1] <= s[:ly] + tol, "#{tipo}/#{frente}: #{b[:name]} sai no fundo"
                assert min[1] >= -tol || %w[puxador acabamento].include?(b[:part]), "#{tipo}/#{frente}: #{b[:name]} sai na frente"
                assert b[:size].all? { |v| v > 0 }, "#{b[:name]} com medida zero"
              end
              fronts = boxes.count { |b| %w[porta frente_gaveta].include?(b[:part]) }
              expected = { 1 => np, 2 => np + 1, 3 => 4, 4 => 0, 5 => 1 }[frente]
              assert_equal expected, fronts, "#{tipo} frente #{frente}: frentes visíveis"
              mdf = boxes.find { |b| b[:name] == 'Lateral esquerda' }
              assert_in_delta 1.5, mdf[:size][0], 1e-9, 'lateral não pode engrossar ao esticar'
            end
          end
        end
      end
    end
    assert count > 300
  end
end
