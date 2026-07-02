# frozen_string_literal: true

# Shared unit helpers for CNC feature code. User-facing values are entered in
# millimeters and converted here to SketchUp internal length values.

module SonVu
  module CNCPlugins
    module Units
      module_function

      def inches_to_model_units(value)
        value.to_f.inch
      end

      def millimeters_to_model_units(value)
        value.to_f.mm
      end

      def model_units_to_millimeters(length)
        return length.to_mm if length.respond_to?(:to_mm)

        length.to_f / 1.mm
      end
    end
  end
end
