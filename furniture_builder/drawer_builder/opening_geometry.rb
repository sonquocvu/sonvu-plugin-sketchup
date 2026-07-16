# frozen_string_literal: true

# Read-only geometric measurements for an assigned drawer opening. Furniture
# geometry in this extension uses local X for width, Y for depth, and Z for
# height. Definition bounds keep that convention even when an instance is
# rotated in its parent context.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module OpeningGeometry
          module_function

          def depth(entity)
            bounds, local = bounds_for(entity)
            return nil unless bounds

            value = finite_positive(local_y_extent(bounds))
            return nil unless value

            value *= local_y_scale(entity) if local
            finite_positive(value)
          rescue StandardError
            nil
          end

          def local_y_extent(bounds)
            return nil unless bounds.respond_to?(:min) && bounds.respond_to?(:max)

            minimum = bounds.min
            maximum = bounds.max
            return nil unless minimum.respond_to?(:y) && maximum.respond_to?(:y)

            maximum.y.to_f - minimum.y.to_f
          end

          def bounds_for(entity)
            return [nil, false] unless entity

            if entity.respond_to?(:definition)
              definition = entity.definition
              if definition && definition.respond_to?(:bounds)
                return [definition.bounds, true]
              end
            end
            if entity.respond_to?(:local_bounds)
              return [entity.local_bounds, true]
            end
            return [entity.bounds, false] if entity.respond_to?(:bounds)

            [nil, false]
          end

          def local_y_scale(entity)
            return 1.0 unless entity.respond_to?(:transformation)

            transformation = entity.transformation
            return 1.0 unless transformation

            if transformation.respond_to?(:yaxis)
              axis = transformation.yaxis
              return finite_positive(axis.length) || 1.0 if axis && axis.respond_to?(:length)
            end
            if transformation.respond_to?(:yscale)
              return finite_positive(transformation.yscale) || 1.0
            end

            1.0
          end

          def finite_positive(value)
            number = Float(value)
            number.positive? && number.finite? ? number : nil
          rescue ArgumentError, TypeError
            nil
          end
        end
      end
    end
  end
end
