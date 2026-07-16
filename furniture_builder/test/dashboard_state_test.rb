# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../dashboard_state'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class DashboardStateTest < Minitest::Test
        def test_empty_model_enables_creation_but_not_downstream_workflows
          state = DashboardState.build(
            report: report(cabinet_count: 0, board_count: 0),
            editable_selection: false,
            license_view: license(true),
            version: '0.16.0'
          )

          assert state[:actions][:create]
          refute state[:actions][:edit_carcass]
          refute state[:actions][:cut_list]
          refute state[:actions][:cost_estimate]
          refute state[:actions][:sheet_optimization]
          refute state[:actions][:phase_five]
          assert_equal 'Model chưa có tủ nội thất SonVu.', state[:selection_message]
          assert_equal '0.16.0', state[:version]
        end

        def test_one_editable_selection_enables_every_existing_workflow
          state = DashboardState.build(
            report: report(cabinet_count: 1, board_count: 15, hardware_count: 9, part_count: 24),
            editable_selection: true,
            selected_cabinet_name: 'Tủ bếp A',
            license_view: license(true)
          )

          assert state[:actions].values_at(
            :create, :edit_carcass, :edit_fittings, :cut_list,
            :cost_estimate, :sheet_optimization, :phase_five
          ).all?
          assert_equal 'Đang chọn: Tủ bếp A', state[:selection_message]
          assert_equal 24, state[:part_count]
        end

        def test_expired_license_locks_workflows_but_preserves_project_summary
          state = DashboardState.build(
            report: report(cabinet_count: 2, board_count: 30),
            editable_selection: true,
            license_view: license(false).merge(state: 'trial_expired')
          )

          refute state[:license][:licensed]
          refute state[:actions].values.any?
          assert_equal 2, state[:cabinet_count]
          assert_equal 30, state[:board_count]
        end

        def test_selected_report_scope_explains_multiple_selected_cabinets
          state = DashboardState.build(
            report: report(cabinet_count: 3, board_count: 25, scope: 'Các tủ đang chọn'),
            editable_selection: false,
            license_view: license(true)
          )

          assert_equal 'Đang dùng 3 tủ trong vùng chọn.', state[:selection_message]
          assert state[:actions][:cut_list]
          refute state[:actions][:edit_carcass]
        end

        private

        def report(overrides = {})
          {
            scope: 'Toàn bộ model', cabinet_count: 1, board_count: 10,
            hardware_count: 4, part_count: 14, warnings: []
          }.merge(overrides)
        end

        def license(valid)
          {
            licensed: valid, state: valid ? 'trial' : 'trial_expired',
            message: valid ? 'Còn 14 ngày.' : 'Đã hết hạn.', customer: '', expires_at: ''
          }
        end
      end
    end
  end
end
