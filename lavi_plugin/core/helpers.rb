# Utilidades comuns: unidades, operações com desfazer, materiais, etiquetas, CSV

require 'json'

module LAVIStudio
  module Plugin
    module Helpers
      PREF = 'LaviPlugin'.freeze
      DICT = 'plane'.freeze
      SQIN_TO_M2 = 0.00064516

      module_function

      def model
        Sketchup.active_model
      end

      # ---- unidades ----------------------------------------------------------
      def mm(v)
        v.to_f.mm
      end

      def cm(v)
        v.to_f.cm
      end

      def to_mm(len)
        len.to_f * 25.4
      end

      def to_cm(len)
        len.to_f * 2.54
      end

      def to_m(len)
        len.to_f * 0.0254
      end

      def m2(area_sq_in)
        area_sq_in.to_f * SQIN_TO_M2
      end

      def num(v, default = 0.0)
        return 1.0 if v == true
        return 0.0 if v == false
        return default if v.nil? || v.to_s.strip.empty?
        v.to_s.tr(',', '.').to_f
      end

      # 1234.5 -> "1.234,50"
      def br(v, dec = 2)
        s = format("%.#{dec}f", v.to_f)
        int, frac = s.split('.')
        neg = int.start_with?('-')
        int = int.delete('-').reverse.scan(/\d{1,3}/).join('.').reverse
        out = (neg ? '-' : '') + int
        dec > 0 ? "#{out},#{frac}" : out
      end

      # ---- operação com um único Ctrl+Z ---------------------------------------
      # tudo numa operação só (um Ctrl+Z desfaz) e com a tela parada enquanto desenha (mais rápido)
      def operation(name)
        m = model
        m.start_operation(name, true)
        @busy = true
        begin
          result = yield
          m.commit_operation
          result
        rescue StandardError => e
          m.abort_operation
          raise e
        ensure
          @busy = false
        end
      end

      # o lavi está desenhando (observadores ignoram o que ele mesmo cria)
      def busy?
        @busy == true
      end

      # ---- preferências --------------------------------------------------------
      def pref(key, default = nil)
        @prefs ||= {}
        return @prefs[key] if @prefs.key?(key)
        @prefs[key] = pref_read(key, default)
      end

      def pref_read(key, default)
        v = Sketchup.read_default(PREF, key.to_s)
        v.nil? ? default : v
      end

      def set_pref(key, value)
        (@prefs ||= {})[key] = value
        Sketchup.write_default(PREF, key.to_s, value)
      end

      def json_pref(key, default)
        JSON.parse(pref(key, JSON.generate(default)).to_s)
      rescue StandardError
        default
      end

      def set_json_pref(key, value)
        set_pref(key, JSON.generate(value))
      end

      def favorites
        json_pref('favorites', %w[scenes export_images room_tags measure])
      end

      def toggle_favorite(id)
        list = favorites
        list.include?(id) ? list.delete(id) : list.push(id)
        set_json_pref('favorites', list)
        list
      end

      # ---- materiais e etiquetas ----------------------------------------------
      def hex_color(hex)
        h = hex.to_s.delete('#')
        Sketchup::Color.new(h[0, 2].to_i(16), h[2, 2].to_i(16), h[4, 2].to_i(16))
      end

      def material(name, hex, alpha = nil)
        mats = model.materials
        mat = mats[name]
        unless mat
          mat = mats.add(name)
          mat.color = hex_color(hex)
          mat.alpha = alpha if alpha
        end
        mat
      end

      def tag(name)
        model.layers[name] || model.layers.add(name)
      end

      # Marca uma entidade criada pelo plugin (usado por quantitativo e etiquetas)
      def mark(ent, kind, data = {})
        ent.set_attribute(DICT, 'kind', kind.to_s)
        data.each { |k, v| ent.set_attribute(DICT, k.to_s, v) }
        ent
      end

      def kind_of(ent)
        ent.get_attribute(DICT, 'kind')
      end

      # ---- seleção ------------------------------------------------------------
      def selection
        model.selection
      end

      def instance?(e)
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end

      def entities_of(e)
        e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
      end

      # Faces selecionadas (direto ou dentro de UM grupo/componente selecionado),
      # com a transformação para coordenadas do modelo.
      def selected_faces
        sel = selection.to_a
        faces = sel.grep(Sketchup::Face).map { |f| [f, IDENTITY] }
        if faces.empty?
          sel.select { |e| instance?(e) }.each do |inst|
            entities_of(inst).grep(Sketchup::Face).each { |f| faces << [f, inst.transformation] }
          end
        end
        faces
      end

      def horizontal?(face, tr = IDENTITY)
        n = face.normal.transform(tr)
        n.normalize!
        n.z.abs > 0.98
      end

      def vertical?(face, tr = IDENTITY)
        n = face.normal.transform(tr)
        n.normalize!
        n.z.abs < 0.02
      end

      # Percorre todas as faces visíveis do modelo com a transformação acumulada
      def each_face(ents, tr = IDENTITY, path = [], &block)
        ents.each do |e|
          next if e.respond_to?(:hidden?) && e.hidden?
          next if e.respond_to?(:layer) && e.layer && !e.layer.visible?
          if e.is_a?(Sketchup::Face)
            yield e, tr, path
          elsif instance?(e)
            each_face(entities_of(e), tr * e.transformation, path + [e], &block)
          end
        end
      end

      # Área real de uma face depois da transformação (em polegadas²)
      def face_area(face, tr)
        return face.area if tr.identity?
        face.area(tr)
      end

      # ---- CSV para Excel (separador ; e vírgula decimal) ----------------------
      def save_csv(rows, default_name)
        path = UI.savepanel('Salvar planilha', '', default_name)
        return nil unless path
        path += '.csv' unless path.downcase.end_with?('.csv')
        File.open(path, 'w:UTF-8') do |f|
          f.write("﻿")
          rows.each do |r|
            f.puts(r.map { |c| csv_cell(c) }.join(';'))
          end
        end
        path
      end

      def csv_cell(c)
        s = c.is_a?(Float) ? br(c, 2).delete('.') : c.to_s
        s =~ /[;"\n]/ ? "\"#{s.gsub('"', '""')}\"" : s
      end

      def ok(msg, extra = {})
        { ok: true, msg: msg }.merge(extra)
      end

      def err(msg, extra = {})
        { ok: false, msg: msg }.merge(extra)
      end
    end
  end
end
