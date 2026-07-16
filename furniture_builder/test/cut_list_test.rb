# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../presets'
require_relative '../specification'
require_relative '../geometry'
require_relative '../cut_list'
require_relative '../cut_list_dialog_html'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class CutListTest < Minitest::Test
        class FakeEntity
          attr_accessor :name
          attr_reader :entities, :definition

          def initialize(name: '', attributes: {}, entities: nil, definition: nil)
            @name = name
            @attributes = attributes
            @entities = entities
            @definition = definition
          end

          def get_attribute(_dictionary, key, default = nil)
            @attributes.fetch(key, default)
          end
        end

        FakeModel = Struct.new(:entities, :selection)

        def test_selected_cabinets_take_precedence_over_whole_model
          selected = cabinet_from_settings('tu_bep_duoi', 'Tủ được chọn', 'cabinet-selected')
          other = cabinet_from_settings('tu_bep_treo', 'Tủ không chọn', 'cabinet-other')
          model = FakeModel.new([selected, other], [selected])

          report = CutList.report_for_model(model)

          assert_equal 'Các tủ đang chọn', report[:scope]
          assert_equal 1, report[:cabinet_count]
          assert_equal 15, report[:board_count]
          assert_equal 9, report[:hardware_count]
          assert report[:board_rows].all? { |row| row[:cabinet_names] == ['Tủ được chọn'] }
        end

        def test_model_scope_finds_cabinets_inside_containers
          cabinet = cabinet_from_settings('tu_bep_treo', 'Tủ treo', 'nested-cabinet')
          container = FakeEntity.new(name: 'Cụm bếp', entities: [cabinet])
          model = FakeModel.new([container], [])

          report = CutList.report_for_model(model)

          assert_equal 'Toàn bộ model', report[:scope]
          assert_equal 1, report[:cabinet_count]
          assert_equal 9, report[:board_count]
          assert_equal 6, report[:hardware_count]
        end

        def test_identical_boards_are_grouped_by_production_properties
          report = CutList.build_report(
            [cabinet_from_settings('tu_bep_duoi', 'Tủ bếp dưới', 'cabinet-1')]
          )
          sides = report[:board_rows].find do |row|
            row[:name] == 'Hông phải / Hông trái'
          end
          doors = report[:board_rows].find do |row|
            row[:name] == 'Cánh phải / Cánh trái'
          end

          assert_equal 2, sides[:quantity]
          assert_in_delta 720.0, sides[:length_mm], 0.001
          assert_in_delta 580.0, sides[:width_mm], 0.001
          assert sides[:edge_front]
          assert_equal 2, doors[:quantity]
          assert doors.values_at(:edge_front, :edge_back, :edge_left, :edge_right).all?
        end

        def test_hardware_is_separated_and_left_right_slides_are_combined
          report = CutList.build_report(
            [cabinet_from_settings('tu_bep_duoi', 'Tủ bếp dưới', 'cabinet-1')]
          )
          quantities = report[:hardware_rows].to_h { |row| [row[:name], row[:quantity]] }

          assert_equal 3, report[:hardware_rows].length
          assert_equal 3, quantities['Tay nắm']
          assert_equal 4, quantities['Bản lề chén']
          assert_equal 2, quantities['Ray ngăn kéo']
        end

        def test_two_identical_cabinets_double_aggregated_quantities
          first = cabinet_from_settings('tu_bep_treo', 'Tủ treo A', 'cabinet-a')
          second = cabinet_from_settings('tu_bep_treo', 'Tủ treo B', 'cabinet-b')
          report = CutList.build_report([first, second])
          sides = report[:board_rows].find { |row| row[:name] == 'Hông phải / Hông trái' }

          assert_equal 2, report[:cabinet_count]
          assert_equal 18, report[:board_count]
          assert_equal 12, report[:hardware_count]
          assert_equal 4, sides[:quantity]
          assert_equal ['Tủ treo A', 'Tủ treo B'], sides[:cabinet_names]
          assert_equal [2, 2], sides[:cabinet_breakdown].map { |item| item[:quantity] }
        end

        def test_panel_metadata_falls_back_to_component_definition
          definition = FakeEntity.new(attributes: panel_attributes(
            name: 'Chi tiết cũ', kind: 'carcass', role: 'legacy',
            length: 500, width: 300, thickness: 18, material: 'MDF cũ'
          ))
          panel = FakeEntity.new(name: 'Instance cũ', attributes: {
            Geometry::PANEL_ATTRIBUTE => true
          }, definition: definition)
          cabinet = fake_cabinet('Tủ cũ', 'old-cabinet', [panel])

          report = CutList.build_report([cabinet])
          row = report[:board_rows].first

          assert_equal 1, report[:board_count]
          assert_equal 'Chi tiết cũ', row[:name]
          assert_equal 'MDF cũ', row[:material_name]
          assert_in_delta 500.0, row[:length_mm], 0.001
        end

        def test_invalid_panel_metadata_is_skipped_with_vietnamese_warning
          panel = FakeEntity.new(name: 'Tấm lỗi', attributes: {
            Geometry::PANEL_ATTRIBUTE => true,
            'part_name_vi' => 'Tấm lỗi',
            'finished_length_mm' => 0,
            'finished_width_mm' => 300,
            'thickness_mm' => 18
          })
          report = CutList.build_report([fake_cabinet('Tủ kiểm tra', 'bad-cabinet', [panel])])

          assert_equal 0, report[:part_count]
          assert_equal 1, report[:warnings].length
          assert_match(/Bỏ qua Tấm lỗi.*thiếu kích thước/i, report[:warnings].first)
        end

        def test_html_is_vietnamese_separates_sections_and_escapes_names
          cabinet = cabinet_from_settings('tu_bep_duoi', '<Tủ & bếp>', 'cabinet-html')
          report = CutList.build_report([cabinet], scope: 'Các tủ đang chọn')
          html = CutListDialogHTML.html(report)

          assert_includes html, '<html lang="vi">'
          assert_includes html, 'Danh sách chi tiết'
          assert_includes html, 'Chi tiết ván'
          assert_includes html, 'Phụ kiện'
          assert_includes html, 'Dán cạnh'
          assert_includes html, '&lt;Tủ &amp; bếp&gt;'
          refute_includes html, '<Tủ & bếp>'
          assert_includes html, 'Bước 3'
          assert_includes html, 'Bước 4'
          refute_match(/Phase|Giai đoạn/i, html)
          assert_includes html, 'Xuất CSV'
          assert_includes html, 'exportCutList'
          assert_includes html, 'Dự toán chi phí'
          assert_includes html, 'openCostEstimate'
          assert_includes html, 'Tối ưu cắt ván'
          assert_includes html, 'openSheetOptimization'
        end

        private

        def cabinet_from_settings(preset_key, name, cabinet_id)
          settings = Specification.defaults(preset_key).merge(cabinet_name: name)
          panels = Specification.parts(settings).map do |part|
            FakeEntity.new(
              name: part.name,
              attributes: panel_attributes_from_part(part, cabinet_id)
            )
          end
          fake_cabinet(name, cabinet_id, panels)
        end

        def fake_cabinet(name, cabinet_id, panels)
          FakeEntity.new(
            name: name,
            entities: panels,
            attributes: {
              Geometry::CABINET_ATTRIBUTE => true,
              Geometry::CABINET_ID_ATTRIBUTE => cabinet_id,
              'furniture_name_vi' => name
            }
          )
        end

        def panel_attributes_from_part(part, cabinet_id)
          panel_attributes(
            name: part.name,
            kind: part.kind,
            role: part.role,
            length: part.finished_length,
            width: part.finished_width,
            thickness: part.thickness,
            material: part.material_name || Specification.defaults[:material_name]
          ).merge(
            Geometry::PANEL_ATTRIBUTE => true,
            Geometry::CABINET_ID_ATTRIBUTE => cabinet_id,
            'part_key' => part.key,
            'grain_direction' => part.grain_direction,
            'grain_axis' => part.grain_axis,
            'geometry_shape' => part.shape,
            'edge_band_front' => part.edge_banding[:front],
            'edge_band_back' => part.edge_banding[:back],
            'edge_band_left' => part.edge_banding[:left],
            'edge_band_right' => part.edge_banding[:right],
            'drawer_index' => part.assembly_index,
            'owner_part_key' => part.owner_part_key,
            'hardware_type' => part.kind == 'hardware' ? part.role : nil
          )
        end

        def panel_attributes(name:, kind:, role:, length:, width:, thickness:, material:)
          {
            Geometry::PANEL_ATTRIBUTE => true,
            'part_name_vi' => name,
            'part_kind' => kind,
            'part_role' => role,
            'finished_length_mm' => length,
            'finished_width_mm' => width,
            'thickness_mm' => thickness,
            'material_name' => material
          }
        end
      end
    end
  end
end
