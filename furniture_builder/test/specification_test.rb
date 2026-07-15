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
  end
end

require_relative '../presets'
require_relative '../specification'
require_relative '../dialog_html'
require_relative '../dialog'
require_relative '../geometry'

module UI
  class << self
    attr_reader :last_inputbox_lengths

    def inputbox(prompts, defaults, lists, _title)
      @last_inputbox_lengths = [prompts.length, defaults.length, lists.length]
      false
    end
  end
end

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class SpecificationTest < Minitest::Test
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

        def test_vietnamese_phase_one_presets_are_available
          labels = Presets.options.to_h.values

          assert_includes labels, 'Tủ bếp dưới'
          assert_includes labels, 'Tủ bếp treo'
          assert_includes labels, 'Tủ áo'
          assert_includes labels, 'Kệ tivi'
        end

        def test_base_kitchen_cabinet_builds_expected_parts
          settings = Specification.defaults('tu_bep_duoi')
          parts = Specification.parts(settings)

          assert_nil Specification.validate(settings)
          assert_equal 24, parts.length
          assert_equal(
            %w[
              back bottom door_left door_right drawer_back drawer_bottom drawer_front
              drawer_inner_front drawer_side_left drawer_side_right drawer_slide_left
              drawer_slide_right handle handle handle hinge_cup hinge_cup hinge_cup hinge_cup
              plinth shelf side_left side_right top
            ],
            parts.map(&:role).sort
          )

          bottom = parts.find { |part| part.role == 'bottom' }
          plinth = parts.find { |part| part.role == 'plinth' }
          assert_in_delta 100.0, bottom.z, 0.001
          assert_in_delta 50.0, plinth.y, 0.001
          assert_in_delta 764.0, plinth.size_x, 0.001
        end

        def test_wall_cabinet_has_no_plinth_and_two_shelves
          parts = Specification.parts(Specification.defaults('tu_bep_treo'))

          assert_equal 2, parts.count { |part| part.role == 'shelf' }
          assert_equal 2, parts.count { |part| part.kind == 'front' }
          refute parts.any? { |part| part.role == 'plinth' }
          assert parts.any? { |part| part.role == 'back' }
        end

        def test_shelves_are_split_into_bays_around_vertical_dividers
          parts = Specification.parts(Specification.defaults('tu_ao'))
          dividers = parts.select { |part| part.role == 'divider' }
          shelves = parts.select { |part| part.role == 'shelf' }

          assert_equal 1, dividers.length
          assert_equal 8, shelves.length
          assert_equal 2, shelves.select { |part| part.name.start_with?('Đợt 1') }.length

          divider = dividers.first
          first_bay = shelves.find { |part| part.key == 'dot_1_1' }
          second_bay = shelves.find { |part| part.key == 'dot_1_2' }
          assert_in_delta divider.x, first_bay.x + first_bay.size_x, 0.001
          assert_in_delta divider.x + divider.size_x, second_bay.x, 0.001
        end

        def test_tv_cabinet_creates_three_shelf_segments_for_two_dividers
          parts = Specification.parts(Specification.defaults('ke_tivi'))

          assert_equal 2, parts.count { |part| part.role == 'divider' }
          assert_equal 3, parts.count { |part| part.role == 'shelf' }
          assert_equal 14, parts.length
          assert_equal ['Cánh lật'], parts.select { |part| part.kind == 'front' }.map(&:name)
        end

        def test_panel_metadata_dimensions_follow_installed_orientation
          parts = Specification.parts(Specification.defaults('tu_bep_duoi'))
          side = parts.find { |part| part.role == 'side_left' }
          top = parts.find { |part| part.role == 'top' }

          assert_in_delta 720.0, side.finished_length, 0.001
          assert_in_delta 580.0, side.finished_width, 0.001
          assert_in_delta 18.0, side.thickness, 0.001
          assert_equal 'dọc', side.grain_direction
          assert side.edge_banding[:front]

          assert_in_delta 764.0, top.finished_length, 0.001
          assert_in_delta 571.0, top.finished_width, 0.001
          assert_equal 'ngang', top.grain_direction
        end

        def test_disabling_back_uses_full_depth_and_omits_back_panel
          settings = Specification.defaults('tu_bep_treo').merge(include_back: false)
          parts = Specification.parts(settings)
          top = parts.find { |part| part.role == 'top' }

          refute parts.any? { |part| part.role == 'back' }
          assert_in_delta settings[:depth_mm], top.size_y, 0.001
        end

        def test_string_input_is_normalized_from_vietnamese_dialog_values
          settings = Specification.normalize(
            'preset_key' => 'ke_tivi',
            'width_mm' => '2000',
            'shelf_count' => '2',
            'divider_count' => '3',
            'include_back' => 'Có',
            'edge_band_front' => 'Không',
            'front_layout' => Presets::FRONT_THREE_DRAWERS,
            'front_gap_mm' => '2.5',
            'front_edge_band_all' => 'Có',
            'include_drawer_boxes' => 'Có',
            'drawer_side_clearance_mm' => '12.5',
            'drawer_box_depth_mm' => '0',
            'include_handles' => 'Có',
            'include_hinges' => 'Không',
            'hinge_count' => '3',
            'include_drawer_slides' => 'Có'
          )

          assert_in_delta 2000.0, settings[:width_mm], 0.001
          assert_equal 2, settings[:shelf_count]
          assert_equal 3, settings[:divider_count]
          assert settings[:include_back]
          refute settings[:edge_band_front]
          assert_equal Presets::FRONT_THREE_DRAWERS, settings[:front_layout]
          assert_in_delta 2.5, settings[:front_gap_mm], 0.001
          assert settings[:front_edge_band_all]
          assert settings[:include_drawer_boxes]
          assert_in_delta 12.5, settings[:drawer_side_clearance_mm], 0.001
          assert_in_delta 0.0, settings[:drawer_box_depth_mm], 0.001
          assert settings[:include_handles]
          refute settings[:include_hinges]
          assert_equal 3, settings[:hinge_count]
          assert settings[:include_drawer_slides]
        end

        def test_invalid_dimensions_return_vietnamese_error
          settings = Specification.defaults.merge(width_mm: 30, panel_thickness_mm: 18)
          error = Specification.validate(settings)

          assert_match(/Chiều rộng tủ/, error)
          assert_raises(ArgumentError) { Specification.parts(settings) }
        end

        def test_non_numeric_dimensions_are_rejected_without_crashing
          settings = Specification.defaults.merge(depth_mm: 'không phải số')
          error = Specification.validate(settings)

          assert_match(/kích thước/i, error)
        end

        def test_html_dialog_is_vietnamese_and_exposes_phase_one_fields
          html = DialogHTML.html(Specification.defaults('tu_ao'), :create)

          assert_includes html, '<html lang="vi">'
          assert_includes html, 'Tạo tủ nội thất'
          assert_includes html, 'Số hàng đợt mỗi khoang'
          assert_includes html, 'Số vách đứng'
          assert_includes html, 'Đánh dấu dán cạnh trước'
          assert_includes html, 'Bố trí mặt trước'
          assert_includes html, 'Một ngăn kéo trên + hai cánh dưới'
          assert_includes html, 'Kiểu phủ mặt cánh'
          assert_includes html, 'dán cạnh bốn phía'
          assert_includes html, 'Tạo hộp ngăn kéo'
          assert_includes html, 'Độ hở ray mỗi bên'
          assert_includes html, 'Sâu hộp (0 = tự động)'
          assert_includes html, 'Phụ kiện cơ bản'
          assert_includes html, 'Tạo tay nắm'
          assert_includes html, 'Tạo mẫu bản lề chén'
          assert_includes html, 'Tạo ray cho hộp ngăn kéo'
          Presets.options.each { |_key, label| assert_includes html, label }
        end

        def test_html_json_escapes_script_breakout_characters
          html = DialogHTML.html(
            Specification.defaults.merge(material_name: '</script><script>alert(1)</script>'),
            :edit
          )

          refute_includes html, '</script><script>alert(1)</script>'
          assert_includes html, '\\u003c/script\\u003e'
        end

        def test_panel_box_has_six_faces_without_duplicate_loop_points
          entities = FakeEntities.new

          Geometry.add_box(entities, 100.0, 50.0, 18.0)

          assert_equal 6, entities.faces.length
          all_points = entities.faces.flatten
          assert_equal [0, 100.0], all_points.map(&:x).uniq.sort
          assert_equal [0, 50.0], all_points.map(&:y).uniq.sort
          assert_equal [0, 18.0], all_points.map(&:z).uniq.sort
        end

        def test_hinge_cylinder_has_closed_faces_without_duplicate_loop_points
          entities = FakeEntities.new

          Geometry.add_cylinder_y(entities, 35.0, 12.0, 24)

          assert_equal 26, entities.faces.length
          assert entities.faces.all? { |points| points.map { |point| [point.x, point.y, point.z] }.uniq.length == points.length }
          assert_equal [0, 12.0], entities.faces.flatten.map(&:y).uniq.sort
        end

        def test_legacy_phase_one_settings_do_not_gain_fronts_during_edit
          legacy = Specification.defaults('tu_bep_duoi').reject do |key, _value|
            Presets::DEFAULT_FRONT_SETTINGS.key?(key) ||
              Presets::DEFAULT_DRAWER_SETTINGS.key?(key) ||
              Presets::DEFAULT_HARDWARE_SETTINGS.key?(key)
          end
          normalized = Specification.normalize(legacy)

          assert_equal Presets::FRONT_NONE, normalized[:front_layout]
          assert_equal 7, Specification.parts(normalized).length
          refute Specification.parts(normalized).any? { |part| part.kind == 'front' }
        end

        def test_overlay_double_doors_use_perimeter_and_center_gaps
          settings = Specification.defaults('tu_bep_treo')
          doors = Specification.parts(settings).select { |part| part.kind == 'front' }
          left, right = doors

          assert_in_delta 2.0, left.x, 0.001
          assert_in_delta(-18.0, left.y, 0.001)
          assert_in_delta 397.0, left.size_x, 0.001
          assert_in_delta 401.0, right.x, 0.001
          assert_in_delta 716.0, left.size_z, 0.001
          assert_in_delta 2.0, right.x - (left.x + left.size_x), 0.001
        end

        def test_inset_double_doors_fit_inside_carcass_opening
          settings = Specification.defaults('tu_bep_treo').merge(front_cover_mode: Presets::COVER_INSET)
          left, right = Specification.parts(settings).select { |part| part.kind == 'front' }

          assert_in_delta 20.0, left.x, 0.001
          assert_in_delta 0.0, left.y, 0.001
          assert_in_delta 379.0, left.size_x, 0.001
          assert_in_delta 401.0, right.x, 0.001
          assert_in_delta 20.0, left.z, 0.001
          assert_in_delta 680.0, left.size_z, 0.001
        end

        def test_top_drawer_and_lower_doors_fill_front_domain_without_overlap
          settings = Specification.defaults('tu_bep_duoi')
          fronts = Specification.parts(settings).select { |part| part.kind == 'front' }
          drawer = fronts.find { |part| part.role == 'drawer_front' }
          doors = fronts.select { |part| part.role.start_with?('door_') }

          assert_equal 3, fronts.length
          assert_in_delta 160.0, drawer.size_z, 0.001
          assert_in_delta 558.0, drawer.z, 0.001
          assert doors.all? { |door| (door.size_z - 454.0).abs < 0.001 }
          assert_in_delta 2.0, drawer.z - (doors.first.z + doors.first.size_z), 0.001
        end

        def test_equal_drawer_fronts_are_numbered_from_top_to_bottom
          settings = Specification.defaults('tu_bep_duoi').merge(front_layout: Presets::FRONT_THREE_DRAWERS)
          drawers = Specification.parts(settings).select { |part| part.role == 'drawer_front' }

          assert_equal ['Mặt ngăn kéo 1', 'Mặt ngăn kéo 2', 'Mặt ngăn kéo 3'], drawers.map(&:name)
          assert_operator drawers[0].z, :>, drawers[1].z
          assert_operator drawers[1].z, :>, drawers[2].z
          assert drawers.map(&:size_z).all? { |height| (height - 204.0).abs < 0.001 }
        end

        def test_fronts_have_separate_material_grain_and_four_edge_metadata
          settings = Specification.defaults('tu_bep_duoi')
          fronts = Specification.parts(settings).select { |part| part.kind == 'front' }
          door = fronts.find { |part| part.role == 'door_left' }
          drawer = fronts.find { |part| part.role == 'drawer_front' }

          assert_equal settings[:front_material_name], door.material_name
          assert_equal 'dọc', door.grain_direction
          assert_equal 'ngang', drawer.grain_direction
          assert_equal 'length', door.grain_axis
          assert_equal 'width', drawer.grain_axis
          assert door.edge_banding.values.all?
          assert drawer.edge_banding.values.all?
        end

        def test_forced_carcass_grain_records_axis_relative_to_finished_dimensions
          horizontal = Specification.defaults('tu_bep_duoi').merge(
            grain_mode: Presets::GRAIN_HORIZONTAL
          )
          vertical = Specification.defaults('tu_bep_duoi').merge(
            grain_mode: Presets::GRAIN_VERTICAL
          )
          horizontal_parts = Specification.parts(horizontal)
          vertical_parts = Specification.parts(vertical)

          assert_equal 'width', horizontal_parts.find { |part| part.role == 'side_left' }.grain_axis
          assert_equal 'length', horizontal_parts.find { |part| part.role == 'top' }.grain_axis
          assert_equal 'length', vertical_parts.find { |part| part.role == 'side_left' }.grain_axis
          assert_equal 'width', vertical_parts.find { |part| part.role == 'top' }.grain_axis
        end

        def test_front_validation_rejects_impossible_layouts_in_vietnamese
          settings = Specification.defaults('tu_bep_duoi').merge(
            front_layout: Presets::FRONT_TOP_DRAWER_DOUBLE_DOOR,
            top_drawer_height_mm: 700
          )

          assert_match(/không đủ/i, Specification.validate(settings))
          assert_raises(ArgumentError) { Specification.parts(settings) }
        end

        def test_native_inputbox_phase_two_arrays_remain_aligned
          result = Dialog.show_inputbox(Specification.defaults('tu_bep_duoi'), :create)

          assert_nil result
          assert_equal [48, 48, 48], UI.last_inputbox_lengths
        end

        def test_default_base_cabinet_creates_one_five_panel_drawer_box
          settings = Specification.defaults('tu_bep_duoi')
          parts = Specification.parts(settings)
          drawer_parts = parts.select { |part| part.kind == 'drawer_box' }

          assert_equal 5, drawer_parts.length
          assert_equal(
            %w[drawer_back drawer_bottom drawer_inner_front drawer_side_left drawer_side_right],
            drawer_parts.map(&:role).sort
          )
          assert drawer_parts.all? { |part| part.assembly_index == 1 }

          left = drawer_parts.find { |part| part.role == 'drawer_side_left' }
          right = drawer_parts.find { |part| part.role == 'drawer_side_right' }
          assert_in_delta 30.5, left.x, 0.001
          assert_in_delta 754.5, right.x, 0.001
          assert_in_delta 531.0, left.size_y, 0.001
          assert_in_delta 120.0, left.size_z, 0.001
        end

        def test_slide_clearance_is_applied_once_per_side
          settings = Specification.defaults('tu_bep_duoi')
          drawer_parts = Specification.parts(settings).select { |part| part.kind == 'drawer_box' }
          left = drawer_parts.find { |part| part.role == 'drawer_side_left' }
          right = drawer_parts.find { |part| part.role == 'drawer_side_right' }
          internal_left = settings[:panel_thickness_mm]
          internal_right = settings[:width_mm] - settings[:panel_thickness_mm]

          assert_in_delta 12.5, left.x - internal_left, 0.001
          assert_in_delta 12.5, internal_right - (right.x + right.size_x), 0.001
        end

        def test_three_drawer_fronts_create_three_linked_drawer_boxes
          settings = Specification.defaults('tu_bep_duoi').merge(
            front_layout: Presets::FRONT_THREE_DRAWERS,
            include_drawer_boxes: true,
            drawer_box_height_mm: 100
          )
          parts = Specification.parts(settings)
          fronts = parts.select { |part| part.role == 'drawer_front' }
          boxes = parts.select { |part| part.kind == 'drawer_box' }

          assert_equal 3, fronts.length
          assert_equal 15, boxes.length
          assert_equal [1, 2, 3], fronts.map(&:assembly_index)
          assert_equal [1, 2, 3], boxes.map(&:assembly_index).uniq
          fronts.each do |front|
            box_side = boxes.find do |part|
              part.assembly_index == front.assembly_index && part.role == 'drawer_side_left'
            end
            assert_in_delta front.z + ((front.size_z - 100) / 2.0), box_side.z, 0.001
          end
        end

        def test_manual_drawer_depth_overrides_automatic_depth
          automatic = Specification.defaults('tu_bep_duoi')
          manual = automatic.merge(drawer_box_depth_mm: 450)
          automatic_side = Specification.parts(automatic).find { |part| part.role == 'drawer_side_left' }
          manual_side = Specification.parts(manual).find { |part| part.role == 'drawer_side_left' }

          assert_in_delta 531.0, automatic_side.size_y, 0.001
          assert_in_delta 450.0, manual_side.size_y, 0.001
        end

        def test_drawer_box_panels_use_separate_material_and_finished_dimensions
          settings = Specification.defaults('tu_bep_duoi')
          bottom = Specification.parts(settings).find { |part| part.role == 'drawer_bottom' }

          assert_equal settings[:drawer_material_name], bottom.material_name
          assert_equal 'drawer_box', bottom.kind
          assert_in_delta 709.0, bottom.finished_length, 0.001
          assert_in_delta 501.0, bottom.finished_width, 0.001
          assert_in_delta 6.0, bottom.thickness, 0.001
          refute bottom.edge_banding.values.any?
        end

        def test_phase_two_a_settings_do_not_gain_drawer_boxes_during_edit
          phase_two_a = Specification.defaults('tu_bep_duoi').reject do |key, _value|
            Presets::DEFAULT_DRAWER_SETTINGS.key?(key) ||
              Presets::DEFAULT_HARDWARE_SETTINGS.key?(key)
          end
          normalized = Specification.normalize(phase_two_a)

          refute normalized[:include_drawer_boxes]
          refute Specification.parts(normalized).any? { |part| part.kind == 'drawer_box' }
          assert Specification.parts(normalized).any? { |part| part.kind == 'front' }
        end

        def test_drawer_validation_requires_drawer_front_layout
          settings = Specification.defaults('tu_bep_treo').merge(include_drawer_boxes: true)

          assert_match(/bố trí mặt trước có ngăn kéo/i, Specification.validate(settings))
        end

        def test_drawer_validation_rejects_excessive_depth_and_height
          deep = Specification.defaults('tu_bep_duoi').merge(drawer_box_depth_mm: 550)
          tall = Specification.defaults('tu_bep_duoi').merge(drawer_box_height_mm: 170)

          assert_match(/vượt quá chiều sâu/i, Specification.validate(deep))
          assert_match(/nhỏ hơn chiều cao mỗi mặt ngăn kéo/i, Specification.validate(tall))
        end

        def test_default_base_cabinet_creates_linked_phase_two_c_hardware
          settings = Specification.defaults('tu_bep_duoi')
          hardware = Specification.parts(settings).select { |part| part.kind == 'hardware' }

          assert_equal 9, hardware.length
          assert_equal 3, hardware.count { |part| part.role == 'handle' }
          assert_equal 4, hardware.count { |part| part.role == 'hinge_cup' }
          assert_equal 1, hardware.count { |part| part.role == 'drawer_slide_left' }
          assert_equal 1, hardware.count { |part| part.role == 'drawer_slide_right' }
          assert hardware.all? { |part| part.material_name == settings[:hardware_material_name] }
          assert hardware.all? { |part| !part.owner_part_key.to_s.empty? }
          assert hardware.select { |part| part.role == 'hinge_cup' }.all? { |part| part.shape == 'cylinder_y' }
        end

        def test_handles_follow_door_and_drawer_orientation
          settings = Specification.defaults('tu_bep_duoi')
          parts = Specification.parts(settings)
          handles = parts.select { |part| part.role == 'handle' }
          left = handles.find { |part| part.owner_part_key == 'canh_trai_duoi' }
          right = handles.find { |part| part.owner_part_key == 'canh_phai_duoi' }
          drawer = handles.find { |part| part.owner_part_key == 'mat_ngan_keo_tren' }

          assert_operator left.size_z, :>, left.size_x
          assert_operator right.size_z, :>, right.size_x
          assert_operator drawer.size_x, :>, drawer.size_z
          assert_in_delta settings[:front_gap_mm] + (2 * settings[:handle_edge_offset_mm]) -
                          settings[:handle_width_mm],
                          right.x - (left.x + left.size_x), 0.001
          assert_in_delta(
            -settings[:front_thickness_mm] - settings[:handle_projection_mm],
            drawer.y,
            0.001
          )
        end

        def test_hinge_count_is_automatic_or_user_selected
          base = Specification.parts(Specification.defaults('tu_bep_duoi'))
          wardrobe = Specification.parts(Specification.defaults('tu_ao'))
          manual_settings = Specification.defaults('tu_bep_treo').merge(hinge_count: 3)
          manual = Specification.parts(manual_settings)

          assert_equal 4, base.count { |part| part.role == 'hinge_cup' }
          assert_equal 10, wardrobe.count { |part| part.role == 'hinge_cup' }
          assert_equal 6, manual.count { |part| part.role == 'hinge_cup' }
        end

        def test_each_drawer_box_receives_two_linked_slides
          settings = Specification.defaults('tu_bep_duoi').merge(
            front_layout: Presets::FRONT_THREE_DRAWERS,
            drawer_box_height_mm: 100
          )
          slides = Specification.parts(settings).select do |part|
            part.role == 'drawer_slide_left' || part.role == 'drawer_slide_right'
          end

          assert_equal 6, slides.length
          assert_equal [1, 2, 3], slides.map(&:assembly_index).uniq
          assert slides.all? { |part| part.size_x == settings[:drawer_slide_thickness_mm] }
          assert slides.all? { |part| part.size_y == 531.0 }
        end

        def test_phase_two_b_settings_do_not_gain_hardware_during_edit
          phase_two_b = Specification.defaults('tu_bep_duoi').reject do |key, _value|
            Presets::DEFAULT_HARDWARE_SETTINGS.key?(key)
          end
          normalized = Specification.normalize(phase_two_b)

          refute normalized[:include_handles]
          refute normalized[:include_hinges]
          refute normalized[:include_drawer_slides]
          refute Specification.parts(normalized).any? { |part| part.kind == 'hardware' }
          assert Specification.parts(normalized).any? { |part| part.kind == 'drawer_box' }
        end

        def test_hardware_validation_rejects_impossible_dimensions
          long_handle = Specification.defaults('tu_bep_duoi').merge(handle_length_mm: 900)
          deep_hinge = Specification.defaults('tu_bep_duoi').merge(hinge_cup_depth_mm: 20)
          thick_slide = Specification.defaults('tu_bep_duoi').merge(drawer_slide_thickness_mm: 13)
          long_slide = Specification.defaults('tu_bep_duoi').merge(drawer_slide_length_mm: 550)

          assert_match(/Tay nắm không vừa/i, Specification.validate(long_handle))
          assert_match(/không được lớn hơn độ dày mặt cánh/i, Specification.validate(deep_hinge))
          assert_match(/không được lớn hơn độ hở ray/i, Specification.validate(thick_slide))
          assert_match(/vượt quá chiều sâu hộp/i, Specification.validate(long_slide))
        end
      end
    end
  end
end
