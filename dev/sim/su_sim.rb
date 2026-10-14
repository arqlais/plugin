# SketchUp simulado (só para testes): geometria de verdade em Ruby puro.
# Faces com contorno e furos, arestas compartilhadas, empurrar/puxar, grupos e componentes
# com transformações, materiais, etiquetas, cenas, câmera, cortes, textos e cotas.
# Não desenha nada: serve para rodar as ferramentas do plugin e conferir o que elas criam.
# Uso: require_relative 'sim/su_sim' (antes de carregar o plugin)

require 'tmpdir'
require 'fileutils'

$loaded = {}
def file_loaded?(f) $loaded[f] end
def file_loaded(f) $loaded[f] = true end

TOL = 1e-3

class Numeric
  def mm; to_f / 25.4; end
  def cm; to_f / 2.54; end
  def m; to_f / 0.0254; end
  def inch; to_f; end
  def feet; to_f * 12; end
  def to_l; to_f; end
  def to_mm; to_f * 25.4; end
  def to_cm; to_f * 2.54; end
  def to_m; to_f * 0.0254; end
  def degrees; to_f * Math::PI / 180; end
  def radians; to_f * 180 / Math::PI; end
end

class String
  # "5", "5,5", "350cm", "80mm", "2m", "10\"" → polegadas (modelo em cm por padrão)
  def to_l
    t = strip.tr(',', '.')
    m = t.match(/\A(-?\d+(?:\.\d+)?)\s*(mm|cm|m|"|')?\z/) or raise ArgumentError, "Cannot convert \"#{self}\" to Length"
    v = m[1].to_f
    case m[2]
    when 'mm' then v / 25.4
    when 'm' then v / 0.0254
    when '"' then v
    when "'" then v * 12
    else v / 2.54
    end
  end
end

module Geom
  class Vector3d
    attr_accessor :x, :y, :z

    def initialize(*a)
      a = a[0].to_a if a.size == 1
      @x, @y, @z = (a + [0, 0, 0])[0, 3].map(&:to_f)
    end

    def to_a; [@x, @y, @z]; end
    def [](i) to_a[i] end
    def clone; Vector3d.new(@x, @y, @z); end
    def length; Math.sqrt(@x * @x + @y * @y + @z * @z); end

    def length=(l)
      n = length
      raise ArgumentError, 'vetor nulo' if n < 1e-12
      k = l.to_f / n
      @x *= k; @y *= k; @z *= k
    end

    def valid?; length > 1e-10; end
    def normalize; v = clone; v.normalize!; v; end

    def normalize!
      n = length
      return self if n < 1e-12
      @x /= n; @y /= n; @z /= n
      self
    end

    def dot(o) @x * o.x + @y * o.y + @z * o.z end
    alias % dot

    def cross(o) Vector3d.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x) end
    alias * cross

    def +(o) Vector3d.new(@x + o.x, @y + o.y, @z + o.z) end
    def -(o) Vector3d.new(@x - o.x, @y - o.y, @z - o.z) end
    def reverse; Vector3d.new(-@x, -@y, -@z); end
    def reverse!; @x = -@x; @y = -@y; @z = -@z; self; end
    def parallel?(o) cross(o).length < 1e-6 * [length * o.length, 1e-12].max end
    def samedirection?(o) parallel?(o) && dot(o) > 0 end
    def perpendicular?(o) dot(o).abs < 1e-9 end

    def angle_between(o)
      c = dot(o) / (length * o.length)
      Math.acos([[c, 1].min, -1].max)
    end

    def transform(t) t.apply_vec(self) end
    def transform!(t) v = transform(t); @x, @y, @z = v.to_a; self end
    def unitvector?; (length - 1).abs < 1e-9; end
    def ==(o) o.respond_to?(:to_a) && to_a.zip(o.to_a).all? { |a, b| (a - b.to_f).abs < TOL } end
    def inspect; "Vector3d(#{to_a.map { |v| v.round(4) }.join(', ')})"; end
    def axes
      z = normalize
      x = (z.parallel?(Vector3d.new(0, 0, 1)) ? Vector3d.new(1, 0, 0) : Vector3d.new(0, 0, 1).cross(z)).normalize
      [x, z.cross(x), z]
    end
  end

  class Point3d
    attr_accessor :x, :y, :z

    def initialize(*a)
      a = a[0].to_a if a.size == 1
      @x, @y, @z = (a + [0, 0, 0])[0, 3].map(&:to_f)
    end

    def to_a; [@x, @y, @z]; end
    def [](i) to_a[i] end
    def clone; Point3d.new(@x, @y, @z); end

    def +(v) Point3d.new(@x + v.x, @y + v.y, @z + v.z) end

    def -(o)
      return Point3d.new(@x - o.x, @y - o.y, @z - o.z) if o.is_a?(Vector3d)
      Vector3d.new(@x - o.x, @y - o.y, @z - o.z)
    end

    def vector_to(o) o - self end
    def distance(o) (self - Point3d.new(o.to_a)).length end

    def offset(v, len = nil)
      v = v.clone
      v.length = len if len
      self + v
    end

    def offset!(v, len = nil) p = offset(v, len); @x, @y, @z = p.to_a; self end
    def transform(t) t.apply_pt(self) end
    def transform!(t) p = transform(t); @x, @y, @z = p.to_a; self end
    def ==(o) o.respond_to?(:to_a) && to_a.zip(o.to_a).all? { |a, b| (a - b.to_f).abs < TOL } end
    def inspect; "Point3d(#{to_a.map { |v| v.round(3) }.join(', ')})"; end
    def to_s; inspect; end

    def project_to_plane(plane)
      pt, n = Geom.plane_pn(plane)
      d = (self - pt).dot(n)
      self - Vector3d.new(n.x * d, n.y * d, n.z * d)
    end

    def distance_to_plane(plane)
      pt, n = Geom.plane_pn(plane)
      (self - pt).dot(n).abs
    end

    def on_plane?(plane) distance_to_plane(plane) < TOL end

    def self.linear_combination(w1, p1, w2, p2)
      Point3d.new(p1.x * w1 + p2.x * w2, p1.y * w1 + p2.y * w2, p1.z * w1 + p2.z * w2)
    end
  end

  def self.linear_combination(w1, p1, w2, p2) Point3d.linear_combination(w1, p1, w2, p2) end

  def self.plane_pn(plane)
    if plane.size == 2
      [Point3d.new(plane[0].to_a), Vector3d.new(plane[1].to_a).normalize]
    else
      a, b, c, d = plane
      n = Vector3d.new(a, b, c)
      l = n.length
      [Point3d.new(-a * d / (l * l), -b * d / (l * l), -c * d / (l * l)), n.normalize]
    end
  end

  def self.intersect_line_line(l1, l2)
    p1 = Point3d.new(l1[0].to_a); d1 = l1[1].is_a?(Point3d) ? l1[1] - p1 : Vector3d.new(l1[1].to_a)
    p2 = Point3d.new(l2[0].to_a); d2 = l2[1].is_a?(Point3d) ? l2[1] - p2 : Vector3d.new(l2[1].to_a)
    n = d1.cross(d2)
    return nil if n.length < 1e-10
    t = (p2 - p1).cross(d2).dot(n) / n.dot(n)
    p1.offset(d1, d1.length * t)
  end

  def self.intersect_line_plane(line, plane)
    p0 = Point3d.new(line[0].to_a)
    d = line[1].is_a?(Point3d) ? line[1] - p0 : Vector3d.new(line[1].to_a)
    pt, n = plane_pn(plane)
    den = d.dot(n)
    return nil if den.abs < 1e-12
    t = (pt - p0).dot(n) / den
    Point3d.new(p0.x + d.x * t, p0.y + d.y * t, p0.z + d.z * t)
  end

  def self.fit_plane_to_points(*pts)
    pts = pts.flatten.map { |p| Point3d.new(p.to_a) }
    n = Sketchup::Face.newell(pts).normalize
    d = -(n.x * pts[0].x + n.y * pts[0].y + n.z * pts[0].z)
    [n.x, n.y, n.z, d]
  end

  def self.point_in_polygon_2D(pt, poly, border)
    inside = false
    j = poly.size - 1
    poly.each_with_index do |pi, i|
      pj = poly[j]
      if ((pi.y > pt.y) != (pj.y > pt.y)) && (pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x)
        inside = !inside
      end
      j = i
    end
    inside
  end

  class Transformation
    attr_reader :m # 4x4, linhas; ponto como coluna

    def initialize(*a)
      @m = [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]
      if a.size == 1 && a[0].is_a?(Array) && a[0].size == 16
        v = a[0].map(&:to_f) # ordem do SketchUp: coluna por coluna
        @m = (0..3).map { |r| (0..3).map { |c| v[c * 4 + r] } }
      elsif a.size == 1 && (a[0].is_a?(Point3d) || a[0].is_a?(Vector3d) || (a[0].is_a?(Array) && a[0].size == 3))
        x, y, z = a[0].to_a
        @m[0][3] = x.to_f; @m[1][3] = y.to_f; @m[2][3] = z.to_f
      elsif a.size == 1 && a[0].is_a?(Transformation)
        @m = a[0].m.map(&:dup)
      elsif a.size == 3 && a[0].is_a?(Point3d) # origem, eixo x, eixo y
        z = a[1].cross(a[2])
        set_axes(a[0], a[1].normalize, a[2].normalize, z.normalize)
      elsif a.size == 4
        set_axes(*a)
      end
    end

    def set_axes(o, x, y, z)
      @m = [[x.x, y.x, z.x, o.x], [x.y, y.y, z.y, o.y], [x.z, y.z, z.z, o.z], [0, 0, 0, 1.0]].map { |r| r.map(&:to_f) }
    end

    def self.from(mm) t = new; t.instance_variable_set(:@m, mm); t end
    def self.translation(v) new(Vector3d.new(v.to_a)) end
    def self.axes(o, x, y, z = nil) z ||= x.cross(y); t = new; t.set_axes(o, x, y, z); t end

    def self.rotation(pt, axis, ang)
      a = Vector3d.new(axis.to_a).normalize
      c = Math.cos(ang); s = Math.sin(ang); t = 1 - c
      x, y, z = a.to_a
      r = [[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
           [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
           [t * x * z - s * y, t * y * z + s * x, t * z * z + c]]
      p = Point3d.new(pt.to_a)
      mm = (0..2).map { |i| r[i] + [p.to_a[i] - (r[i][0] * p.x + r[i][1] * p.y + r[i][2] * p.z)] } + [[0, 0, 0, 1.0]]
      from(mm)
    end

    def self.scaling(*a)
      if a.size == 1
        k = a[0].to_f; return from([[k, 0, 0, 0], [0, k, 0, 0], [0, 0, k, 0], [0, 0, 0, 1.0]])
      end
      if a.size == 2 && a[0].is_a?(Point3d)
        k = a[1].to_f; o = a[0]
        return from([[k, 0, 0, o.x * (1 - k)], [0, k, 0, o.y * (1 - k)], [0, 0, k, o.z * (1 - k)], [0, 0, 0, 1.0]])
      end
      if a.size == 4
        o, sx, sy, sz = a
        return from([[sx, 0, 0, o.x * (1 - sx)], [0, sy, 0, o.y * (1 - sy)], [0, 0, sz, o.z * (1 - sz)], [0, 0, 0, 1.0]])
      end
      sx, sy, sz = a
      from([[sx.to_f, 0, 0, 0], [0, sy.to_f, 0, 0], [0, 0, sz.to_f, 0], [0, 0, 0, 1.0]])
    end

    def *(o)
      case o
      when Transformation then Transformation.from((0..3).map { |r| (0..3).map { |c| (0..3).sum { |k| @m[r][k] * o.m[k][c] } } })
      when Point3d then apply_pt(o)
      when Vector3d then apply_vec(o)
      when Array then apply_pt(Point3d.new(o))
      end
    end

    def apply_pt(p)
      Point3d.new(*(0..2).map { |r| @m[r][0] * p.x + @m[r][1] * p.y + @m[r][2] * p.z + @m[r][3] })
    end

    def apply_vec(v)
      Vector3d.new(*(0..2).map { |r| @m[r][0] * v.x + @m[r][1] * v.y + @m[r][2] * v.z })
    end

    def inverse
      a = @m.map(&:dup); inv = (0..3).map { |i| (0..3).map { |j| i == j ? 1.0 : 0.0 } }
      4.times do |c|
        piv = (c..3).max_by { |r| a[r][c].abs }
        raise 'transformação sem inversa' if a[piv][c].abs < 1e-14
        a[c], a[piv] = a[piv], a[c]; inv[c], inv[piv] = inv[piv], inv[c]
        f = a[c][c]
        4.times { |k| a[c][k] /= f; inv[c][k] /= f }
        4.times do |r|
          next if r == c
          g = a[r][c]
          4.times { |k| a[r][k] -= g * a[c][k]; inv[r][k] -= g * inv[c][k] }
        end
      end
      Transformation.from(inv)
    end

    def invert!; @m = inverse.m; self; end
    def origin; Point3d.new(@m[0][3], @m[1][3], @m[2][3]); end
    def xaxis; Vector3d.new(@m[0][0], @m[1][0], @m[2][0]); end
    def yaxis; Vector3d.new(@m[0][1], @m[1][1], @m[2][1]); end
    def zaxis; Vector3d.new(@m[0][2], @m[1][2], @m[2][2]); end
    def to_a; (0..3).flat_map { |c| (0..3).map { |r| @m[r][c] } }; end
    def identity?; to_a.zip(Transformation.new.to_a).all? { |a, b| (a - b).abs < 1e-9 }; end
    def clone; Transformation.new(self); end
  end

  class BoundingBox
    def initialize; @min = nil; @max = nil; end

    def add(*items)
      items.flatten.each do |it|
        if it.is_a?(BoundingBox)
          next if it.empty?
          add(it.min, it.max)
        else
          p = Point3d.new(it.to_a)
          if @min.nil?
            @min = p.clone; @max = p.clone
          else
            @min = Point3d.new(*@min.to_a.zip(p.to_a).map(&:min)); @max = Point3d.new(*@max.to_a.zip(p.to_a).map(&:max))
          end
        end
      end
      self
    end

    def empty?; @min.nil?; end
    def valid?; !empty?; end
    def min; @min || Point3d.new; end
    def max; @max || Point3d.new; end
    def center; Point3d.linear_combination(0.5, min, 0.5, max); end
    def width; max.x - min.x; end
    def height; max.y - min.y; end
    def depth; max.z - min.z; end
    def diagonal; (max - min).length; end
    def clear; @min = @max = nil; self; end

    def corner(i)
      Point3d.new(i & 1 == 0 ? min.x : max.x, i & 2 == 0 ? min.y : max.y, i & 4 == 0 ? min.z : max.z)
    end

    def contains?(p)
      p = p.is_a?(BoundingBox) ? p.center : p
      (0..2).all? { |k| p.to_a[k] >= min.to_a[k] - TOL && p.to_a[k] <= max.to_a[k] + TOL }
    end

    def intersect(o)
      b = BoundingBox.new
      lo = min.to_a.zip(o.min.to_a).map(&:max); hi = max.to_a.zip(o.max.to_a).map(&:min)
      b.add(lo, hi) if lo.zip(hi).all? { |a, c| a <= c }
      b
    end
  end
end

ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)
IDENTITY = Geom::Transformation.new
MB_OK = 0; MB_OKCANCEL = 1; MB_YESNO = 4; MB_YESNOCANCEL = 3
IDOK = 1; IDCANCEL = 2; IDYES = 6; IDNO = 7
GL_POINTS = 0; GL_LINES = 1; GL_LINE_LOOP = 2; GL_LINE_STRIP = 3; GL_TRIANGLES = 4; GL_QUADS = 7; GL_POLYGON = 9
CONSTRAIN_MODIFIER_MASK = 4; COPY_MODIFIER_MASK = 8; ALT_MODIFIER_MASK = 32
VK_SHIFT = 16; VK_CONTROL = 17
TextAlignLeft = 0; TextAlignCenter = 1; TextAlignRight = 2
TextVerticalAlignBaseline = 0; TextVerticalAlignCenter = 1

class SketchupExtension
  attr_accessor :name, :description, :version, :creator, :copyright
  def initialize(n, path) @name = n; @path = path end
  def load!; require File.join(PLUGINS, @path + '.rb'); end
end

module Sketchup
  @prefs = {}
  @ext = []
  @status = ''
  class << self
    attr_accessor :status_text, :vcb_label, :vcb_value, :installed
  end

  def self.register_extension(e, load) @ext << e; e.load! if load; true end
  def self.read_default(_s, k, d = nil) @prefs.fetch(k, d) end
  def self.write_default(_s, k, v) @prefs[k] = v end
  def self.version; '26.0.0'; end
  def self.version_number; 2_600_000_000; end
  def self.platform; :platform_win; end
  def self.is_pro?; true; end
  def self.temp_dir; Dir.tmpdir; end
  def self.active_model; @model ||= Model.new; end
  def self.reset_model!
    @model = Model.new
    (@app_obs || []).each { |o| o.onNewModel(@model) if o.respond_to?(:onNewModel) }
    @model
  end
  def self.add_observer(o) (@app_obs ||= []) << o; true end

  class EntitiesObserver; end
  class AppObserver; end
  class ModelObserver; end
  class SelectionObserver; end
  def self.install_from_archive(path, *_a) (@installed ||= []) << path; true end
  def self.find_support_file(*_a) nil end
  def self.require(f) Kernel.require(f) end
  def self.send_action(*_a) true end
  def self.break_edges=(_v) end

  class Color
    attr_accessor :red, :green, :blue, :alpha
    NAMES = { 'white' => [255, 255, 255], 'black' => [0, 0, 0], 'red' => [255, 0, 0], 'gray' => [128, 128, 128] }.freeze

    def initialize(*a)
      if a.size == 1 && a[0].is_a?(String)
        h = a[0].delete('#')
        rgb = NAMES[a[0].downcase] || [h[0, 2].to_i(16), h[2, 2].to_i(16), h[4, 2].to_i(16)]
        @red, @green, @blue = rgb; @alpha = 255
      elsif a.size == 1 && a[0].is_a?(Color)
        @red, @green, @blue, @alpha = a[0].to_a
      else
        @red, @green, @blue = a[0, 3].map(&:to_i); @alpha = (a[3] || 255).to_i
      end
    end

    def to_a; [@red, @green, @blue, @alpha]; end
    def to_i; @red + (@green << 8) + (@blue << 16); end
    def to_s; format('#%02X%02X%02X', @red, @green, @blue); end
  end

  # ---- entidades -------------------------------------------------------------
  class Entity
    @@next_id = 1
    attr_reader :entityID, :persistent_id
    attr_accessor :ents # coleção onde a entidade está
    def parent; @ents && @ents.owner; end

    def initialize
      @entityID = @@next_id
      @persistent_id = 10_000 + @@next_id
      @@next_id += 1
      @valid = true
      @dicts = {}
    end

    def valid?; @valid; end
    def deleted?; !@valid; end
    def model; Sketchup.active_model; end
    def typename; self.class.name.split('::').last; end

    def erase!
      raise TypeError, 'reference to deleted entity' unless @valid
      @ents.remove_entity(self) if @ents
      @valid = false
      true
    end

    def kill!; @valid = false; end
    def check!; raise TypeError, "reference to deleted #{typename}" unless @valid; end

    def set_attribute(d, k, v) check!; (@dicts[d.to_s] ||= {})[k.to_s] = v.is_a?(String) ? v.dup : v; v end
    def get_attribute(d, k, default = nil) check!; h = @dicts[d.to_s]; h && h.key?(k.to_s) ? h[k.to_s] : default end
    def delete_attribute(d, k = nil) k ? (@dicts[d.to_s] || {}).delete(k.to_s) : @dicts.delete(d.to_s) end
    def attribute_dictionary(name, create = false) (create ? (@dicts[name.to_s] ||= {}) : @dicts[name.to_s]) && AttrDict.new(name.to_s, @dicts[name.to_s]) end
    def attribute_dictionaries; d = @dicts; d.empty? ? nil : d.map { |k, v| AttrDict.new(k, v) }; end
  end

  class AttrDict
    include Enumerable
    attr_reader :name
    def initialize(n, h) @name = n; @h = h end
    def [](k) @h[k.to_s] end
    def []=(k, v) @h[k.to_s] = v end
    def keys; @h.keys; end
    def values; @h.values; end
    def each(&b) @h.each(&b) end
    def each_pair(&b) @h.each(&b) end
    def size; @h.size; end
    def delete_key(k) @h.delete(k.to_s) end
  end

  class Drawingelement < Entity
    attr_writer :hidden
    attr_accessor :casts_shadows, :receives_shadows

    def initialize
      super
      @hidden = false
      @layer = nil
      @material = nil
    end

    def layer; @layer || Sketchup.active_model.layers[0]; end

    def layer=(l)
      l = Sketchup.active_model.layers[l] if l.is_a?(String)
      raise ArgumentError, 'etiqueta inválida' unless l.nil? || l.is_a?(Layer)
      @layer = l
    end

    def material; @material; end

    def material=(m)
      m = Sketchup.active_model.materials[m] || Sketchup.active_model.materials.add(m) if m.is_a?(String)
      m = Sketchup.active_model.materials.add_color(m) if m.is_a?(Color)
      raise ArgumentError, 'material inválido' unless m.nil? || m.is_a?(Material)
      @material = m
    end

    def hidden?; @hidden; end
    def visible?; !@hidden; end
    def visible=(v) @hidden = !v end
  end

  class Vertex < Entity
    attr_reader :position
    attr_accessor :edges_list

    def initialize(p)
      super()
      @position = Geom::Point3d.new(p.to_a)
      @edges_list = []
    end

    def edges; @edges_list.select(&:valid?); end
    def faces; edges.flat_map(&:faces).uniq; end
    def used_by?(e) edges.include?(e) || faces.include?(e) end
    def set_position(p) @position = p end
  end

  class Edge < Drawingelement
    attr_reader :start, :end
    attr_accessor :soft, :smooth, :faces_list

    def initialize(a, b)
      super()
      @start = a; @end = b
      @faces_list = []
      a.edges_list << self; b.edges_list << self
      @soft = @smooth = false
    end

    def vertices; [@start, @end]; end
    def faces; @faces_list.select(&:valid?); end
    def length(t = nil) t ? @start.position.transform(t).distance(@end.position.transform(t)) : @start.position.distance(@end.position) end
    def line; [@start.position, (@end.position - @start.position).normalize]; end
    def other_vertex(v) v == @start ? @end : @start end
    def used_by?(o) vertices.include?(o) || faces.include?(o) end
    def curve; nil; end
    def soft?; @soft; end
    def smooth?; @smooth; end
    def bounds; Geom::BoundingBox.new.add(@start.position, @end.position); end
    def find_faces; @ents ? @ents.find_faces_for(self) : 0; end

    # divide a aresta num ponto (o vértice se junta a outro que já esteja ali)
    def split(pt)
      pt = Geom::Point3d.new(pt.to_a)
      v = @ents.vertex_at(pt)
      old_end = @end
      @end.edges_list.delete(self)
      @end = v
      v.edges_list << self
      @ents.add_edge_v(v, old_end)
    end

    def reversed_in?(face)
      vs = face.outer_loop.vertices
      i = vs.index(@start)
      i && vs[(i + 1) % vs.size] != @end
    end
  end

  class Loop < Entity
    attr_reader :vertices
    def initialize(vs, outer, face) super(); @vertices = vs; @outer = outer; @face = face end
    def outer?; @outer; end
    def face; @face; end
    def edges; @vertices.each_with_index.map { |v, i| @face.ents.edge_between(v, @vertices[(i + 1) % @vertices.size]) }.compact; end
    def convex?; true; end
  end

  class Face < Drawingelement
    attr_accessor :back_material
    PointUnknown = 0; PointInside = 1; PointOnVertex = 2; PointOnEdge = 4; PointOutside = 16; PointNotOnPlane = 32

    def self.newell(pts)
      n = Geom::Vector3d.new(0, 0, 0)
      pts.each_with_index do |a, i|
        b = pts[(i + 1) % pts.size]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
      end
      n
    end

    def initialize(ents, verts)
      super()
      @ents = ents
      @outer = Loop.new(verts, true, self)
      @inner = []
      @uv = nil
    end

    def outer_loop; check!; @outer; end
    def loops; check!; [@outer] + @inner; end
    def inner_loops; @inner; end
    def add_inner(vs)
      ring = vs.map(&:position)
      vs = vs.reverse if Face.newell(ring).dot(Face.newell(pts)) > 0 # furo gira ao contrário do contorno
      @inner << Loop.new(vs, false, self)
      vs.each_with_index { |v, i| e = @ents.add_edge_v(v, vs[(i + 1) % vs.size]); e.faces_list << self unless e.faces_list.include?(self) }
    end
    def vertices; check!; loops.flat_map(&:vertices); end
    def edges; check!; loops.flat_map(&:edges).uniq; end
    def pts(loop = @outer) loop.vertices.map(&:position) end
    def normal; check!; Face.newell(pts).normalize; end
    def plane; n = normal; p = pts[0]; [n.x, n.y, n.z, -(n.x * p.x + n.y * p.y + n.z * p.z)]; end
    def bounds; Geom::BoundingBox.new.add(pts); end
    def uv_data; @uv; end

    def area(t = nil)
      check!
      a = ->(ps) { Face.newell(ps).length / 2.0 }
      pp = ->(l) { t ? pts(l).map { |q| q.transform(t) } : pts(l) }
      a.call(pp.call(@outer)) - @inner.sum { |l| a.call(pp.call(l)) }
    end

    def reverse!
      check!
      @outer = Loop.new(@outer.vertices.reverse, true, self)
      @inner = @inner.map { |l| Loop.new(l.vertices.reverse, false, self) }
      self
    end

    def position_material(mat, pts, front = true)
      raise ArgumentError, 'pares de pontos inválidos' unless [2, 4, 6, 8].include?(pts.size)
      raise ArgumentError, 'material inválido' unless mat.is_a?(Material)
      front ? self.material = mat : self.back_material = mat
      @uv = pts
      self
    end

    # posição do ponto em relação à face
    def classify_point(p)
      p = Geom::Point3d.new(p.to_a)
      return PointNotOnPlane unless p.on_plane?(plane)
      return PointOnVertex if vertices.any? { |v| v.position == p }
      ax = Sketchup.plane_axes(normal)
      to2 = ->(q) { d = q - pts[0]; Geom::Point3d.new(d.dot(ax[0]), d.dot(ax[1]), 0) }
      on_edge = loops.any? do |l|
        ps = pts(l)
        ps.each_with_index.any? do |a, i|
          b = ps[(i + 1) % ps.size]
          ab = b - a
          t = (p - a).dot(ab) / ab.dot(ab)
          t >= -1e-9 && t <= 1 + 1e-9 && a.offset(ab, ab.length * t).distance(p) < TOL
        end
      end
      return PointOnEdge if on_edge
      q = to2.call(p)
      inside = Geom.point_in_polygon_2D(q, pts.map { |x| to2.call(x) }, false) &&
               @inner.none? { |l| Geom.point_in_polygon_2D(q, pts(l).map { |x| to2.call(x) }, false) }
      inside ? PointInside : PointOutside
    end

    # Empurrar/puxar: cria a face de cima (mesmo sentido) e as laterais; a original vira a base
    def pushpull(d, copy = false)
      check!
      n = normal
      off = Geom::Vector3d.new(n.x * d, n.y * d, n.z * d)
      ents = @ents
      top_pts = pts.map { |q| q + off }
      # face solta fica como base; face recortada dentro de outra (vão na parede) se move junto
      free = edges.all? { |e| e.faces.size == 1 }
      # laterais olhando para fora do sólido: contorno anti-horário em volta da normal → fora = aresta × normal
      side = lambda do |ring|
        ring.each_with_index do |a, i|
          b = ring[(i + 1) % ring.size]
          f = ents.add_face(a, b, b + off, a + off)
          next unless f
          out = (b - a).cross(n)
          f.reverse! if f.normal.dot(out) < 0
          f.material = material
        end
      end
      side.call(pts)
      @inner.each { |l| side.call(pts(l)) }
      # tampa chegando numa face do outro lado (atravessou a parede): vira furo nela
      through = ents.to_a.grep(Face).find do |g|
        !g.equal?(self) && g.normal.parallel?(n) && top_pts.all? { |q| q.on_plane?(g.plane) } &&
          top_pts.all? { |q| [PointInside, PointOnEdge, PointOnVertex].include?(g.classify_point(q)) } &&
          top_pts.any? { |q| g.classify_point(q) == PointInside || g.area > Face.newell(top_pts).length / 2 * 1.001 }
      end
      if through
        through.add_inner(top_pts.map { |q| ents.vertex_at(q) })
        top = nil
      else
        top = ents.add_face(top_pts)
        @inner.each { |l| top.add_inner(pts(l).map { |q| ents.vertex_at(q + off) }) } if top
        top.reverse! if top && top.normal.dot(off) < 0 # a tampa olha para fora do sólido
        top.material = material if top
      end
      if free
        reverse! if d > 0 && !copy
      else
        erase!
      end
      nil
    end

    def followme(*_a) true end
    def get_UVHelper(*_a) nil end
    def mesh(*_a) nil end
  end

  module Sketchup_plane_axes; end

  def self.plane_axes(n)
    z = n.normalize
    x = z.parallel?(Z_AXIS) ? X_AXIS.clone : Z_AXIS.cross(z).normalize
    [x, z.cross(x).normalize, z]
  end

  class Text < Drawingelement
    attr_accessor :text, :point, :vector, :leader_type, :arrow_type, :display_leader, :line_weight
    def initialize(t, p, v) super(); @text = t; @point = p; @vector = v end
    def bounds; Geom::BoundingBox.new.add(@point); end
  end

  class Dimension < Drawingelement
    attr_accessor :text, :arrow_type, :has_aligned_text
    def bounds; Geom::BoundingBox.new.add(@pts || [ORIGIN]); end
  end

  class DimensionLinear < Dimension
    attr_reader :start, :end, :offset_vector
    def initialize(a, b, v) super(); @start = [nil, a]; @end = [nil, b]; @offset_vector = v; @pts = [a, b] end
    def length; @pts[0].distance(@pts[1]); end
    def offset_vector=(v) @offset_vector = v end
  end

  class ConstructionPoint < Drawingelement
    attr_reader :position
    def initialize(p) super(); @position = p end
    def bounds; Geom::BoundingBox.new.add(@position); end
  end

  class ConstructionLine < Drawingelement
    attr_accessor :start, :end, :position, :direction, :stipple
    def initialize(a, b) super(); @start = a; @end = b; @position = a; @direction = b.is_a?(Geom::Vector3d) ? b : (b - a) end
    def bounds; Geom::BoundingBox.new.add(@position); end
  end

  class SectionPlane < Drawingelement
    attr_accessor :name, :symbol
    def initialize(plane) super(); @plane = plane; @active = false end
    def get_plane; pt, n = Geom.plane_pn(@plane); [n.x, n.y, n.z, -(n.x * pt.x + n.y * pt.y + n.z * pt.z)] end
    def set_plane(p) @plane = p; self end
    def activate; @ents.active_section_plane = self if @ents; self end
    def active?; @ents && @ents.active_section_plane == self end
    def bounds; Geom::BoundingBox.new.add(Geom.plane_pn(@plane)[0]); end
  end

  class ComponentDefinition < Entity
    attr_accessor :name, :description, :behavior_obj, :insertion_point
    attr_reader :entities, :instances_list

    def initialize(name, group = false)
      super()
      @name = name
      @group = group
      @entities = Entities.new(self)
      @instances_list = []
      @description = ''
      @insertion_point = ORIGIN
    end

    def group?; @group; end
    def image?; false; end
    def internal?; false; end
    def instances; @instances_list.select(&:valid?); end
    def count_instances; instances.size; end
    def count_used_instances; instances.size; end
    def bounds; @entities.bounds; end
    def behavior; @behavior_obj ||= Behavior.new; end
    def save_as(path) File.write(path, 'skp simulado'); true end

    def save_thumbnail(path)
      File.binwrite(path, "\x89PNG\r\n\x1a\nsimulado".b)
      true
    end

    def refresh_thumbnail; true; end
    def path; ''; end
    def live_component?; false; end
    def guid; "def-#{entityID}"; end
  end

  class Behavior
    attr_accessor :always_face_camera, :cuts_opening, :is2d, :snapto, :no_scale_mask, :shadows_face_sun
    def cuts_opening?; @cuts_opening; end
  end

  class ComponentInstance < Drawingelement
    attr_accessor :name, :locked, :glued_to
    attr_reader :definition

    def initialize(defn, tr)
      super()
      @definition = defn
      @transformation = tr
      @name = ''
      defn.instances_list << self
    end

    def transformation; @transformation; end
    def transformation=(t) @transformation = t end
    def definition=(d) @definition.instances_list.delete(self); @definition = d; d.instances_list << self end
    def transform!(t) @transformation = t * @transformation; self end
    def move!(t) @transformation = t; self end
    def entities; @definition.entities; end
    def bounds; @definition.entities.bounds(@transformation); end
    def locked?; !!@locked; end
    def guid; "inst-#{entityID}"; end

    def make_unique
      return self if @definition.instances.size <= 1
      d = Sketchup.active_model.definitions.copy_of(@definition)
      @definition.instances_list.delete(self)
      @definition = d
      d.instances_list << self
      self
    end

    def explode
      ents = @ents
      out = []
      definition.entities.to_a.each do |e|
        out << ents.copy_entity(e, @transformation)
      end
      erase!
      out.compact
    end

    def copy
      @ents.add_instance(@definition, @transformation).tap { |c| c.material = material; c.layer = layer }
    end

    def intersect(_o) nil end
    def manifold?; definition.entities.manifold?; end
    def volume; manifold? ? definition.entities.volume.abs : -1; end
  end

  class Group < ComponentInstance
    def initialize(defn, tr) super(defn, tr) end
    def copy; @ents.copy_entity(self, IDENTITY); end
    def entities; make_unique; definition.entities; end
    def group?; true; end
  end

  class Image < Drawingelement; end

  # ---- coleção de entidades --------------------------------------------------
  class Entities
    include Enumerable
    attr_reader :owner, :active_section_plane

    def initialize(owner)
      @owner = owner
      @items = []
      @verts = {}
      @fhash = {}
      @planes = Hash.new { |h, k| h[k] = [] }
    end

    def vkey(p) p.to_a.map { |v| (v / TOL).round } end

    def model_ref; Sketchup.active_model; end
    def parent; @owner; end
    def model; Sketchup.active_model; end
    def each(&b) @items.select(&:valid?).each(&b) end
    def to_a; @items.select(&:valid?); end
    def size; to_a.size; end
    alias length size
    alias count_items size
    def [](i) to_a[i] end
    def empty?; to_a.empty?; end
    def active_section_plane=(s) @active_section_plane = s end

    def remove_entity(e)
      @items.delete(e)
      if e.is_a?(Edge)
        e.faces.each { |f| f.kill! }
      end
      if e.is_a?(Face)
        # furos ficam: só some a face
      end
    end

    def vertex_at(p)
      p = Geom::Point3d.new(p.to_a)
      k = vkey(p)
      v = @verts[k]
      return v if v && v.valid?
      v = Vertex.new(p)
      v.ents = self
      @verts[k] = v
      v
    end

    def edge_between(a, b)
      a.edges.find { |e| e.ents == self && (e.other_vertex(a) == b) }
    end

    def add_edge_v(a, b)
      e = edge_between(a, b)
      return e if e
      e = Edge.new(a, b)
      e.ents = self
      @items << e
      e
    end

    def add_line(a, b)
      a = Geom::Point3d.new(a.to_a); b = Geom::Point3d.new(b.to_a)
      raise ArgumentError, 'linha com comprimento zero' if a == b
      add_edge_v(vertex_at(a), vertex_at(b))
    end

    def add_edges(*pts)
      pts = pts.flatten.map { |p| Geom::Point3d.new(p.to_a) }
      pts.each_cons(2).map { |a, b| a == b ? nil : add_line(a, b) }.compact
    end

    def add_curve(*pts) add_edges(*pts) end

    def add_circle(c, n, r, segs = 24)
      ax = Sketchup.plane_axes(Geom::Vector3d.new(n.to_a))
      pts = (0..segs).map do |i|
        a = 2 * Math::PI * i / segs
        Geom::Point3d.new(c.to_a).offset(ax[0], r * Math.cos(a)).offset(ax[1], r * Math.sin(a))
      end
      add_edges(pts)
    end

    def add_arc(c, xaxis, n, r, a0, a1, segs = 12)
      ax_y = Geom::Vector3d.new(n.to_a).cross(Geom::Vector3d.new(xaxis.to_a)).normalize
      xa = Geom::Vector3d.new(xaxis.to_a).normalize
      pts = (0..segs).map do |i|
        a = a0 + (a1 - a0) * i / segs
        Geom::Point3d.new(c.to_a).offset(xa, r * Math.cos(a)).offset(ax_y, r * Math.sin(a))
      end
      add_edges(pts)
    end

    def add_ngon(c, n, r, segs = 24) add_circle(c, n, r, segs) end

    def add_face(*args)
      args = args[0] if args.size == 1 && args[0].is_a?(Array) && !args[0][0].is_a?(Numeric)
      if args.all? { |a| a.is_a?(Edge) }
        vs = []
        args.each { |e| vs << e.start.position; }
        args = vs
      end
      pts = args.map { |p| Geom::Point3d.new(p.to_a) }
      pts = pts.each_with_object([]) { |p, acc| acc << p unless acc.last == p }
      pts.pop while pts.size > 1 && pts.last == pts.first
      raise ArgumentError, 'Points are not planar' unless planar?(pts)
      raise ArgumentError, 'Duplicate points in array' if pts.uniq { |p| p.to_a.map { |v| v.round(3) } }.size != pts.size
      raise ArgumentError, 'Not enough points' if pts.size < 3
      raise ArgumentError, 'Points are collinear' if Face.newell(pts).length < 1e-8
      vs = pts.map { |p| vertex_at(p) }
      fk = pts.map { |q| vkey(q) }.sort
      existing = @fhash[fk]
      return existing if existing && existing.valid?
      f = Face.new(self, vs)
      @items << f
      @fhash[fk] = f
      vs.each_with_index do |v, i|
        e = add_edge_v(v, vs[(i + 1) % vs.size])
        e.faces_list << f
      end
      # face nova dentro de outra coplanar: vira furo nela (como no SketchUp)
      n = f.normal
      n = n.reverse if n.x + n.y * 1e-3 + n.z * 1e-6 < 0
      pk = (n.to_a + [n.dot(Geom::Vector3d.new(pts[0].to_a))]).map { |v| v.round(3) }
      fb = f.bounds
      @planes[pk].each do |g|
        next if g.equal?(f) || !g.valid?
        gb = g.bounds
        next unless gb.contains?(fb.min) && gb.contains?(fb.max)
        cls = pts.map { |p| g.classify_point(p) }
        next unless cls.all? { |c| c != Face::PointOutside } && cls.include?(Face::PointInside)
        g.add_inner(vs)
      end
      @planes[pk] << f
      f
    end

    def touches_none?(g, f)
      (g.outer_loop.vertices & f.outer_loop.vertices).empty?
    end

    def planar?(pts)
      return true if pts.size <= 3
      n = Face.newell(pts)
      return false if n.length < 1e-10
      n.normalize!
      pts.all? { |p| ((p - pts[0]).dot(n)).abs < 1e-3 }
    end

    # menor ciclo de arestas que passa pela aresta e está num plano → vira face (como o SketchUp faz)
    def find_faces_for(edge)
      a = edge.start
      b = edge.end
      prev = { b => nil }
      queue = [b]
      until queue.empty? || prev.key?(a)
        v = queue.shift
        v.edges.each do |e|
          next if e.equal?(edge) || e.ents != self
          w = e.other_vertex(v)
          next if prev.key?(w)
          prev[w] = v
          queue << w
        end
      end
      return 0 unless prev.key?(a)
      ring = [a]
      ring << prev[ring.last] while prev[ring.last]
      pts = ring.map(&:position)
      return 0 if pts.size < 3 || !planar?(pts)
      before = to_a.grep(Face).size
      add_face(pts) rescue nil
      to_a.grep(Face).size - before
    end

    def add_group(*ents)
      d = model_ref.definitions.new_group_def
      g = Group.new(d, Geom::Transformation.new)
      g.ents = self
      @items << g
      ents.flatten.each do |e|
        next unless e.valid?
        d.entities.copy_entity(e, Geom::Transformation.new)
        e.erase!
      end
      g
    end

    def add_instance(defn, tr)
      tr = Geom::Transformation.new(tr) unless tr.is_a?(Geom::Transformation)
      raise ArgumentError, 'definição inválida' unless defn.is_a?(ComponentDefinition)
      i = ComponentInstance.new(defn, tr)
      i.ents = self
      @items << i
      (@observers || []).each { |o| o.onElementAdded(self, i) if o.respond_to?(:onElementAdded) }
      i
    end

    def add_observer(o) (@observers ||= []) << o; true end
    def remove_observer(o) (@observers || []).delete(o); true end

    def add_text(t, p, v = nil)
      x = Text.new(t, p, v)
      x.ents = self
      @items << x
      x
    end

    def add_3d_text(str, _align, _font, _bold = false, _ital = false, h = 1.0, _tol = 0, z = 0.0, filled = true, ext = 0.0)
      raise ArgumentError, 'texto vazio' if str.to_s.empty?
      w = h * 0.6
      str.to_s.each_char.with_index do |ch, i|
        next if ch =~ /\s/
        x = i * w
        f = add_face([x, 0, z], [x + w * 0.8, 0, z], [x + w * 0.8, h, z], [x, h, z]) if filled
        f.pushpull(ext) if f && ext.to_f.abs > 0
      end
      true
    end

    def add_dimension_linear(a, b, v)
      a = a.is_a?(Array) && a.size == 2 && !a[0].is_a?(Numeric) ? a[1] : a
      b = b.is_a?(Array) && b.size == 2 && !b[0].is_a?(Numeric) ? b[1] : b
      d = DimensionLinear.new(Geom::Point3d.new(a.to_a), Geom::Point3d.new(b.to_a), Geom::Vector3d.new(v.to_a))
      d.ents = self
      @items << d
      d
    end

    def add_cpoint(p) c = ConstructionPoint.new(Geom::Point3d.new(p.to_a)); c.ents = self; @items << c; c end
    def add_cline(a, b) c = ConstructionLine.new(Geom::Point3d.new(a.to_a), b); c.ents = self; @items << c; c end

    def add_section_plane(*plane)
      plane = plane.size == 1 ? plane[0] : plane
      s = SectionPlane.new(plane)
      s.ents = self
      @items << s
      s
    end

    def add_image(path, pt, w, h = nil) raise ArgumentError, 'imagem não existe' unless File.exist?(path); i = Image.new; i.ents = self; @items << i; i end
    def fill_from_mesh(*_a) true end
    def add_faces_from_mesh(*_a) 0 end

    def clear!; to_a.each { |e| e.erase! if e.valid? }; true end

    def erase_entities(*ents)
      ents.flatten.each { |e| e.erase! if e.valid? }
      nil
    end

    def transform_entities(t, *ents)
      ents.flatten.each do |e|
        if e.is_a?(ComponentInstance)
          e.transform!(t)
        else
          vs = e.respond_to?(:vertices) ? e.vertices : []
          vs.each { |v| v.set_position(v.position.transform(t)) }
        end
      end
      true
    end

    def transform_by_vectors(ents, vecs)
      ents.each_with_index { |v, i| v.set_position(v.position + vecs[i]) if v.is_a?(Vertex) }
      @verts = @verts.values.select(&:valid?).map { |v| [vkey(v.position), v] }.to_h
      true
    end

    def intersect_with(*_a) [] end
    def weld(edges) edges end

    def copy_entity(e, t)
      case e
      when Face
        f = add_face(e.outer_loop.vertices.map { |v| v.position.transform(t) })
        e.inner_loops.each { |l| f.add_inner(l.vertices.map { |v| vertex_at(v.position.transform(t)) }) } if f
        f.material = e.material if f
        f
      when Edge then add_line(e.start.position.transform(t), e.end.position.transform(t))
      when Group
        g = add_group
        g.definition.entities.instance_variable_set(:@items, [])
        e.definition.entities.to_a.each { |x| g.definition.entities.copy_entity(x, IDENTITY) }
        g.transformation = t * e.transformation
        g.name = e.name; g.material = e.material; g.layer = e.layer
        g
      when ComponentInstance
        i = add_instance(e.definition, t * e.transformation)
        i.material = e.material; i.layer = e.layer
        i
      when Text then add_text(e.text, e.point.transform(t), e.vector)
      when ConstructionPoint then add_cpoint(e.position.transform(t))
      else nil
      end
    end

    def bounds(t = IDENTITY)
      b = Geom::BoundingBox.new
      each do |e|
        case e
        when Face, Edge then b.add(e.vertices.map { |v| v.position.transform(t) })
        when ComponentInstance then b.add(e.definition.entities.bounds(t * e.transformation)) unless e.definition.entities.bounds.empty?
        when Text, ConstructionPoint then b.add(e.bounds.min.transform(t))
        end
      end
      b
    end

    # malha fechada: toda aresta com exatamente 2 faces
    def manifold?
      es = to_a.grep(Edge)
      !es.empty? && es.all? { |e| e.faces.size == 2 }
    end

    def volume
      to_a.grep(Face).sum do |f|
        p = f.outer_loop.vertices.map(&:position)
        n = f.normal
        f.area * (p[0].x * n.x + p[0].y * n.y + p[0].z * n.z) / 3.0
      end
    end

    def grep(k) to_a.grep(k) end
  end

  # ---- coleções do modelo ----------------------------------------------------
  class Material < Entity
    attr_accessor :name, :alpha, :colorize_type
    attr_reader :color, :texture

    def initialize(n) super(); @name = n; @color = Color.new(200, 200, 200); @alpha = 1.0 end
    def display_name; @name; end
    def color=(c) @color = c.is_a?(Color) ? c : Color.new(c) end
    def use_alpha?; @alpha < 1.0; end
    def materialType; @texture ? 1 : 0; end

    def texture=(f)
      raise ArgumentError, "imagem não encontrada: #{f}" if f && !File.exist?(f.to_s)
      @texture = f && Texture.new(f.to_s)
    end
  end

  class Texture
    attr_reader :filename
    attr_accessor :width, :height
    def initialize(f) @filename = f; @width = @height = 100 end
    def size=(v) @width, @height = v.is_a?(Array) ? v : [v, v] end
    def size; [@width, @height]; end
    def image_width; 512; end
    def image_height; 512; end
    def valid?; true; end
  end

  class Materials
    include Enumerable
    def initialize; @list = []; @current = nil end
    def each(&b) @list.each(&b) end
    def size; @list.size; end
    alias length size
    alias count size
    def [](k) k.is_a?(Integer) ? @list[k] : @list.find { |m| m.name == k.to_s } end

    def add(n)
      n = n.to_s
      base = n; i = 1
      n = "#{base}#{i += 1}" while self[n]
      m = Material.new(n)
      @list << m
      m
    end

    def add_color(c) m = add("Cor_#{c}"); m.color = c; m end
    def current; @current; end
    def current=(m) @current = m end
    def remove(m) @list.delete(m); true end

    def purge_unused
      used = Sketchup.active_model.used_materials
      @list.select! { |m| used.include?(m) }
      self
    end
  end

  class Layer < Entity
    attr_accessor :name, :color, :page_behavior, :line_style
    def initialize(n) super(); @name = n; @visible = true end
    def visible?; @visible; end
    def visible=(v) @visible = v end
    def display_name; @name; end
    def folder; nil; end
  end

  class Layers
    include Enumerable
    def initialize; @list = [Layer.new('Layer0')]; end
    def each(&b) @list.each(&b) end
    def size; @list.size; end
    alias length size
    alias count size
    def [](k) k.is_a?(Integer) ? @list[k] : @list.find { |l| l.name == k.to_s } end
    def add(n) self[n] || (@list << Layer.new(n.to_s)).last end
    def add_layer(n) add(n) end
    def remove(l, *_a) @list.delete(l == @list[0] ? nil : l); true end
    def purge; used = Sketchup.active_model.used_layers; @list.select! { |l| l == @list[0] || used.include?(l) }; self end
    def purge_unused; purge; end
    def unique_name(n) n end
  end

  class Definitions
    include Enumerable
    def initialize; @list = []; end
    def each(&b) @list.each(&b) end
    def size; @list.size; end
    alias length size
    alias count size
    def [](k) k.is_a?(Integer) ? @list[k] : @list.find { |d| d.name == k.to_s } end
    def add(n) d = ComponentDefinition.new(unique(n.to_s)); @list << d; d end
    def new_group_def; d = ComponentDefinition.new("Grupo##{@list.size + 1}", true); @list << d; d end

    def unique(n)
      return n unless self[n]
      i = 1
      i += 1 while self["#{n}##{i}"]
      "#{n}##{i}"
    end

    def copy_of(d)
      c = ComponentDefinition.new(unique(d.name), d.group?)
      d.entities.to_a.each { |e| c.entities.copy_entity(e, IDENTITY) }
      @list << c
      c
    end

    def load(path) raise IOError, "arquivo não existe: #{path}" unless File.exist?(path); add(File.basename(path, '.skp')) end
    def purge_unused; @list.select! { |d| d.instances.any? || d.group? && d.instances.any? }; self end
    def remove(d) @list.delete(d); true end
  end

  class Camera
    attr_reader :eye, :target, :up
    attr_accessor :fov, :height, :aspect_ratio, :focal_length

    def initialize(eye = Geom::Point3d.new(-500, -500, 300), target = ORIGIN, up = Z_AXIS, persp = true, fov = 35.0)
      set(eye, target, up)
      @persp = persp
      @fov = fov.to_f
      @height = 1000
      @aspect_ratio = 0
    end

    def set(eye, target, up)
      @eye = Geom::Point3d.new(eye.to_a); @target = Geom::Point3d.new(target.to_a); @up = Geom::Vector3d.new(up.to_a)
      raise ArgumentError, 'olho e alvo iguais' if @eye == @target
      self
    end

    def direction; (@target - @eye).normalize; end
    def perspective?; @persp; end
    def perspective=(v) @persp = v end
    def xaxis; direction.cross(@up).normalize; end
    def yaxis; xaxis.cross(direction).normalize; end
    def zaxis; direction.reverse; end
    def is_2d?; false; end
  end

  class View
    attr_reader :model, :images
    attr_accessor :drawing_color, :line_width, :line_stipple, :tooltip

    def initialize(m) @model = m; @camera = Camera.new; @images = []; @vpw = 1600; @vph = 900 end
    def camera; @camera; end

    def camera=(c)
      c = c[0] if c.is_a?(Array)
      raise ArgumentError, 'câmera inválida' unless c.is_a?(Camera)
      @camera = c
    end

    def vpwidth; @vpw; end
    def vpheight; @vph; end
    def set_viewport(w, h) @vpw = w; @vph = h end
    def invalidate; self; end
    def refresh; self; end
    def zoom_extents; self; end
    def zoom(*_a) self; end
    def pixels_to_model(px, _pt) px * 0.5 end
    def pick_helper; PickHelper.new; end
    def guess_target; ORIGIN; end
    def field_of_view; @camera.fov; end
    def field_of_view=(v) @camera.fov = v end
    def draw(*_a) end
    def draw2d(*_a) end
    def draw_points(*_a) end
    def draw_line(*_a) end
    def draw_text(*_a) end
    def screen_coords(p) p end
    def lock_inference(*_a) end

    def write_image(*a)
      o = a[0].is_a?(Hash) ? a[0] : { filename: a[0], width: a[1], height: a[2] }
      f = o[:filename] || o['filename']
      raise ArgumentError, 'sem nome de arquivo' unless f
      raise ArgumentError, 'pasta não existe' unless File.directory?(File.dirname(f))
      File.binwrite(f, "imagem simulada #{o[:width]}x#{o[:height]}")
      @images << o.merge(page: @model.pages.selected_page && @model.pages.selected_page.name)
      true
    end
  end

  class PickHelper
    def do_pick(*_a) 0 end
    def count; 0; end
    def picked_face; nil; end
    def path_at(_i) nil end
    def transformation_at(_i) IDENTITY end
  end

  class Page < Entity
    attr_accessor :name, :description, :transition_time, :delay_time, :use_camera, :use_section_planes,
                  :use_hidden_layers, :use_rendering_options, :use_style, :use_hidden, :use_axes, :use_shadow_info, :label
    attr_reader :camera, :layers_state, :section_on

    def initialize(m, name)
      super()
      @model = m
      @name = name
      @layers_state = {}
      capture
    end

    def capture
      @camera = @model.active_view.camera.dup
      @section_on = @model.active_entities.active_section_plane
      @rendering = @model.rendering_options.to_h.dup
      @layers_state = @model.layers.map { |l| [l.name, l.visible?] }.to_h
    end

    def update(_flags = 127) capture; true end
    def layers; @model.layers.select { |l| @layers_state[l.name] == false }; end
    def set_visibility(l, v) @layers_state[l.name] = v; self end
    def rendering_options; @rendering; end
    def style; nil; end
    def hidden_entities; []; end
    def include_in_animation?; true; end
    def include_in_animation=(_v) end
  end

  class Pages
    include Enumerable
    attr_reader :selected_page
    def initialize(m) @m = m; @list = []; @selected_page = nil end
    def each(&b) @list.each(&b) end
    def size; @list.size; end
    alias length size
    alias count size
    def to_a; @list.dup; end
    def [](k) k.is_a?(Integer) ? @list[k] : @list.find { |p| p.name == k.to_s } end

    def add(name = nil, _flags = 127, index = -1)
      name ||= "Cena #{@list.size + 1}"
      raise ArgumentError, "já existe uma cena #{name}" if self[name]
      pg = Page.new(@m, name)
      index == -1 ? @list << pg : @list.insert(index, pg)
      @selected_page = pg
      pg
    end

    def selected_page=(pg)
      raise ArgumentError, 'cena inválida' unless @list.include?(pg)
      @selected_page = pg
      @m.active_view.camera = pg.camera
      @m.active_entities.active_section_plane = pg.section_on
    end

    def erase(pg) @list.delete(pg); @selected_page = @list.first if @selected_page == pg; true end
    def add_observer(*_a) true end
  end

  class Selection
    include Enumerable
    def initialize; @list = []; end
    def each(&b) @list.select(&:valid?).each(&b) end
    def to_a; @list.select(&:valid?); end
    def size; to_a.size; end
    alias length size
    alias count size
    def empty?; to_a.empty?; end
    def first; to_a.first; end
    def [](i) to_a[i] end
    def add(*e) e.flatten.each { |x| @list << x unless @list.include?(x) }; size end
    def remove(*e) e.flatten.each { |x| @list.delete(x) }; size end
    def toggle(*e) e.flatten.each { |x| @list.include?(x) ? @list.delete(x) : @list << x }; size end
    def clear; @list.clear; self; end
    def include?(e) @list.include?(e) end
    def contains?(e) include?(e) end
    def single_object?; size == 1; end
    def is_curve?; false; end
    def grep(k) to_a.grep(k) end
  end

  class OptionsProvider
    def initialize(h) @h = h end
    def [](k) @h[k] end
    def []=(k, v) @h[k] = v end
    def each(&b) @h.each(&b) end
    def keys; @h.keys; end
    def to_h; @h; end
    def key?(k) @h.key?(k) end
    def has_key?(k) @h.key?(k) end
  end

  class OptionsManager
    def initialize
      @o = {
        'UnitsOptions' => OptionsProvider.new('LengthUnit' => 3, 'LengthFormat' => 0, 'LengthPrecision' => 1),
        'PageOptions' => OptionsProvider.new('ShowTransition' => true, 'TransitionTime' => 2.0),
        'PrintOptions' => OptionsProvider.new({}), 'NamedOptions' => OptionsProvider.new({}), 'SlideshowOptions' => OptionsProvider.new({})
      }
    end
    def [](k) @o[k] end
  end

  class RenderingOptions < OptionsProvider; end

  class Styles
    include Enumerable
    def initialize; @l = []; end
    def each(&b) @l.each(&b) end
    def size; @l.size; end
    def selected_style; nil; end
    def active_style; nil; end
    def add_style(*_a) true end
    def update_selected_style; true end
  end

  class Overlays
    include Enumerable
    def initialize; @l = []; end
    def each(&b) @l.each(&b) end
    def add(o) @l << o; true end
    def remove(o) @l.delete(o); true end
    def size; @l.size; end
  end

  class Overlay
    attr_accessor :enabled, :name, :overlay_id, :description
    def initialize(id, name, description: '') @overlay_id = id; @name = name; @description = description; @enabled = false end
    def enabled?; @enabled; end
    def valid?; true; end
  end

  class ShadowInfo < OptionsProvider; end

  class InputPoint
    attr_reader :position
    def initialize(p = nil) @position = p end
    def pick(*_a) false end
    def valid?; !!@position; end
    def copy!(o) @position = o.position; self end
    def draw(*_a) end
    def tooltip; ''; end
    def display?; false; end
    def face; nil; end
    def edge; nil; end
    def vertex; nil; end
    def transformation; IDENTITY; end
    def degrees_of_freedom; 3; end
    def clear; @position = nil; end
  end

  class Model
    attr_reader :entities, :materials, :layers, :definitions, :pages, :selection, :active_view, :options,
                :rendering_options, :styles, :overlays, :shadow_info, :tool, :ops
    attr_accessor :title, :path, :active_layer

    def initialize
      @entities = Entities.new(self)
      @materials = Materials.new
      @layers = Layers.new
      @definitions = Definitions.new
      @selection = Selection.new
      @active_view = View.new(self)
      @pages = Pages.new(self)
      @options = OptionsManager.new
      @rendering_options = RenderingOptions.new('SectionCutFilled' => false, 'DisplaySectionPlanes' => true, 'DisplaySectionCuts' => true, 'EdgeColorMode' => 1)
      @styles = Styles.new
      @overlays = Overlays.new
      @shadow_info = ShadowInfo.new('DisplayShadows' => false)
      @ops = []
      @open_ops = 0
      @title = 'Modelo de teste'
      @path = ''
      @dicts = {}
    end

    def active_entities; @entities; end
    def active_path; nil; end
    def active_path=(_p) end
    def tools; self; end
    def guid; "modelo-#{object_id}"; end
    def bounds; @entities.bounds; end
    def valid?; true; end
    def name; @title; end
    def modified?; true; end

    def start_operation(name, *_a)
      raise 'operação aninhada sem fechar' if @open_ops > 0 && ENV['STRICT_OPS']
      @open_ops += 1
      @ops << [name, :aberta]
      true
    end

    def commit_operation; @open_ops -= 1; @ops[-1][1] = :ok if @ops.any?; true end
    def abort_operation; @open_ops -= 1; @ops[-1][1] = :desfeita if @ops.any?; true end
    def open_ops; @open_ops; end

    def select_tool(t)
      @tool = t
      t.activate if t && t.respond_to?(:activate)
      true
    end

    def find_entity_by_persistent_id(*ids)
      ids = ids.flatten
      found = ids.map { |id| all_entities.find { |e| e.persistent_id == id.to_i && e.valid? } }
      ids.size == 1 ? found[0] : found
    end

    def find_entity_by_id(id) all_entities.find { |e| e.entityID == id } end

    def all_entities(ents = @entities, out = [])
      ents.to_a.each do |e|
        out << e
        out.concat(e.vertices) if e.is_a?(Face) || e.is_a?(Edge)
      end
      @definitions.each { |d| d.entities.to_a.each { |e| out << e; out.concat(e.vertices) if e.respond_to?(:vertices) } } if ents.equal?(@entities)
      out.uniq
    end

    def used_materials
      all_entities.map { |e| e.respond_to?(:material) ? e.material : nil }.compact.uniq
    end

    def used_layers
      all_entities.map { |e| e.respond_to?(:layer) ? e.layer : nil }.compact.uniq
    end

    def set_attribute(d, k, v) (@dicts[d.to_s] ||= {})[k.to_s] = v end
    def get_attribute(d, k, default = nil) h = @dicts[d.to_s]; h && h.key?(k.to_s) ? h[k.to_s] : default end
    def delete_attribute(d, k = nil) k ? (@dicts[d.to_s] || {}).delete(k.to_s) : @dicts.delete(d.to_s) end
    def attribute_dictionary(n, c = false) nil end
    def export(path, *_a) File.write(path, 'export simulado'); true end
    def save(*_a) true end
    def number_faces; all_entities.grep(Face).size; end
    def add_observer(*_a) true end
    def place_component(*_a) true end
    def close_active; true; end
    def classifications; []; end
    def save_thumbnail(path) File.binwrite(path, 'png simulado'); true end
  end

  module Http
    GET = 'GET'
    class Request
      def initialize(u, m) @u = u end
      def start(&b) b.call(self, Response.new(0, '')) end
    end
    Response = Struct.new(:status_code, :body)
  end
end

module UI
  @answers = {}
  @log = []
  class << self
    attr_accessor :answers, :log
  end

  def self.reply(kind, *a)
    v = @answers[kind]
    v.respond_to?(:call) ? v.call(*a) : v
  end

  def self.messagebox(msg, type = MB_OK, *_a)
    @log << [:messagebox, msg]
    r = reply(:messagebox, msg)
    r || (type == MB_YESNO ? IDYES : IDOK)
  end

  def self.inputbox(prompts, defaults = [], *_a)
    @log << [:inputbox, prompts]
    r = reply(:inputbox, prompts, defaults)
    r.nil? ? defaults : r
  end

  def self.openpanel(*a) @log << [:openpanel, a]; reply(:openpanel, *a) end
  def self.savepanel(*a) @log << [:savepanel, a]; reply(:savepanel, *a) end
  def self.select_directory(*a) @log << [:select_directory, a]; reply(:select_directory, *a) end
  def self.openURL(u) @log << [:openURL, u]; true end
  def self.beep; @log << [:beep]; end
  def self.start_timer(*_a, &b) ($timers ||= []) << b; 1 end
  def self.stop_timer(_id) true end
  def self.menu(_n = nil) Menu.new end
  def self.refresh_toolbars; end
  def self.scale_factor; 1.0; end

  class Menu
    def add_submenu(_n) Menu.new end
    def add_item(_n, &_b) 1 end
    def add_separator; end
    def set_validation_proc(*_a) end
  end

  class Toolbar
    attr_reader :items
    def initialize(_n) @items = [] end
    def add_item(c) @items << c end
    def add_separator; end
    def restore; end
    def show; end
  end

  class Command
    attr_accessor :small_icon, :large_icon, :tooltip, :status_bar_text, :menu_text
    def initialize(_n, &b) @b = b end
    def set_validation_proc(*_a) end
  end

  class Notification
    def initialize(*_a) end
    def on_accept(*_a, &_b) end
    def on_dismiss(*_a, &_b) end
    def show; true; end
  end

  class HtmlDialog
    STYLE_DIALOG = 1; STYLE_UTILITY = 2; STYLE_WINDOW = 0
    def initialize(_h) @cb = {}; @vis = false end
    def set_file(f) raise "painel não encontrado: #{f}" unless File.exist?(f); @file = f end
    def set_url(u) @file = u end
    def add_action_callback(n, &b) @cb[n] = b end
    def show; @vis = true; @cb['ready'].call(nil, '') if @cb['ready']; end
    def visible?; @vis end
    def close; @vis = false end
    def bring_to_front; end
    def set_size(*_a) end
    def center; end
    def execute_script(js) $js << js end
    def call(n, a) @cb[n].call(nil, a) end
  end
end

$js = []
