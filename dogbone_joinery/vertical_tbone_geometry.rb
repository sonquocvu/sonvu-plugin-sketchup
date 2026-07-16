# frozen_string_literal: true

# Pure measurements shared by the manual vertical T-bone profile, automatic
# feasibility filtering, and automatic preview markers. SketchUp entities are
# deliberately not referenced here.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module VerticalTBoneGeometry
        CENTER_OFFSET_FACTOR = 0.65
        EPSILON = 1.0e-9

        module_function

        def center_offset(radius)
          radius.to_f * CENTER_OFFSET_FACTOR
        end

        def horizontal_relief_reach(radius)
          value = radius.to_f
          offset = center_offset(value)
          Math.sqrt((value * value) - (offset * offset))
        end

        def feasible?(width:, height:, radius:)
          validate!(width: width, height: height, radius: radius)
          true
        rescue ArgumentError
          false
        end

        def validate!(width:, height:, radius:)
          values = [width, height, radius]
          unless values.all? { |value| finite_number?(value) && value.to_f.positive? }
            raise ArgumentError, 'Kích thước mộng âm dọc T-bone phải lớn hơn 0.'
          end
          minimum_width = horizontal_relief_reach(radius) * 2.0
          if width.to_f <= minimum_width + EPSILON
            raise ArgumentError, 'Chiều rộng mộng không đủ cho bán kính dao dọc T-bone.'
          end

          true
        end

        def relief_centers(width:, height:, radius:, origin_x: 0.0, origin_y: 0.0)
          validate!(width: width, height: height, radius: radius)
          left = origin_x.to_f
          right = left + width.to_f
          bottom = origin_y.to_f
          top = bottom + height.to_f
          offset = center_offset(radius)
          {
            bottom_left: [left, bottom - offset],
            bottom_right: [right, bottom - offset],
            top_right: [right, top + offset],
            top_left: [left, top + offset]
          }.freeze
        end

        def finite_number?(value)
          value.is_a?(Numeric) && (!value.respond_to?(:finite?) || value.finite?)
        end
      end
    end
  end
end
