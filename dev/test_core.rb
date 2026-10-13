# Testes da parte que não depende do SketchUp: geometria 2D, plano de corte,
# escada, paginação, licenças e comparação de versões.
# Rodar: ruby dev/test_core.rb

require 'minitest/autorun'
require 'json'
require 'digest'

# ---- stubs mínimos do SketchUp ------------------------------------------------
class Numeric
  def mm; self / 25.4; end
  def cm; self / 2.54; end
end

module Sketchup
  @prefs = {}
  def self.read_default(_s, k, d = nil) = @prefs.fetch(k, d)
  def self.write_default(_s, k, v) = (@prefs[k] = v)
end
def file_loaded?(_f) = true
def file_loaded(_f) = nil
IDENTITY = nil

ROOT_DIR = File.expand_path('..', __dir__)
module Plane
  module Plugin
    PLUGIN_NAME = 'Planê Plugin'
    VERSION = '0.4.1'
    ROOT = File.join(ROOT_DIR, 'plane_plugin')
  end
end
%w[registry license helpers geom nesting dc_formula dc_tree].each { |f| require File.join(ROOT_DIR, 'plane_plugin', 'core', f) }
module Plane::Plugin::Dialog; def self.push(*); end; end
require File.join(ROOT_DIR, 'plane_plugin', 'core', 'updater')
require File.join(ROOT_DIR, 'plane_plugin', 'tools', 'joinery_spec')
Dir[File.join(ROOT_DIR, 'plane_plugin', 'tools', '*.rb')].sort.each { |f| require f }

P = Plane::Plugin
G = P::Geom2

class TestCore < Minitest::Test
  def test_all_tools_registered
    ids = P::Registry.all.map { |t| t[:id] }
    %i[walls openings dwg_walls stairs roofs urban_index tiling wall_tiling baseboard ceiling
       joinery cut_list countertop takeoff budget model_health align replace auto_tags].each do |id|
      assert_includes ids, id
    end
    P::Registry.all.each { |t| assert t[:handler].respond_to?(:handle), "#{t[:id]} sem handle" }
    JSON.generate(P::Registry.to_ui)
  end

  def test_area_and_offset
    sq = [[0, 0], [10, 0], [10, 10], [0, 10]]
    assert_in_delta 100, G.area(sq)
    inner = G.offset_polyline(sq, 1, true)
    assert_in_delta 64, G.area(inner), 1e-6
    open = G.offset_polyline([[0, 0], [10, 0], [10, 10]], 1, false)
    assert_equal [[0.0, 1.0], [9.0, 1.0], [9.0, 10.0]], open.map { |p| p.map { |v| v.round(6) } }
  end

  def test_clip_concave_room
    room = G.ccw([[0, 0], [10, 0], [10, 4], [4, 4], [4, 10], [0, 10]]) # L
    tile = [[3, 3], [6, 3], [6, 6], [3, 6]]
    piece = G.clip(room, tile)
    assert_in_delta 5, G.area(piece), 1e-6
  end

  def test_tiling_counts
    room = [[0, 0], [300.cm, 0], [300.cm, 200.cm], [0, 200.cm]]
    r = P::Tools::Tiling.layout(room, [], 'pc' => 60, 'pl' => 60, 'rej' => 0)
    assert_equal 15, r[:full]
    assert_equal 5, r[:cut]
    total = r[:pieces].sum { |p| G.area(p) }
    assert_in_delta G.area(room), total, 1
    r2 = P::Tools::Tiling.layout(room, [], 'pc' => 60, 'pl' => 30, 'rej' => 2, 'padrao' => 'meia', 'ang' => 45)
    assert r2[:pieces].size > 30
    assert r2[:pieces].sum { |p| G.area(p) } < G.area(room)
  end

  def test_nesting
    pcs = Array.new(10) { { w: 700, h: 550, label: 'Lateral' } } + Array.new(4) { { w: 1800, h: 600, label: 'Torre' } }
    sheets = P::Nesting.pack(pcs, sheet_w: 2750, sheet_h: 1840)
    placed = sheets.sum { |s| s[:parts].size }
    assert_equal 14, placed
    sheets.each do |s|
      s[:parts].each do |a|
        assert a[:x] + a[:w] <= 2750 - 10 + 1e-6
        assert a[:y] + a[:h] <= 1840 - 10 + 1e-6
        s[:parts].each do |b|
          next if a.equal?(b)
          overlap = a[:x] < b[:x] + b[:w] && b[:x] < a[:x] + a[:w] && a[:y] < b[:y] + b[:h] && b[:y] < a[:y] + a[:h]
          refute overlap, 'peças sobrepostas'
        end
      end
    end
    assert sheets.size <= 3
  end

  def test_stairs_blondel
    c = P::Tools::Stairs.calc('alt' => 280)
    assert_equal 16, c[:n]
    assert_in_delta 17.5, c[:e], 0.01
    assert c[:blondel].between?(63, 64.5)
    assert_empty c[:avisos]
  end

  def test_license
    serial = 'AB12C'
    key = "PLANE-MARC-#{serial}-#{P::License.check_digits('MARC', serial)}"
    assert_equal 'MARC', P::License.parse(key)
    assert_nil P::License.parse(key.sub(/.$/, key[-1] == '0' ? '1' : '0'))
    assert P::License.activate(key)[:ok]
  end

  def test_versions
    assert P::Updater.newer?('0.4.1', '0.4.0')
    assert P::Updater.newer?('0.10.0', '0.9.9')
    refute P::Updater.newer?('0.4.0', '0.4.0')
  end

  def test_br_format
    assert_equal '1.234,50', P::Helpers.br(1234.5)
    assert_equal '-12,0', P::Helpers.br(-12, 1)
  end

  def test_dc_option_encoding
    s = P::JoinerySpec.opts([['Gaveta + portas', 2], ['Freijó', 'PLN_Freijo']])
    assert_equal '&Gaveta%20%2B%20portas=2&Freij%C3%B3=PLN_Freijo&', s
  end

  def test_dc_formulas
    f = ->(src, vars = {}) { P::DCFormula.eval(src, ->(n) { vars.fetch(n.downcase) }) }
    assert_equal 7.0, f.call('1+2*3')
    assert_equal 1.0, f.call('IF(AND(a=2,OR(b>5,b<1)),1,0)', 'a' => 2, 'b' => 0)
    assert_equal 'x', f.call('IF(1,"x","y")')
    assert_equal 4.0, f.call('MAX(1,4,-2)')
    assert_equal 1.0, f.call('m="PLN_Freijo"', 'm' => 'PLN_Freijo')
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
                    prat: 2, puxador: pux, matfrente: 'PLN_Freijo', matcaixa: 'PLN_Branco', tampo: t[:tampo], mattampo: 'PLN_Marmore',
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
