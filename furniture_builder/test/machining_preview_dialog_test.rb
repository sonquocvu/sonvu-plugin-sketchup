# frozen_string_literal: true

require 'json'
require 'minitest/autorun'

require_relative '../../constants'
require_relative '../presets'
require_relative '../specification'
require_relative '../geometry'
require_relative '../cut_list'
require_relative '../machining_planner'
require_relative '../machining_preview_dialog'

module Sketchup
  class << self
    def read_default(section, key, fallback = nil)
      (@defaults || {}).fetch([section, key], fallback)
    end

    def write_default(section, key, value)
      @defaults ||= {}
      @defaults[[section, key]] = value
    end

    def reset_defaults
      @defaults = {}
    end
  end
end

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class MachiningPreviewDialogTest < Minitest::Test
        FakeModel = Struct.new(:selection, :entities)

        class FakeCabinet
          attr_reader :name

          def initialize(settings, id)
            @name = settings[:cabinet_name]
            @attributes = {
              Geometry::CABINET_ATTRIBUTE => true,
              Geometry::CABINET_ID_ATTRIBUTE => id,
              Geometry::SETTINGS_ATTRIBUTE => JSON.generate(settings),
              'furniture_name_vi' => settings[:cabinet_name]
            }
          end

          def get_attribute(_dictionary, key, default = nil)
            @attributes.fetch(key, default)
          end
        end

        def setup
          Sketchup.reset_defaults
        end

        def test_selected_cabinets_take_precedence_over_whole_model
          selected = FakeCabinet.new(Specification.defaults('tu_bep_duoi'), 'selected')
          other = FakeCabinet.new(Specification.defaults('tu_ao'), 'other')
          model = FakeModel.new([selected], [selected, other])

          project = MachiningPreviewDialog.project_for_model(model)

          assert_equal 'Các tủ đang chọn', project[:scope]
          assert_equal 1, project[:cabinet_count]
          assert_equal ['selected'], project[:cabinets].map { |item| item[:cabinet_id] }
          assert_equal 100, project[:ready_operation_count]
        end

        def test_empty_selection_uses_all_valid_cabinets
          first = FakeCabinet.new(Specification.defaults('tu_bep_duoi'), 'first')
          second = FakeCabinet.new(Specification.defaults('tu_ao'), 'second')
          model = FakeModel.new([], [first, second])

          project = MachiningPreviewDialog.project_for_model(model)

          assert_equal 'Toàn bộ model', project[:scope]
          assert_equal 2, project[:cabinet_count]
          assert_operator project[:panel_count], :>, 15
          assert_operator project[:ready_operation_count], :>, 4
        end

        def test_valid_rules_are_saved_and_loaded_from_preferences
          rules = MachiningRules.normalize(
            preset_key: 'tuy_chinh',
            include_shelf_pins: false,
            dowel_diameter_mm: 10
          )

          MachiningPreviewDialog.save_rules(rules)
          loaded = MachiningPreviewDialog.load_rules

          assert_equal 'tuy_chinh', loaded[:preset_key]
          refute loaded[:include_shelf_pins]
          assert_equal 10.0, loaded[:dowel_diameter_mm]
        end

        def test_corrupt_preferences_fall_back_to_defaults
          Sketchup.write_default(
            MachiningPreviewDialog::PREFERENCES_SECTION,
            MachiningPreviewDialog::RULES_KEY,
            '{bad json'
          )

          assert_equal MachiningRules.defaults, MachiningPreviewDialog.load_rules
        end
      end
    end
  end
end
