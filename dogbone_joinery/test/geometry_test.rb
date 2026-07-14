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

module Sketchup
  class << self
    attr_reader :last_status_text

    def set_status_text(message)
      @last_status_text = message
    end
  end
end

module SonVu
  module CNCPlugins
    module Licensing
      module Manager
        class << self
          attr_accessor :feature_allowed

          def require_feature(_feature)
            @feature_allowed != false
          end
        end
      end
    end

    module Units
      module_function

      def model_units_to_millimeters(length)
        length
      end

      def millimeters_to_model_units(length)
        length
      end
    end
  end
end

require_relative '../geometry'
require_relative '../../constants'
require_relative '../dialog'
require_relative '../dialog_html'
require_relative '../commands'
require_relative '../tool'

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
            coordinates = points.map { |point| [point.x, point.y, point.z] }
            raise ArgumentError, 'Duplicate points in array' unless coordinates.uniq.length == coordinates.length

            @faces << points
            Object.new
          end
        end

        class FakeBackup
          attr_accessor :name, :hidden
          attr_reader :attributes

          def initialize
            @attributes = {}
          end

          def set_attribute(dictionary, key, value)
            @attributes[[dictionary, key]] = value
          end
        end

        class FakeSolidTarget
          attr_reader :backup

          def initialize
            @backup = FakeBackup.new
          end

          def copy
            backup
          end
        end

        class FakeComponentTarget
          attr_reader :definition, :transformation

          def initialize
            @definition = Object.new
            @transformation = Object.new
          end
        end

        class FakeParentEntities
          attr_reader :definition, :transformation, :backup

          def add_instance(definition, transformation)
            @definition = definition
            @transformation = transformation
            @backup = FakeBackup.new
          end
        end

        def base_params
          {
            tenon_width: 80.0,
            tenon_height: 18.0,
            tenon_projection: 20.0,
            cutter_radius: 3.0,
            tenon_cutter_radius: 3.0,
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
            params[:cutter_radius],
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
            params[:cutter_radius],
            params
          )

          assert points.all? { |point| (point.y - 0.1).abs < 0.0001 }
          assert points.any? { |point| point.x > 0 && point.x < 3.1 && point.z > 0 && point.z < 6.1 }
          assert points.any? { |point| point.x < 79.8 && point.x > 76.7 && point.z > 0 && point.z < 6.1 }
        end

        def test_tenon_relief_uses_supplied_cutter_radius
          params = base_params.merge(tenon_cutter_radius: 4.0)
          radius = Geometry.tenon_cutter_radius(params)
          points = Geometry.tenon_profile_points(
            Geom::Point3d.new(0, 0, 0),
            Geometry.effective_tenon_width(params),
            Geometry.tenon_projection(params),
            radius,
            params
          )
          left_relief_points = points.select { |point| point.x < 20 && point.z < 8.1 }

          assert_in_delta 4.0, radius, 0.0001
          assert_in_delta 4.0, left_relief_points.map(&:x).max, 0.05
        end

        def test_mortise_uses_radius_and_accepts_legacy_diameter
          assert_in_delta 3.0, Geometry.mortise_cutter_radius(cutter_radius: 3.0), 0.0001
          assert_in_delta 3.0, Geometry.mortise_cutter_radius(cutter_diameter: 6.0), 0.0001
        end

        def test_mortise_solid_is_recessed_below_surface_plane
          surface_points = [
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(40, 0, 0),
            Geom::Point3d.new(40, 20, 0),
            Geom::Point3d.new(0, 20, 0),
            Geom::Point3d.new(0, 0, 0)
          ]
          entities = FakeEntities.new

          Geometry.add_negative_z_profile_solid(entities, surface_points, 18.0)

          all_points = entities.faces.flatten
          assert_equal 6, entities.faces.length
          assert_in_delta 0.0, all_points.map(&:z).max, 0.0001
          assert_in_delta(-18.0, all_points.map(&:z).min, 0.0001)
          refute all_points.any? { |point| point.z > 0.0001 }
        end

        def test_profile_normalization_removes_neighbor_and_closing_duplicates
          first = Geom::Point3d.new(0, 0, 0)
          second = Geom::Point3d.new(10, 0, 0)
          third = Geom::Point3d.new(10, 10, 0)

          normalized = Geometry.normalize_profile_points([first, first, second, third, first])

          assert_equal 3, normalized.length
          assert_same first, normalized.first
          assert_same third, normalized.last
        end

        def test_generated_dogbone_mortise_builds_without_duplicate_face_points
          params = {
            mortise_width: 40.0,
            mortise_height: 20.0,
            cutter_radius: 3.0,
            dogbone_style: Geometry::DOGBONE_STYLE_DIAGONAL
          }
          profile = Geometry.points_for_dogbone_mortise_profile(params)
          entities = FakeEntities.new

          Geometry.add_negative_z_profile_solid(entities, profile, 10.0)

          assert_operator entities.faces.length, :>, 2
          assert entities.faces.flatten.all? { |point| point.z <= 0.0001 }
        end

        def test_mortise_profile_is_centered_on_placement_point
          params = {
            mortise_width: 40.0,
            mortise_height: 20.0,
            mortise_depth: 10.0,
            mortise_face_width: 100.0,
            mortise_face_height: 80.0,
            mortise_model_depth: 15.0,
            cutter_radius: 3.0,
            dogbone_style: Geometry::DOGBONE_STYLE_DIAGONAL
          }

          points = Geometry.centered_mortise_profile_points(params, Geom::Point3d.new(50, 40, 0))

          assert_in_delta 50.0, (points.map(&:x).min + points.map(&:x).max) / 2.0, 0.0001
          assert_in_delta 40.0, (points.map(&:y).min + points.map(&:y).max) / 2.0, 0.0001
          assert_nil Geometry.validate_mortise_against_face(params)
        end

        def test_mortise_depth_cannot_exceed_model_depth
          params = {
            mortise_width: 40.0,
            mortise_height: 20.0,
            mortise_depth: 16.0,
            mortise_face_width: 100.0,
            mortise_face_height: 80.0,
            mortise_model_depth: 15.0,
            cutter_radius: 3.0,
            dogbone_style: Geometry::DOGBONE_STYLE_DIAGONAL
          }

          error = assert_raises(RuntimeError) { Geometry.validate_mortise_against_face(params) }
          assert_match(/vượt quá chiều sâu model/, error.message)
        end

        def test_mortise_recess_rejects_nonpositive_depth
          entities = FakeEntities.new
          points = [
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(1, 0, 0),
            Geom::Point3d.new(0, 1, 0)
          ]

          assert_raises(RuntimeError) { Geometry.add_negative_z_profile_solid(entities, points, 0) }
        end

        def test_layout_width_is_the_single_finished_tenon_width
          assert_in_delta 79.8, Geometry.tenon_layout_width(base_params), 0.0001
        end

        def test_single_tenon_is_centered_on_face
          assert_in_delta 10.1, Geometry.tenon_first_offset(base_params), 0.0001
          assert_in_delta 0.0, Geometry.tenon_gap(base_params), 0.0001
        end

        def test_multiple_tenons_are_distributed_with_equal_gaps
          params = base_params.merge(
            tenon_width: 40.0,
            tenon_count: 5,
            tenon_face_width: 600.0,
            tenon_edge_offset: 20.0
          )
          origin = Geom::Point3d.new(20.0, 0, 0)
          origins = Geometry.tenon_origins(params, origin)

          assert_in_delta 90.25, Geometry.tenon_gap(params), 0.0001
          assert_equal 5, origins.length
          assert_in_delta 20.0, origins.first.x, 0.0001
          assert_in_delta 540.2, origins.last.x, 0.0001
          assert_in_delta 20.0, 600.0 - (origins.last.x + Geometry.effective_tenon_width(params)), 0.0001
        end

        def test_layout_rejects_geometry_outside_selected_face
          params = base_params.merge(tenon_count: 2, tenon_edge_offset: 30.0, tenon_face_width: 100.0)

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

        def test_tenon_union_backup_is_hidden_and_tagged
          target = FakeSolidTarget.new

          backup = Geometry.create_tenon_union_backup(target, 'Canh_Tu')

          assert_equal 'SonVu_Backup_Canh_Tu', backup.name
          assert_equal true, backup.hidden
          assert_equal true, backup.attributes[[CNCPlugins::ATTRIBUTE_DICTIONARY, 'tenon_union_backup']]
        end

        def test_component_tenon_union_backup_uses_definition_instance
          target = FakeComponentTarget.new
          parent_entities = FakeParentEntities.new

          backup = Geometry.create_tenon_union_backup(
            target,
            'Canh_Component',
            parent_entities: parent_entities
          )

          assert_same target.definition, parent_entities.definition
          assert_same target.transformation, parent_entities.transformation
          assert_same parent_entities.backup, backup
          assert_equal 'SonVu_Backup_Canh_Component', backup.name
          assert_equal true, backup.hidden
          assert_equal true, backup.attributes[[CNCPlugins::ATTRIBUTE_DICTIONARY, 'tenon_union_backup']]
        end

        def test_tenon_union_overlap_preserves_visible_projection
          params = base_params
          union_params, union_origin = Geometry.tenon_union_geometry(
            params,
            Geom::Point3d.new(0, 0, 0)
          )

          assert_in_delta(-0.1, union_origin.z, 0.0001)
          assert_in_delta 20.1, Geometry.tenon_projection(union_params), 0.0001
          assert_in_delta 20.0, union_origin.z + Geometry.tenon_projection(union_params), 0.0001
        end
      end

      class DialogTest < Minitest::Test
        Dialog = DogboneJoinery::Dialog

        Vertex = Struct.new(:position)
        Face = Struct.new(:vertices, :edges, :normal)
        ConnectedEntity = Struct.new(:vertices)
        DepthFace = Struct.new(:vertices, :normal, :connected_entities) do
          def all_connected
            connected_entities
          end
        end

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
            cutter_radius_mm: 3.0,
            clearance_mm: 0.2,
            dogbone_style: 'Chéo',
            create_mortise: false,
            cut_mortise_into_selected_solid: false,
            tenon_width_mm: 40.0,
            tenon_face_width_mm: 100.0,
            tenon_height_mm: 18.0,
            tenon_thickness_mm: 10.0,
            tenon_cutter_radius_mm: 3.0,
            tenon_count: 2,
            tenon_edge_offset_mm: 5.0,
            create_tenon: true,
            tenon_relief_enabled: true,
            add_labels: false,
            selected_face: true,
            selected_side_face: true,
            selected_face_width_mm: 100.0,
            selected_face_height_mm: 80.0,
            selected_model_depth_mm: 18.0
          }
        end

        def test_tenon_defaults_are_40_by_10_with_20_edge_offset
          values = Dialog.defaults_for_mode(:tenon)

          assert_equal Dialog::PROMPTS.length, Dialog::DEFAULTS.length
          assert_equal Dialog::PROMPTS.length, Dialog::LISTS.length
          assert_equal 40, values[9]
          assert_equal 10, values[10]
          assert_equal 3, values[11]
          assert_equal 2, values[12]
          assert_equal 20, values[13]
          assert_equal Dialog::YES, values[14]
        end

        def test_mortise_defaults_are_20_by_20_by_10_with_horizontal_tbone
          values = Dialog.defaults_for_mode(:mortise)

          assert_equal 20, values[1]
          assert_equal 20, values[2]
          assert_equal 10, values[3]
          assert_equal 3, values[4]
          assert_equal 'Ngang (T-bone)', values[6]

          context = {
            selected: true,
            side_face: true,
            width_mm: 100.0,
            height_mm: 80.0,
            depth_mm: 18.0,
            width_label: '100 mm',
            height_label: '80 mm',
            depth_label: '18 mm'
          }
          html = DogboneJoinery::DialogHTML.html(context, :mortise)
          assert_match(/value="Ngang \(T-bone\)" checked/, html)
        end

        def test_presets_store_cutter_radius_values
          assert_equal 3, CNCPlugins::DOGBONE_PRESETS.fetch('MDF 18mm / bán kính dao 3mm').fetch(:cutter_radius_mm)
          assert_equal 2, CNCPlugins::DOGBONE_PRESETS.fetch('Ván ép 18mm / bán kính dao 2mm').fetch(:cutter_radius_mm)
        end

        def test_projection_may_be_shorter_than_selected_face_height
          assert_nil Dialog.validate(valid_values)
        end

        def test_dialog_rejects_layout_that_exceeds_face
          values = valid_values.merge(tenon_edge_offset_mm: 70.0)

          assert_match(/vượt quá chiều rộng mặt đã chọn/, Dialog.validate(values))
        end

        def test_dialog_rejects_nonpositive_tenon_cutter_radius
          values = valid_values.merge(tenon_cutter_radius_mm: 0.0)

          assert_match(/Bán kính dao/, Dialog.validate(values))
        end

        def test_dialog_rejects_mortise_deeper_than_model
          values = valid_values.merge(
            create_mortise: true,
            create_tenon: false,
            mortise_depth_mm: 19.0
          )

          assert_match(/vượt quá chiều sâu model/, Dialog.validate(values))
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

        def test_model_depth_is_measured_perpendicular_to_selected_face
          front_vertices = [
            Vertex.new(Geom::Point3d.new(0, 0, 0)),
            Vertex.new(Geom::Point3d.new(100, 0, 0)),
            Vertex.new(Geom::Point3d.new(100, 80, 0)),
            Vertex.new(Geom::Point3d.new(0, 80, 0))
          ]
          back_vertices = front_vertices.map do |vertex|
            Vertex.new(Geom::Point3d.new(vertex.position.x, vertex.position.y, -18))
          end
          connected = ConnectedEntity.new(front_vertices + back_vertices)
          face = DepthFace.new(front_vertices, Geom::Vector3d.new(0, 0, 1), [connected])

          assert_in_delta 18.0, Dialog.face_model_depth(face), 0.0001
        end

        def test_mortise_and_tenon_have_separate_forms
          context = {
            selected: true,
            side_face: true,
            width_mm: 100.0,
            height_mm: 18.0,
            depth_mm: 25.0,
            width_label: '100 mm',
            height_label: '18 mm',
            depth_label: '25 mm'
          }

          tenon_html = DogboneJoinery::DialogHTML.html(context, :tenon)
          mortise_html = DogboneJoinery::DialogHTML.html(context, :mortise)

          assert_equal 1, tenon_html.scan('id="clearance_mm"').length
          assert_includes tenon_html, '100 mm × 18 mm'
          assert_includes tenon_html, 'id="tenon_cutter_radius_mm"'
          refute_includes tenon_html, 'id="mortise_width_mm"'
          assert_includes tenon_html, 'id="tenon_count"'
          assert_includes tenon_html, 'hợp khối với group/component solid'
          refute_includes tenon_html, 'id="tenon_spacing_mm"'
          assert_includes mortise_html, 'id="mortise_width_mm"'
          assert_includes mortise_html, 'id="cutter_radius_mm"'
          refute_includes mortise_html, 'id="cutter_diameter_mm"'
          assert_equal 1, mortise_html.scan('Bán kính dao').length
          assert_equal 1, tenon_html.scan('Bán kính dao').length
          refute_includes mortise_html, 'id="mortise_offset_x_mm"'
          refute_includes mortise_html, 'id="mortise_offset_y_mm"'
          assert_includes mortise_html, 'bấm để đặt tâm mộng âm'
          refute_includes mortise_html, 'id="tenon_width_mm"'
          refute_includes mortise_html, 'id="clearance_mm"'
        end
      end

      class CommandsTest < Minitest::Test
        Commands = DogboneJoinery::Commands

        class ValidTarget
          def manifold?
            true
          end

          def union(_other); end
          def copy; end
          def transformation; end
        end

        class InvalidTarget < ValidTarget
          def manifold?
            false
          end
        end

        class ValidComponentTarget
          attr_reader :definition

          def initialize
            @definition = Object.new
          end

          def manifold?
            true
          end

          def union(_other); end
          def transformation; end
        end

        def test_tenon_target_must_be_a_backupable_union_capable_solid
          assert Commands.valid_solid_target?(ValidTarget.new)
          assert Commands.valid_solid_target?(ValidComponentTarget.new)
          refute Commands.valid_solid_target?(InvalidTarget.new)
          refute Commands.valid_solid_target?(Object.new)
        end

        def test_dogbone_dialog_stops_before_selection_when_license_is_denied
          CNCPlugins::Licensing::Manager.feature_allowed = false

          assert_nil Commands.open_dialog(:mortise)
        ensure
          CNCPlugins::Licensing::Manager.feature_allowed = true
        end
      end


      class PlacementToolTest < Minitest::Test
        def test_status_text_uses_sketchup_api
          tool = DogboneJoinery::PlacementTool.allocate

          tool.send(:update_status_text, 'Ready')

          assert_equal 'Ready', Sketchup.last_status_text
        end
      end
    end
  end
end
