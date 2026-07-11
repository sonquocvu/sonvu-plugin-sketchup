# frozen_string_literal: true

require 'minitest/autorun'

module Geom
  class Point3d
    attr_reader :x, :y, :z

    def initialize(x, y, z)
      @x = x
      @y = y
      @z = z
    end

    def distance(other)
      Math.sqrt(((x - other.x)**2) + ((y - other.y)**2) + ((z - other.z)**2))
    end

    def -(other)
      Vector3d.new(x - other.x, y - other.y, z - other.z)
    end
  end

  class Vector3d
    attr_reader :x, :y, :z

    def initialize(x, y, z)
      @x = x
      @y = y
      @z = z
    end

    def length
      Math.sqrt((x**2) + (y**2) + (z**2))
    end

    def normalize!
      magnitude = length
      @x /= magnitude
      @y /= magnitude
      @z /= magnitude
      self
    end

    def *(other)
      Vector3d.new(
        (y * other.z) - (z * other.y),
        (z * other.x) - (x * other.z),
        (x * other.y) - (y * other.x)
      )
    end
  end
end

module SonVu
  module CNCPlugins
    module Units
      module_function

      def model_units_to_millimeters(length)
        length
      end
    end
  end
end

require_relative '../geometry'
require_relative '../../constants'
require_relative '../dialog'
require_relative '../dialog_html'

