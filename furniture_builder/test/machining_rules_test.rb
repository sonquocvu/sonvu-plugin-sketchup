# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../machining_rules'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class MachiningRulesTest < Minitest::Test
        def test_default_preset_exposes_phase_five_b_rules
          rules = MachiningRules.normalize

          assert_equal MachiningRules::DEFAULT_KEY, rules[:preset_key]
          assert rules[:include_connectors]
          assert rules[:include_cam_pockets]
          assert rules[:include_shelf_pins]
          assert rules[:include_back_grooves]
          assert_equal 8.0, rules[:dowel_diameter_mm]
          assert_equal 32.0, rules[:shelf_pin_pitch_mm]
          assert_equal 10.0, rules[:back_groove_width_mm]
        end

        def test_named_preset_can_disable_cam_pockets
          rules = MachiningRules.normalize(preset_key: 'chi_chot_go')

          assert rules[:include_connectors]
          refute rules[:include_cam_pockets]
          assert rules[:include_shelf_pins]
        end

        def test_submitted_strings_are_normalized
          rules = MachiningRules.normalize(
            preset_key: 'tuy_chinh',
            include_shelf_pins: 'false',
            dowel_diameter_mm: '10',
            back_groove_depth_mm: '7.5'
          )

          refute rules[:include_shelf_pins]
          assert_equal 10.0, rules[:dowel_diameter_mm]
          assert_equal 7.5, rules[:back_groove_depth_mm]
        end

        def test_invalid_rule_values_return_vietnamese_errors
          error = assert_raises(ArgumentError) do
            MachiningRules.normalize(shelf_pin_pitch_mm: 0)
          end

          assert_match(/bước hàng lỗ/i, error.message)
          assert_raises(ArgumentError) { MachiningRules.normalize(dowel_depth_mm: 'abc') }
        end

        def test_cam_pockets_are_disabled_when_connector_rules_are_disabled
          rules = MachiningRules.normalize(
            include_connectors: false,
            include_cam_pockets: true
          )

          refute rules[:include_connectors]
          refute rules[:include_cam_pockets]
        end
      end
    end
  end
end
