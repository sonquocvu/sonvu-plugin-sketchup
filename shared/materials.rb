# frozen_string_literal: true

# Shared material helpers for CNC workflows. Features can request named visual
# checking materials without duplicating SketchUp material setup.

module SonVu
  module CNCPlugins
    module Materials
      module_function

      def find_material(name)
        Sketchup.active_model.materials[name]
      end

      def find_or_create_material(name, color, alpha = 1.0)
        material = find_material(name) || Sketchup.active_model.materials.add(name)
        material.color = color
        material.alpha = alpha
        material
      end
    end
  end
end
