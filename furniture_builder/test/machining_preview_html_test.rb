# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../presets'
require_relative '../specification'
require_relative '../machining_planner'
require_relative '../machining_preview_html'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class MachiningPreviewHTMLTest < Minitest::Test
        def test_preview_is_vietnamese_machine_independent_and_exposes_callbacks
          html = MachiningPreviewHTML.html(project)

          assert_includes html, '<html lang="vi">'
          assert_includes html, 'SonVu Furniture Builder — Bước 5'
          assert_includes html, 'Xem trước gia công CNC'
          assert_includes html, 'Chế độ chuẩn bị an toàn'
          assert_includes html, 'không khoan/cắt model'
          assert_includes html, 'chưa tạo mã máy CNC'
          assert_includes html, 'refreshMachiningPreview'
          assert_includes html, 'exportMachiningPackage'
          assert_includes html, 'Xuất gói CNC'
          assert_match(/<button type="button" onclick="window\.sketchup\.exportMachiningPackage\(\)">Xuất gói CNC<\/button>/, html)
          assert_includes html, 'closeMachiningPreview'
          refute_match(/Phase|Giai đoạn/i, html)
        end

        def test_preview_renders_panel_maps_coordinates_and_operations
          html = MachiningPreviewHTML.html(project)

          assert_equal 2, html.scan('class="panel-map"').length
          assert_equal 4, html.scan(/class="operation hinge_cup"/).length
          assert_includes html, 'Khoan chén bản lề'
          assert_includes html, 'Mặt gia công: B'
          assert_includes html, 'X (mm)'
          assert_includes html, 'Y (mm)'
          assert_includes html, 'Ø35'
          assert_includes html, 'Sẵn sàng'
          assert_includes html, 'Tham chiếu phụ kiện'
        end

        def test_model_text_and_svg_titles_are_escaped
          settings = Specification.defaults('tu_bep_duoi').merge(
            cabinet_name: 'Tủ <A> & "B"',
            front_material_name: '<MDF & phủ>'
          )
          unsafe_project = MachiningPlanner.project(
            [{ settings: settings, cabinet_id: 'unsafe', cabinet_name: settings[:cabinet_name] }]
          )
          html = MachiningPreviewHTML.html(unsafe_project)

          assert_includes html, 'Tủ &lt;A&gt; &amp; &quot;B&quot;'
          assert_includes html, '&lt;MDF &amp; phủ&gt;'
          refute_includes html, 'Tủ <A>'
          refute_includes html, '<MDF & phủ>'
        end

        def test_empty_plan_explains_how_to_create_supported_operations
          settings = Specification.defaults('ke_tivi').merge(
            include_hinges: false,
            include_handles: false,
            include_drawer_slides: false
          )
          empty = MachiningPlanner.project(
            [{ settings: settings, cabinet_id: 'empty' }],
            rules: MachiningRules.defaults('chi_ban_le')
          )
          html = MachiningPreviewHTML.html(empty)

          assert_includes html, 'Chưa có nguyên công được hỗ trợ'
          assert_includes html, 'bật bản lề chén trong Bước 2'
          refute_includes html, 'class="panel-map"'
        end

        def test_phase_five_b_form_and_face_maps_expose_all_rule_operations
          standard = MachiningPlanner.project(
            [{ settings: Specification.defaults('tu_bep_duoi'), cabinet_id: 'standard' }]
          )
          html = MachiningPreviewHTML.html(standard)

          assert_includes html, 'Quy tắc gia công và mẫu khoan'
          assert_includes html, 'Tiêu chuẩn ván 18 mm'
          assert_includes html, 'Chỉ chốt gỗ và hàng lỗ'
          assert_includes html, 'Tạo hàng lỗ đợt'
          assert_includes html, 'Tạo rãnh hậu'
          assert_includes html, 'calculateMachiningPreview'
          assert_includes html, 'Cập nhật xem trước'
          assert_equal 6, html.scan('class="panel-map"').length
          assert_equal 8, html.scan(/class="operation dowel"/).length
          assert_equal 8, html.scan(/class="operation cam_pocket"/).length
          assert_equal 76, html.scan(/class="operation shelf_pin"/).length
          assert_equal 4, html.scan(/class="operation back_groove"/).length
          assert_includes html, 'Mặt gia công: A'
          assert_includes html, 'Mặt gia công: B'
        end

        def test_opposing_face_collision_is_visible_to_the_customer
          wardrobe = MachiningPlanner.project(
            [{ settings: Specification.defaults('tu_ao'), cabinet_id: 'wardrobe' }]
          )
          html = MachiningPreviewHTML.html(wardrobe)

          assert_operator wardrobe[:invalid_operation_count], :>, 0
          assert_includes html, 'Cần kiểm tra'
          assert_includes html, 'operation shelf_pin invalid'
          assert_includes html, 'Lỗ từ hai mặt đối diện giao nhau'
          assert_match(/<button type="button" disabled onclick="window\.sketchup\.exportMachiningPackage\(\)">Xuất gói CNC<\/button>/, html)
          assert_includes html, 'nguyên công chưa hợp lệ trước khi xuất'
        end

        private

        def project
          @project ||= MachiningPlanner.project(
            [{
              settings: Specification.defaults('tu_bep_duoi'),
              cabinet_id: 'cab-1', cabinet_name: 'Tủ bếp A'
            }],
            scope: 'Các tủ đang chọn',
            rules: MachiningRules.defaults('chi_ban_le')
          )
        end
      end
    end
  end
end
