# frozen_string_literal: true

# Interactive SketchUp tool code for Dogbone Joinery. The placement tool waits
# for a model click, then creates the requested templates at that location.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      class PlacementTool
        STATUS_TEXT = 'Bấm một điểm để đặt mộng xương chó.'
        MORTISE_STATUS_TEXT = 'Di chuyển bản xem trước và bấm để đặt tâm mộng âm. Esc để hủy.'
        MORTISE_OUTSIDE_STATUS_TEXT = 'Biên dạng mộng âm phải nằm hoàn toàn trong mặt đã chọn.'
        MORTISE_PREVIEW_ERROR_PREFIX = 'Không hiển thị được bản xem trước'
        VK_ESCAPE = 27

        def initialize(params, placement_face = nil, cut_target = nil)
          @params = params
          @placement_face = placement_face
          @cut_target = cut_target
          @input_point = Sketchup::InputPoint.new
        end

        def self.create_on_face(params, placement_face)
          new(params, placement_face, nil).create_on_face
        end

        def self.integrate_tenons_on_face(params, placement_face, target)
          new(params, placement_face, nil).integrate_tenons_on_face(target)
        end

        def create_on_face
          reference_point = @placement_face.bounds.center
          DogboneJoinery::Geometry.create_templates(
            @params,
            origin: placement_origin(reference_point),
            transformation: placement_transformation(reference_point)
          )
        end

        def integrate_tenons_on_face(target)
          model = Sketchup.active_model
          original_path = model.respond_to?(:active_path) ? model.active_path : nil
          reference_point = @placement_face.bounds.center
          local_placement = placement_transformation(reference_point)
          parent_placement = target.transformation * local_placement
          local_origin = placement_origin(reference_point)

          model.close_active
          DogboneJoinery::Geometry.union_tenons_into_solid(
            target,
            @params,
            origin: local_origin,
            transformation: parent_placement
          )
        rescue StandardError
          if original_path && target.respond_to?(:valid?) && target.valid? && model.respond_to?(:active_path=)
            model.active_path = original_path
          end
          raise
        end

        def activate
          update_status_text(mortise_placement? ? MORTISE_STATUS_TEXT : STATUS_TEXT)
        end

        def deactivate(view)
          view.invalidate if view
        end

        def onMouseMove(_flags, x, y, view)
          @input_point.pick(view, x, y)
          if mortise_placement? && @input_point.valid?
            status = mortise_profile_fits_face?(@input_point.position) ? MORTISE_STATUS_TEXT : MORTISE_OUTSIDE_STATUS_TEXT
            update_status_text(status)
          end
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @input_point.pick(view, x, y)
          return unless @input_point.valid?

          if mortise_placement? && !mortise_profile_fits_face?(@input_point.position)
            update_status_text(MORTISE_OUTSIDE_STATUS_TEXT)
            view.invalidate
            return
          end

          if @cut_target
            DogboneJoinery::Geometry.cut_mortise_into_solid(
              @cut_target,
              @params,
              origin: placement_origin(@input_point.position),
              transformation: placement_transformation(@input_point.position)
            )
          else
            DogboneJoinery::Geometry.create_templates(
              @params,
              origin: placement_origin(@input_point.position),
              transformation: placement_transformation(@input_point.position)
            )
          end
          view.model.select_tool(nil)
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("#{failure_message}:\n#{e.message}")
          view.model.select_tool(nil)
        end

        def onKeyDown(key, _repeat, _flags, view)
          view.model.select_tool(nil) if key == VK_ESCAPE
        end

        def draw(view)
          @input_point.draw(view) if @input_point.display?
          if mortise_placement? && @input_point.valid?
            draw_mortise_center(view)
            draw_mortise_preview(view)
          end
        end

        def getExtents
          bounds = Geom::BoundingBox.new
          @placement_face.vertices.each { |vertex| bounds.add(vertex.position) } if @placement_face
          if mortise_placement? && @input_point.valid?
            mortise_preview_points(@input_point.position).each { |point| bounds.add(point) }
          end
          bounds
        rescue StandardError => e
          report_preview_error(e)
          Geom::BoundingBox.new
        end

        private

        def failure_message
          @cut_target ? 'Không cắt được mộng âm xương chó' : 'Không đặt được mẫu mộng xương chó'
        end

        def placement_origin(point)
          return Geom::Point3d.new(0, 0, 0) if mortise_placement?
          return face_local_origin if @placement_face

          Geom::Point3d.new(point.x, point.y, point.z)
        end

        def placement_transformation(point)
          return nil unless @placement_face

          # Transformation math:
          # Template geometry is authored in local coordinates where X follows
          # the selected edge, Y crosses the selected face, and Z is normal to
          # that face. Mortises use XY as their profile plane and extrude along
          # -Z. Tenons use XZ as their relieved shoulder plane and extrude through
          # the selected edge-face thickness along +Y. For face placement we build a
          # local coordinate frame at the clicked point projected onto the
          # selected face plane. Local Z follows the selected face normal for
          # mortises. For tenon-only placement, local Z is corrected to point
          # away from the connected model bounds so the tab protrudes outward.
          # Local X follows an edge direction on that face, and local Y is the
          # cross product that completes the plane basis.
          #
          # Mortise geometry is centered around the local origin, so the
          # projected cursor point becomes the center of its live preview.
          zaxis = placement_zaxis

          xaxis = face_xaxis(zaxis)
          yaxis = zaxis * xaxis
          yaxis.normalize!

          origin = face_anchored_template? ? face_min_anchor(xaxis, yaxis) : project_point_to_face(point)
          Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
        end

        def placement_zaxis
          normal = Geom::Vector3d.new(@placement_face.normal.x, @placement_face.normal.y, @placement_face.normal.z)
          normal.normalize!
          outward_normal(normal)
        end

        def outward_normal(normal)
          face_center = selected_face_center
          bounds_center = connected_geometry_bounds_center
          return ray_outward_normal(normal) unless face_center && bounds_center

          outward_vector = face_center - bounds_center
          return ray_outward_normal(normal) if outward_vector.length <= 0.001

          outward_vector.normalize!
          bounds_normal = vector_dot(normal, outward_vector).negative? ? reversed_vector(normal) : normal
          bounds_normal
        end

        def ray_outward_normal(normal)
          reversed = reversed_vector(normal)
          normal_distance = ray_hit_distance(normal)
          reversed_distance = ray_hit_distance(reversed)

          return normal if normal_distance.nil? && reversed_distance
          return reversed if reversed_distance.nil? && normal_distance
          return normal unless normal_distance && reversed_distance

          normal_distance >= reversed_distance ? normal : reversed
        rescue StandardError
          normal
        end

        def ray_hit_distance(direction)
          face_center = selected_face_center
          return nil unless face_center

          start = face_center.offset(direction, CNCPlugins::Units.millimeters_to_model_units(1))
          hit = Sketchup.active_model.raytest([start, direction], true)
          return nil unless hit && hit.first

          start.distance(hit.first)
        end

        def selected_face_center
          vertices = @placement_face.vertices
          return nil if vertices.empty?

          x = vertices.sum { |vertex| vertex.position.x } / vertices.length.to_f
          y = vertices.sum { |vertex| vertex.position.y } / vertices.length.to_f
          z = vertices.sum { |vertex| vertex.position.z } / vertices.length.to_f
          Geom::Point3d.new(x, y, z)
        end

        def connected_geometry_bounds_center
          bounds = Geom::BoundingBox.new
          @placement_face.all_connected.each do |entity|
            next unless entity.respond_to?(:bounds)

            entity_bounds = entity.bounds
            bounds.add(entity_bounds.min)
            bounds.add(entity_bounds.max)
          end
          bounds.valid? ? bounds.center : nil
        end

        def vector_dot(first, second)
          (first.x * second.x) + (first.y * second.y) + (first.z * second.z)
        end

        def reversed_vector(vector)
          Geom::Vector3d.new(-vector.x, -vector.y, -vector.z)
        end

        def face_local_origin
          if tenon_only_template?
            return Geom::Point3d.new(0, 0, 0)
          end

          return Geom::Point3d.new(0, 0, 0) if mortise_only_template?

          Geom::Point3d.new(
            -(@params.fetch(:mortise_width) / 2.0),
            -(@params.fetch(:mortise_height) / 2.0),
            0
          )
        end

        def tenon_only_template?
          @params[:create_tenon] && !@params[:create_mortise] && !@cut_target
        end

        def mortise_only_template?
          @params[:create_mortise] && !@params[:create_tenon] && !@cut_target
        end

        def face_anchored_template?
          tenon_only_template?
        end

        def mortise_placement?
          @placement_face && (mortise_only_template? || @cut_target)
        end

        def draw_mortise_preview(view)
          points = mortise_preview_points(@input_point.position)
          return if points.empty?

          valid = mortise_profile_fits_face?(@input_point.position)
          points = lift_preview_from_face(points, view)
          view.drawing_color = preview_color(valid)
          view.line_width = 2
          view.draw_polyline(points + [points.first])
        rescue StandardError => e
          report_preview_error(e)
        end

        def draw_mortise_center(view)
          center = project_point_to_face(@input_point.position)
          valid = mortise_profile_fits_face?(@input_point.position)
          center = lift_preview_from_face([center], view).first
          view.draw_points([center], 12, 3, preview_color(valid))
        rescue StandardError => e
          report_preview_error(e)
        end

        def preview_color(valid)
          valid ? Sketchup::Color.new(38, 166, 91) : Sketchup::Color.new(210, 48, 48)
        end

        def lift_preview_from_face(points, view)
          reference = points.first
          distance = view.pixels_to_model(2, reference)
          normal = placement_zaxis
          points.map { |point| point.offset(normal, distance) }
        end

        def mortise_preview_points(point)
          local_points = DogboneJoinery::Geometry.centered_mortise_profile_points(@params)
          transformation = placement_transformation(point)
          local_points.map { |profile_point| transformation * profile_point }
        end

        def mortise_profile_fits_face?(point)
          return false unless point_on_selected_face?(project_point_to_face(point))

          points = mortise_preview_points(point)
          return false if points.empty?

          samples = points.each_with_index.flat_map do |current, index|
            following = points[(index + 1) % points.length]
            [current, midpoint(current, following)]
          end
          samples.all? { |sample| point_on_selected_face?(sample) }
        rescue StandardError
          false
        end

        def point_on_selected_face?(point)
          classification = @placement_face.classify_point(point)
          [
            Sketchup::Face::PointInside,
            Sketchup::Face::PointOnFace,
            Sketchup::Face::PointOnEdge,
            Sketchup::Face::PointOnVertex
          ].include?(classification)
        end

        def midpoint(first, second)
          Geom::Point3d.new(
            (first.x + second.x) / 2.0,
            (first.y + second.y) / 2.0,
            (first.z + second.z) / 2.0
          )
        end

        def report_preview_error(error)
          return if @preview_error_reported

          @preview_error_reported = true
          message = "#{MORTISE_PREVIEW_ERROR_PREFIX}: #{error.message}"
          update_status_text(message)
          warn("[SonVu CNC Plugins] #{message}\n#{error.backtrace&.first}")
        end

        def update_status_text(message)
          Sketchup.set_status_text(message)
        end

        def project_point_to_face(point)
          point.project_to_plane([@placement_face.vertices.first.position, @placement_face.normal])
        end

        def face_xaxis(normal)
          edge = @placement_face.edges.max_by(&:length)
          xaxis = edge_direction(edge)
          xaxis = fallback_xaxis(normal) if xaxis.length <= 0.001
          xaxis.normalize!
          xaxis
        end

        def edge_direction(edge)
          edge.end.position - edge.start.position
        end

        def fallback_xaxis(normal)
          world_x = Geom::Vector3d.new(1, 0, 0)
          world_z = Geom::Vector3d.new(0, 0, 1)
          candidate = normal.parallel?(world_z) ? world_x : world_z * normal
          candidate.normalize!
          candidate
        end

        def face_min_anchor(xaxis, yaxis)
          vertices = @placement_face.vertices.map(&:position)
          return project_point_to_face(@input_point.position) if vertices.empty?

          world_origin = Geom::Point3d.new(0, 0, 0)
          reference = vertices.first
          min_x = vertices.map { |vertex| vector_dot(vertex - world_origin, xaxis) }.min
          min_y = vertices.map { |vertex| vector_dot(vertex - world_origin, yaxis) }.min
          reference_x = vector_dot(reference - world_origin, xaxis)
          reference_y = vector_dot(reference - world_origin, yaxis)

          reference.offset(xaxis, min_x - reference_x).offset(yaxis, min_y - reference_y)
        end
      end
    end
  end
end
