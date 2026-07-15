# frozen_string_literal: true

# Click-to-place tool for newly configured furniture. The preview is a simple
# cabinet envelope; model geometry is created only after the customer clicks.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class PlacementTool
        STATUS_TEXT = 'Di chuyển chuột và bấm để đặt tủ. Nhấn Esc để hủy.'
        VK_ESCAPE = 27

        def initialize(settings)
          @settings = Specification.normalize(settings)
          @input_point = Sketchup::InputPoint.new
        end

        def activate
          Sketchup.set_status_text(STATUS_TEXT)
        end

        def deactivate(view)
          view.invalidate if view
        end

        def onMouseMove(_flags, x, y, view)
          @input_point.pick(view, x, y)
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @input_point.pick(view, x, y)
          return unless @input_point.valid?

          transformation = Geom::Transformation.translation(active_context_point.to_a)
          FurnitureBuilder::Geometry.create(@settings, transformation: transformation)
          view.model.select_tool(nil)
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không tạo được tủ nội thất:\n#{e.message}")
          view.model.select_tool(nil)
        end

        def onKeyDown(key, _repeat, _flags, view)
          view.model.select_tool(nil) if key == VK_ESCAPE
        end

        def onCancel(_reason, view)
          view.model.select_tool(nil)
        end

        def draw(view)
          return unless @input_point.valid?

          view.drawing_color = Sketchup::Color.new(34, 108, 74)
          view.line_width = 2
          view.draw(::GL_LINES, preview_edges(@input_point.position))
          @input_point.draw(view) if @input_point.display?
        end

        def getExtents
          bounds = Geom::BoundingBox.new
          preview_corners(@input_point.position).each { |point| bounds.add(point) } if @input_point.valid?
          bounds
        end

        private

        def active_context_point
          model = Sketchup.active_model
          return @input_point.position unless model.respond_to?(:edit_transform)

          model.edit_transform.inverse * @input_point.position
        end

        def preview_edges(origin)
          corners = preview_corners(origin)
          edge_indexes = [
            0, 1, 1, 2, 2, 3, 3, 0,
            4, 5, 5, 6, 6, 7, 7, 4,
            0, 4, 1, 5, 2, 6, 3, 7
          ]
          edge_indexes.map { |index| corners[index] }
        end

        def preview_corners(origin)
          width = mm(@settings[:width_mm])
          depth = mm(@settings[:depth_mm])
          height = mm(@settings[:height_mm])
          [
            [0, 0, 0], [width, 0, 0], [width, depth, 0], [0, depth, 0],
            [0, 0, height], [width, 0, height], [width, depth, height], [0, depth, height]
          ].map do |x, y, z|
            Geom::Point3d.new(origin.x + x, origin.y + y, origin.z + z)
          end
        end

        def mm(value)
          CNCPlugins::Units.millimeters_to_model_units(value)
        end
      end
    end
  end
end
