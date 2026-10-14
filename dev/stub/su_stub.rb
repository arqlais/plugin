# Simula o mínimo da API do SketchUp para carregar o plugin e abrir o painel
$loaded = {}
def file_loaded?(f) $loaded[f] end
def file_loaded(f) $loaded[f] = true end
class Numeric; def mm; self/25.4; end; def cm; self/2.54; end; end
class SketchupExtension
  attr_accessor :description, :version, :creator, :copyright
  def initialize(n, path) @n=n; @path=path end
  def load!; require File.join(PLUGINS, @path + '.rb'); end
end
module Sketchup
  @ext = []; @prefs = {}
  def self.register_extension(e, load) @ext << e; e.load! if load; true end
  def self.read_default(s,k,d=nil) @prefs.fetch(k,d) end
  def self.write_default(s,k,v) @prefs[k]=v end
  def self.version; '24.0.0'; end
  def self.active_model; nil; end
end
module UI
  class Menu; def add_submenu(n) Menu.new end; def add_item(n,&b) 1 end; def add_separator; end; end
  def self.menu(n) Menu.new end
  def self.start_timer(*a,&b) ($timers ||= []) << b; 1 end
  def self.messagebox(*a) puts "MSGBOX: #{a[0]}"; 1 end
  class Toolbar; def initialize(n) end; def add_item(c) end; def add_separator; end; def restore; end; end
  class Command; attr_accessor :small_icon,:large_icon,:tooltip,:status_bar_text; def initialize(n,&b) end; end
  class HtmlDialog
    STYLE_DIALOG = 1
    def initialize(h) @cb={} end
    def set_file(f) raise "painel não encontrado: #{f}" unless File.exist?(f); @file=f end
    def add_action_callback(n,&b) @cb[n]=b end
    def show; @vis=true; @cb['ready'].call(nil,'') end
    def visible?; @vis end
    def execute_script(js) $js << js end
    def call(n,a) @cb[n].call(nil,a) end
  end
end
$js = []
