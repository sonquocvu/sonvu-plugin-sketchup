# frozen_string_literal: true

# Interactive SketchUp tool code for Dogbone Joinery. The placement tool waits
# for a model click, then creates the requested templates at that location.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      class PlacementTool
        STATUS_TEXT = 'Bấm một điểm để đặt mộng xương chó.'
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

        def create_on_face
          reference_point = @placement_face.bounds.center
          DogboneJoinery::Geometry.create_templates(
            @params,
            origin: placement_origin(reference_point),
            transformation: placement_transformation(reference_point)
          )
        end

        def activate
          UI.set_status_text(STATUS_TEXT)
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
        end

        private

        def failure_message
          @cut_target ? 'Không cắt được mộng âm xương chó' : 'Không đặt được mẫu mộng xương chó'
        end

        def placement_origin(point)
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
          # The geometry is generated around a local origin before this
          # transform is applied. For face placement, face_local_origin offsets
          # the template by half the mortise width/height, so the clicked point
          # lands at the center of the mortise rectangle rather than at a corner.
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
          tenon_only_template? || mortise_only_template?
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
