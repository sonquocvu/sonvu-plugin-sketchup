# frozen_string_literal: true

require 'json'
require 'minitest/autorun'

require_relative '../persistence'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class PersistenceTest < Minitest::Test
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

          def test_opening_specification_round_trip
            assert_round_trip(opening: opening_values)
          end

          def test_slide_specification_round_trip
            assert_round_trip(slides: slide_values)
          end

          def test_drawer_box_specification_round_trip
            assert_round_trip(box: box_values)
          end

          def test_complete_specification_round_trip
            assert_round_trip(complete_values)
          end

          def test_partial_opening_only_specification
            entity = EntityStub.new
            Persistence.write(entity, opening: opening_values)
            restored = Persistence.read(entity)

            assert restored.valid?, restored.errors.inspect
            refute_nil restored.opening
            assert_nil restored.slides
            assert_nil restored.box
          end

          def test_partial_opening_and_slides_specification
            entity = EntityStub.new
            Persistence.write(entity, opening: opening_values, slides: slide_values)
            restored = Persistence.read(entity)

            refute_nil restored.opening
            refute_nil restored.slides
            assert_nil restored.box
          end

          def test_asymmetric_slide_clearances_remain_independent
            entity = EntityStub.new
            values = slide_values.merge(left_clearance: 9.5, right_clearance: 16.25)

            Persistence.write(entity, slides: values)
            restored = Persistence.read(entity)

            assert_equal 9.5, restored.slides[:left_clearance]
            assert_equal 16.25, restored.slides[:right_clearance]
          end

          def test_persisted_dimensions_are_numeric_not_formatted_strings
            payload = Persistence.dump(complete_values)
            parsed = JSON.parse(payload)

            assert_instance_of Float, parsed['opening']['opening_width']
            assert_instance_of Float, parsed['slides']['left_clearance']
            assert_instance_of Float, parsed['box']['board_thickness']
            refute_includes payload, ' mm'
          end

          def test_read_hash_returns_plain_ruby_data
            entity = EntityStub.new
            Persistence.write(entity, complete_values)

            values = Persistence.read_hash(entity)

            assert_instance_of Hash, values
            assert_instance_of Hash, values[:opening]
            assert_equal 600.0, values[:opening][:opening_width]
          end

          def test_missing_specification_returns_nil
            assert_nil Persistence.read(EntityStub.new)
          end

          def test_invalid_specification_raises_structured_error
            error = assert_raises(Persistence::PersistenceError) do
              Persistence.dump(opening: opening_values.merge(opening_width: 0))
            end

            assert_equal :invalid_specification, error.code
          end

          def test_malformed_json_raises_structured_error
            error = assert_raises(Persistence::PersistenceError) do
              Persistence.load_json('{broken')
            end

            assert_equal :invalid_specification, error.code
          end

          def test_future_schema_version_is_not_silently_loaded
            error = assert_raises(Persistence::PersistenceError) do
              Persistence.load_json(
                JSON.generate(schema_version: Specification::SCHEMA_VERSION + 1, opening: opening_values)
              )
            end

            assert_equal :future_metadata_version, error.code
          end

          def test_invalid_schema_version_is_rejected
            error = assert_raises(Persistence::PersistenceError) do
              Persistence.load_json(JSON.generate(schema_version: 'version-one', opening: opening_values))
            end

            assert_equal :invalid_specification, error.code
            assert_equal :schema_version, error.field
          end

          def test_clear_removes_only_specification_payload
            entity = EntityStub.new
            identity = Identity.create(object_type: 'drawer_opening')
            Metadata.write(entity, identity)
            entity.set_attribute(Metadata::DICTIONARY, 'part_kind', 'carcass')
            Persistence.write(entity, opening: opening_values)

            Persistence.clear(entity)

            assert_nil Persistence.read(entity)
            expected_identity = identity.to_h.reject { |_key, value| value.nil? }
            assert_equal expected_identity, Metadata.read(entity)
            assert_equal 'carcass', entity.get_attribute(Metadata::DICTIONARY, 'part_kind')
          end

          private

          def assert_round_trip(values)
            entity = EntityStub.new
            original = Specification.new(values)

            written = Persistence.write(entity, original)
            restored = Persistence.read(entity)

            assert_same original, written
            assert_instance_of Specification, restored
            assert_equal original.to_h, restored.to_h
          end

          def complete_values
            {
              schema_version: 1,
              unit_system: 'sketchup_internal',
              drawer_system_id: Identity.generate_system_id,
              source: 'generated',
              opening: opening_values,
              slides: slide_values,
              box: box_values
            }
          end

          def opening_values
            {
              object_id: 'opening-1',
              opening_width: 600,
              opening_height: 180,
              opening_depth: 500,
              front_direction: [1, 0, 0],
              depth_direction: [0, 1, 0],
              local_transformation: (1..16).to_a,
              source_entity_id: 12_345
            }
          end

          def slide_values
            {
              object_id: 'slides-1',
              slide_type: 'custom',
              calculation_strategy: 'clearance',
              label_vi: 'Ray tùy chỉnh',
              left_clearance: 10,
              right_clearance: 15,
              top_clearance: 2,
              bottom_clearance: 3,
              front_setback: 20,
              rear_clearance: 25,
              slide_thickness: 12.5,
              slide_length: 450,
              preset_name: 'Bếp tiêu chuẩn',
              manufacturer: 'SonVu'
            }
          end

          def box_values
            {
              object_id: 'box-1',
              box_width: 575,
              box_height: 175,
              box_depth: 455,
              board_thickness: 15,
              bottom_thickness: 6,
              front_thickness: 15,
              back_thickness: 15
            }
          end
        end
      end
    end
  end
end
