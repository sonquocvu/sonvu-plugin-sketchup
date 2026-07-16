# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../dashboard_state'
require_relative '../dashboard_html'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class DashboardHTMLTest < Minitest::Test
        def test_dashboard_is_vietnamese_and_exposes_the_complete_workflow
          html = DashboardHTML.html(state)

          assert_includes html, '<html lang="vi">'
          assert_includes html, 'Trung tâm nội thất SonVu'
          assert_includes html, 'Bước 1'
          assert_includes html, 'Thiết kế thùng tủ'
          assert_includes html, 'Mặt cánh, ngăn kéo và phụ kiện'
          assert_includes html, 'Danh sách sản xuất và báo giá'
          assert_includes html, 'Tối ưu và xuất phương án cắt'
          assert_includes html, 'Gia công CNC'
          assert_includes html, 'Xem trước gia công'
          assert_includes html, 'dashboardCreateFurniture'
          assert_includes html, 'dashboardEditCarcass'
          assert_includes html, 'dashboardEditFittings'
          assert_includes html, 'dashboardOpenCutList'
          assert_includes html, 'dashboardOpenCostEstimate'
          assert_includes html, 'dashboardOpenSheetOptimization'
          assert_includes html, 'dashboardOpenMachiningPreview'
          assert_includes html, 'refreshFurnitureDashboard'
          assert_includes html, 'openDashboardLicense'
          refute_match(/Phase|Giai đoạn/i, html)
        end

        def test_disabled_actions_and_license_warning_are_visible
          locked = state(
            report: report.merge(cabinet_count: 0, board_count: 0),
            editable_selection: false,
            license_view: license.merge(licensed: false, message: 'Đã hết hạn.')
          )
          html = DashboardHTML.html(locked)

          assert_includes html, 'Tính năng đang bị khóa'
          assert_includes html, 'Đã hết hạn.'
          assert_match(/disabled onclick="window\.sketchup\.dashboardCreateFurniture/, html)
          assert_match(/disabled onclick="window\.sketchup\.dashboardOpenCutList/, html)
          assert_match(/disabled onclick="window\.sketchup\.dashboardOpenMachiningPreview/, html)
        end

        def test_model_and_license_text_is_html_escaped
          unsafe = state(
            selected_cabinet_name: 'Tủ <A> & "B"',
            license_view: license.merge(customer: '<Khách & hàng>')
          )
          html = DashboardHTML.html(unsafe)

          assert_includes html, 'Tủ &lt;A&gt; &amp; &quot;B&quot;'
          assert_includes html, '&lt;Khách &amp; hàng&gt;'
          refute_includes html, 'Tủ <A>'
          refute_includes html, '<Khách & hàng>'
        end

        private

        def state(overrides = {})
          inputs = {
            report: report,
            editable_selection: true,
            selected_cabinet_name: 'Tủ bếp A',
            license_view: license,
            version: '0.16.0'
          }.merge(overrides)
          DashboardState.build(**inputs)
        end

        def report
          {
            scope: 'Các tủ đang chọn', cabinet_count: 1, board_count: 15,
            hardware_count: 9, part_count: 24, warnings: []
          }
        end

        def license
          {
            licensed: true, state: 'trial', message: 'Còn 14 ngày.',
            customer: '', expires_at: '30/07/2026'
          }
        end
      end
    end
  end
end
