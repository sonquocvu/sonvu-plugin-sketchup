# frozen_string_literal: true

# Interactive SketchUp tool code for Dogbone Joinery. The placement tool waits
# for a model click, then creates the requested templates at that location.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      class PlacementTool
        STATUS_TEXT = 'Click a point to place the dog-bone joint.'
        VK_ESCAPE = 27

        def initialize(params, placement_face = nil)
          @params = params
          @placement_face = placement_face
          @input_point = Sketchup::InputPoint.new
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

          DogboneJoinery::Geometry.create_templates(
            @params,
            origin: placement_origin(@input_point.position),
            transformation: placement_transformation(@input_point.position)
          )
          view.model.select_tool(nil)
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Unable to place Dogbone templates:\n#{e.message}")
          view.model.select_tool(nil)
        end

        def onKeyDown(key, _repeat, _flags, view)
          view.model.select_tool(nil) if key == VK_ESCAPE
        end

        def draw(view)
          @input_point.draw(view) if @input_point.display?
        end

        private

        def placement_origin(point)
          return face_local_origin if @placement_face

          Geom::Point3d.new(point.x, point.y, point.z)
        end

        def placement_transformation(point)
          return nil unless @placement_face

          # Transformation math:
          # Template geometry is authored in local coordinates where X is width,
          # Y is height, and Z is mortise depth. For face placement we build a
          # local coordinate frame at the clicked point projected onto the
          # selected face plane. Local Z follows the selected face normal, local
          # X follows an edge direction on that face, and local Y is the cross
          # product that completes the plane basis.
          #
          # The geometry is generated around a local origin before this
          # transform is applied. For face placement, face_local_origin offsets
          # the template by half the mortise width/height, so the clicked point
          # lands at the center of the mortise rectangle rather than at a corner.
          zaxis = @placement_face.normal
          zaxis.normalize!

          xaxis = face_xaxis(zaxis)
          yaxis = zaxis * xaxis
          yaxis.normalize!

          Geom::Transformation.axes(project_point_to_face(point), xaxis, yaxis, zaxis)
        end

        def face_local_origin
          Geom::Point3d.new(
            -(@params.fetch(:mortise_width) / 2.0),
            -(@params.fetch(:mortise_height) / 2.0),
            0
          )
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
      end
    end
  end
end
