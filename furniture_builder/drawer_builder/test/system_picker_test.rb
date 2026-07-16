# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../system_picker'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SystemPickerTest < Minitest::Test
          class EntityStub
            def initialize
              @attributes = {}
            end

            def get_attribute(dictionary, key, default = nil)
              @attributes.fetch([dictionary, key], default)
            end

            def set_attribute(dictionary, key, value)
              @attributes[[dictionary, key]] = value
            end

            def delete_attribute(dictionary, key)
              @attributes.delete([dictionary, key])
            end
          end

          class UIStub
            attr_reader :messages, :input_calls

            def initialize(confirmations: [], inputs: [])
              @confirmations = confirmations
              @inputs = inputs
              @messages = []
              @input_calls = []
            end

            def messagebox(message, _flags)
              @messages << message
              @confirmations.shift
            end

            def inputbox(prompts, defaults, lists, title)
              @input_calls << [prompts, defaults, lists, title]
              @inputs.shift
            end
          end

          YES = 6
          NO = 7

          def test_zero_systems_can_create_new_partial_system
            ui = UIStub.new(confirmations: [YES])

            result = SystemPicker.choose([], ui: ui)

            assert_equal :create_new, result[:status]
            assert_nil result[:drawer_system_id]
            assert_equal CommandMessages::NO_SYSTEM_CONFIRMATION, ui.messages.last
          end

          def test_zero_systems_can_be_cancelled
            result = SystemPicker.choose([], ui: UIStub.new(confirmations: [NO]))

            assert_equal :cancelled, result[:status]
          end

          def test_one_system_confirmation_returns_stable_id
            system_id, entities = system_with_roles(%w[drawer_opening])
            ui = UIStub.new(confirmations: [YES])

            result = SystemPicker.choose(entities, ui: ui)

            assert_equal :selected, result[:status]
            assert_equal system_id, result[:drawer_system_id]
            assert_equal CommandMessages::ONE_SYSTEM_CONFIRMATION, ui.messages.last
          end

          def test_one_system_confirmation_can_be_cancelled
            _system_id, entities = system_with_roles(%w[drawer_opening])

            result = SystemPicker.choose(entities, ui: UIStub.new(confirmations: [NO]))

            assert_equal :cancelled, result[:status]
          end

          def test_multiple_system_picker_maps_label_to_correct_id
            first_id, first = system_with_roles(%w[drawer_opening])
            second_id, second = system_with_roles(
              %w[drawer_opening drawer_slide_left drawer_slide_right drawer_box]
            )
            scope = first + second
            options = SystemPicker.systems(scope)
            ui = UIStub.new(inputs: [[options[1][:label]]])

            result = SystemPicker.choose(scope, ui: ui)

            assert_equal :selected, result[:status]
            assert_equal second_id, result[:drawer_system_id]
            refute_equal first_id, result[:drawer_system_id]
            assert_equal 'Chọn hệ ngăn kéo', ui.input_calls.last[3]
          end

          def test_complete_and_partial_state_labels_are_readable
            assert_equal 'Hệ ngăn kéo 1 — hoàn chỉnh', SystemPicker.system_label(1, :complete)
            assert_equal 'Hệ ngăn kéo 2 — chỉ có khoang', SystemPicker.system_label(2, :opening_only)
            assert_equal(
              'Hệ ngăn kéo 3 — có khoang và thùng ngăn kéo',
              SystemPicker.system_label(3, :opening_and_box)
            )
            refute_includes SystemPicker.system_label(4, :custom_partial), 'drawer_'
          end

          def test_cancelled_multiple_system_picker
            _first_id, first = system_with_roles(%w[drawer_opening])
            _second_id, second = system_with_roles(%w[drawer_box])

            result = SystemPicker.choose(first + second, ui: UIStub.new(inputs: [false]))

            assert_equal :cancelled, result[:status]
          end

          def test_duplicate_looking_states_keep_distinct_id_mapping
            first_id, first = system_with_roles(%w[drawer_opening])
            second_id, second = system_with_roles(%w[drawer_opening])
            options = SystemPicker.systems(first + second)

            assert_equal :opening_only, options[0][:state]
            assert_equal :opening_only, options[1][:state]
            refute_equal options[0][:label], options[1][:label]
            assert_equal first_id, options[0][:drawer_system_id]
            assert_equal second_id, options[1][:drawer_system_id]
          end

          private

          def system_with_roles(roles)
            system_id = Identity.generate_system_id
            entities = roles.map do |role|
              entity = EntityStub.new
              Metadata.write(entity, Identity.create(object_type: role, system_id: system_id))
              entity
            end
            [system_id, entities]
          end
        end
      end
    end
  end
end
