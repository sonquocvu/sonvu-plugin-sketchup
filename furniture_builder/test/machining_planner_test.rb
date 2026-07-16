# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../presets'
require_relative '../specification'
require_relative '../machining_planner'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class MachiningPlannerTest < Minitest::Test
        def test_base_cabinet_builds_safe_hinge_operations_and_hardware_references
          plan = MachiningPlanner.plan(
            Specification.defaults('tu_bep_duoi'),
            cabinet_id: 'cab-1',
            cabinet_name: 'Tủ bếp A',
            rules: hinge_only_rules
          )

          assert_equal 15, plan[:panel_count]
          assert_equal 4, plan[:operation_count]
          assert_equal 4, plan[:ready_operation_count]
          assert_equal 0, plan[:invalid_operation_count]
          assert_equal 5, plan[:reference_count]
          assert_equal 2, plan[:warnings].length

          machined = plan[:panels].select { |panel| panel[:operations].any? }
          assert_equal 2, machined.length
          machined.each do |panel|
            assert_equal 'front', panel[:kind]
            assert_equal 'Z', panel[:length_axis]
            assert_equal 'X', panel[:width_axis]
            panel[:operations].each do |operation|
              assert_equal 'hinge_cup', operation[:type]
              assert_equal 'B', operation[:face]
              assert_equal 'ready', operation[:status]
              assert_empty operation[:errors]
              assert_operator operation[:x_mm], :>, 0
              assert_operator operation[:y_mm], :>, 0
              assert_operator operation[:x_mm], :<, panel[:length_mm]
              assert_operator operation[:y_mm], :<, panel[:width_mm]
              assert_equal 35.0, operation[:diameter_mm]
              assert_equal 12.0, operation[:depth_mm]
            end
          end
        end

        def test_operation_validation_rejects_depth_and_boundary_errors
          panel = {
            length_mm: 500.0, width_mm: 300.0, thickness_mm: 18.0
          }
          operation = {
            x_mm: 5.0, y_mm: 299.0, diameter_mm: 35.0,
            depth_mm: 20.0, errors: [], status: 'ready'
          }

          MachiningPlanner.validate_operation(operation, panel)

          assert_equal 'invalid', operation[:status]
          assert_equal 3, operation[:errors].length
          assert operation[:errors].any? { |message| message.include?('độ dày') }
          assert operation[:errors].any? { |message| message.include?('chiều dài') }
          assert operation[:errors].any? { |message| message.include?('chiều rộng') }
        end

        def test_project_aggregates_cabinets_and_skips_invalid_settings
          project = MachiningPlanner.project(
            [
              {
                settings: Specification.defaults('tu_bep_duoi'),
                cabinet_id: 'a', cabinet_name: 'Tủ A'
              },
              {
                settings: Specification.defaults('tu_ao').merge(width_mm: 20),
                cabinet_id: 'b', cabinet_name: 'Tủ lỗi'
              },
              {
                settings: nil,
                cabinet_id: 'c', cabinet_name: 'Tủ thiếu dữ liệu'
              }
            ],
            scope: 'Các tủ đang chọn',
            rules: hinge_only_rules
          )

          assert_equal 'Các tủ đang chọn', project[:scope]
          assert_equal 1, project[:cabinet_count]
          assert_equal 15, project[:panel_count]
          assert_equal 4, project[:operation_count]
          assert project[:warnings].any? { |message| message.include?('Bỏ qua Tủ lỗi') }
          assert project[:warnings].any? { |message| message.include?('Bỏ qua Tủ thiếu dữ liệu') }
        end

        def test_cabinet_without_hinges_has_no_machine_operation
          settings = Specification.defaults('ke_tivi').merge(
            include_hinges: false,
            include_handles: false,
            include_drawer_slides: false
          )
          plan = MachiningPlanner.plan(settings, rules: hinge_only_rules)

          assert_equal 0, plan[:operation_count]
          assert_equal 0, plan[:reference_count]
          assert_includes plan[:warnings], 'Tủ chưa có nguyên công khoan được hỗ trợ.'
        end

        def test_standard_rules_generate_connectors_shelf_pins_and_back_grooves
          plan = MachiningPlanner.plan(Specification.defaults('tu_bep_duoi'))

          assert_equal 100, plan[:operation_count]
          assert_equal 100, plan[:ready_operation_count]
          assert_equal 0, plan[:invalid_operation_count]
          assert_equal 4, plan[:operation_types]['hinge_cup']
          assert_equal 8, plan[:operation_types]['dowel']
          assert_equal 8, plan[:operation_types]['cam_pocket']
          assert_equal 76, plan[:operation_types]['shelf_pin']
          assert_equal 4, plan[:operation_types]['back_groove']
          assert_equal 6, plan[:panels].count { |panel| panel[:operations].any? }
          assert plan[:panels].flat_map { |panel| panel[:operations] }.all? do |operation|
            operation[:status] == 'ready'
          end
        end

        def test_opposing_shelf_pin_rows_are_flagged_when_they_cross_a_divider
          plan = MachiningPlanner.plan(Specification.defaults('tu_ao'))
          divider = plan[:panels].find { |panel| panel[:role] == 'divider' }

          assert divider
          assert_operator divider[:operations].count { |operation| operation[:status] == 'invalid' }, :>, 0
          assert_operator plan[:invalid_operation_count], :>, 0
          assert plan[:warnings].any? { |message| message.include?('hai mặt đối diện') }
        end

        private

        def hinge_only_rules
          MachiningRules.defaults('chi_ban_le')
        end
      end
    end
  end
end