module SonVu
  module CNCPlugins
    module DogboneJoinery
      class GeometryTest < Minitest::Test
        Geometry = DogboneJoinery::Geometry

        class FakeEntities
          attr_reader :faces

          def initialize
            @faces = []
          end

          def add_face(points)
            @faces << points
            Object.new
          end
        end

        def base_params
          {
            tenon_width: 80.0,
            tenon_height: 18.0,
            tenon_projection: 20.0,
            cutter_diameter: 6.0,
            clearance: 0.2,
            tenon_edge_offset: 20.0,
            tenon_face_width: 100.0,
            tenon_relief_enabled: true
          }
        end

        def test_clearance_reduces_total_width_and_height_once
          assert_in_delta 79.8, Geometry.effective_tenon_width(base_params), 0.0001
          assert_in_delta 17.8, Geometry.effective_tenon_height(base_params), 0.0001
          assert_in_delta 0.1, Geometry.tenon_vertical_inset(base_params), 0.0001
        end

        def test_profile_is_extruded_as_one_continuous_shell
          params = base_params
          origin = Geom::Point3d.new(0, 0, 0)
          points = Geometry.tenon_profile_points(
            origin,
            Geometry.effective_tenon_width(params),
            Geometry.tenon_projection(params),
            params[:cutter_diameter] / 2.0,
            params
          )
          entities = FakeEntities.new

          Geometry.add_xz_profile_solid(entities, points, Geometry.effective_tenon_height(params))

          assert_operator points.length, :>, 4
          assert_equal points.length + 2, entities.faces.length
          assert_in_delta 0.0, points.map(&:x).min, 0.0001
          assert_in_delta 79.8, points.map(&:x).max, 0.0001
          assert_in_delta 0.0, points.map(&:y).min, 0.0001
          assert_in_delta 0.0, points.map(&:y).max, 0.0001
          assert_in_delta 20.0, points.map(&:z).max, 0.0001
          assert entities.faces.flatten.any? { |point| (point.y - 17.8).abs < 0.0001 }
          assert entities.faces.flatten.any? { |point| (point.z - 20.0).abs < 0.0001 }
        end

        def test_reliefs_are_in_xz_shoulder_plane
          params = base_params
          points = Geometry.tenon_profile_points(
            Geom::Point3d.new(0, 0.1, 0),
            Geometry.effective_tenon_width(params),
            Geometry.tenon_projection(params),
            params[:cutter_diameter] / 2.0,
            params
          )

          assert points.all? { |point| (point.y - 0.1).abs < 0.0001 }
          assert points.any? { |point| point.x > 0 && point.x < 3.1 && point.z > 0 && point.z < 6.1 }
          assert points.any? { |point| point.x < 79.8 && point.x > 76.7 && point.z > 0 && point.z < 6.1 }
        end

        def test_layout_width_is_the_single_finished_tenon_width
          assert_in_delta 79.8, Geometry.tenon_layout_width(base_params), 0.0001
        end

        def test_layout_rejects_geometry_outside_selected_face
          params = base_params.merge(tenon_edge_offset: 30.0, tenon_face_width: 100.0)

          error = assert_raises(RuntimeError) { Geometry.validate_tenon_layout(params) }
          assert_match(/vượt quá chiều rộng mặt đã chọn/, error.message)
        end

        def test_projection_supports_legacy_parameter_name
          params = base_params.dup
          params.delete(:tenon_projection)
          params[:tenon_thickness] = 22.0

          assert_in_delta 22.0, Geometry.tenon_projection(params), 0.0001
        end

        def test_negative_clearance_is_rejected_by_geometry_layer
          error = assert_raises(RuntimeError) do
            Geometry.validate_tenon_clearance(base_params.merge(clearance: -0.1))
          end

          assert_match(/không được nhỏ hơn 0/, error.message)
        end
      end

      class DialogTest < Minitest::Test
        Dialog = DogboneJoinery::Dialog

        Vertex = Struct.new(:position)
        Face = Struct.new(:vertices, :edges, :normal)

        class Edge
          attr_reader :start, :end

          def initialize(start_vertex, end_vertex)
            @start = start_vertex
            @end = end_vertex
          end

          def length
            @start.position.distance(@end.position)
          end
        end

        def valid_values
          {
            preset: 'Tùy chỉnh',
            mortise_width_mm: 80.0,
            mortise_height_mm: 20.0,
            mortise_depth_mm: 18.0,
            cutter_diameter_mm: 6.0,
            clearance_mm: 0.2,
            dogbone_style: 'Chéo',
            create_mortise: false,
            cut_mortise_into_selected_solid: false,
            tenon_width_mm: 40.0,
            tenon_face_width_mm: 100.0,
            tenon_height_mm: 18.0,
            tenon_thickness_mm: 10.0,
            tenon_edge_offset_mm: 5.0,
            create_tenon: true,
            tenon_relief_enabled: true,
            add_labels: false,
            selected_face: true,
            selected_side_face: true
          }
        end

        def test_tenon_defaults_are_40_by_10_with_20_edge_offset
          values = Dialog.defaults_for_mode(:tenon)

          assert_equal Dialog::PROMPTS.length, Dialog::DEFAULTS.length
          assert_equal Dialog::PROMPTS.length, Dialog::LISTS.length
          assert_equal 40, values[9]
          assert_equal 10, values[10]
          assert_equal 20, values[11]
          assert_equal Dialog::YES, values[12]
        end

        def test_projection_may_be_shorter_than_selected_face_height
          assert_nil Dialog.validate(valid_values)
        end

        def test_dialog_rejects_layout_that_exceeds_face
          values = valid_values.merge(tenon_edge_offset_mm: 70.0)

          assert_match(/vượt quá chiều rộng mặt đã chọn/, Dialog.validate(values))
        end

        def test_face_dimensions_are_measured_in_face_axes
          diagonal = Math.sqrt(0.5)
          vertices = [
            Vertex.new(Geom::Point3d.new(0, 0, 0)),
            Vertex.new(Geom::Point3d.new(100 * diagonal, 100 * diagonal, 0)),
            Vertex.new(Geom::Point3d.new(100 * diagonal, 100 * diagonal, 18)),
            Vertex.new(Geom::Point3d.new(0, 0, 18))
          ]
          edges = vertices.each_index.map { |index| Edge.new(vertices[index], vertices[(index + 1) % vertices.length]) }
          face = Face.new(vertices, edges, Geom::Vector3d.new(diagonal, -diagonal, 0))

          dimensions = Dialog.face_dimensions(face)

          assert_in_delta 100.0, dimensions[:width], 0.0001
          assert_in_delta 18.0, dimensions[:height], 0.0001
        end

        def test_mortise_and_tenon_have_separate_forms
          context = {
            selected: true,
            side_face: true,
            width_mm: 100.0,
            height_mm: 18.0,
            width_label: '100 mm',
            height_label: '18 mm'
          }

          tenon_html = DogboneJoinery::DialogHTML.html(context, :tenon)
          mortise_html = DogboneJoinery::DialogHTML.html(context, :mortise)

          assert_equal 1, tenon_html.scan('id="clearance_mm"').length
          assert_includes tenon_html, '100 mm × 18 mm'
          refute_includes tenon_html, 'id="mortise_width_mm"'
          refute_includes tenon_html, 'id="tenon_count"'
          refute_includes tenon_html, 'id="tenon_spacing_mm"'
          assert_includes mortise_html, 'id="mortise_width_mm"'
          refute_includes mortise_html, 'id="tenon_width_mm"'
          refute_includes mortise_html, 'id="clearance_mm"'
        end
      end
    end
  end
end
