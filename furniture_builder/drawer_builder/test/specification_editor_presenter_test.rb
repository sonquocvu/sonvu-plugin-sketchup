# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../specification_editor_presenter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SpecificationEditorPresenterTest < Minitest::Test
          class EntityStub
            attr_reader :writes, :deletes

            PointStub = Struct.new(:y)
            BoundsStub = Struct.new(:min, :max) do
              def self.with_y_extent(value)
                new(PointStub.new(0.0), PointStub.new(value))
              end
            end
            DefinitionStub = Struct.new(:bounds)
            AxisStub = Struct.new(:length)
            TransformationStub = Struct.new(:yaxis)

            def initialize(model_depth: nil, y_scale: 1.0)
              @attributes = {}
              @writes = []
              @deletes = []
              unless model_depth.nil?
                @definition = DefinitionStub.new(BoundsStub.with_y_extent(model_depth))
              end
              @transformation = TransformationStub.new(AxisStub.new(y_scale))
            end

            attr_reader :definition, :transformation

            def get_attribute(dictionary, key, default = nil)
              @attributes.fetch([dictionary, key], default)
            end

            def set_attribute(dictionary, key, value)
              @writes << [dictionary, key, value]
              @attributes[[dictionary, key]] = value
            end

            def delete_attribute(dictionary, key)
              @deletes << [dictionary, key]
              @attributes.delete([dictionary, key])
            end

            def snapshot
              Marshal.load(Marshal.dump(@attributes))
            end
          end

          def setup
            Units.define_singleton_method(:model_units_to_millimeters) { |value| value.to_f / 2.0 }
          end

          def test_empty_specification_uses_selected_role_without_writing
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id)
            before = opening.snapshot

            payload = present([opening], system_id, opening, nil)

            assert payload[:opening][:enabled]
            refute payload[:slides][:enabled]
            refute payload[:box][:enabled]
            assert_nil payload[:opening][:opening_width]
            assert_equal before, opening.snapshot
          end

          def test_empty_depth_is_automatically_filled_from_scaled_opening_geometry
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id, model_depth: 800, y_scale: 1.25)

            payload = present([opening], system_id, opening, nil)

            assert_equal 500, payload[:opening][:opening_depth]
            assert_nil payload[:opening][:opening_width]
            assert_nil payload[:opening][:opening_height]
          end

          def test_saved_depth_is_not_overwritten_by_opening_geometry
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id, model_depth: 2000)
            specification = Specification.new(
              drawer_system_id: system_id,
              source: 'assigned',
              opening: { opening_width: 1200, opening_height: 360, opening_depth: 1000 }
            )

            payload = present([opening], system_id, opening, specification)

            assert_equal 500, payload[:opening][:opening_depth]
          end

          def test_partial_opening_converts_internal_units_to_millimeters
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id)
            specification = Specification.new(
              drawer_system_id: system_id,
              source: 'assigned',
              opening: { opening_width: 1200, opening_height: 360, opening_depth: 1000 }
            )

            payload = present([opening], system_id, opening, specification)

            assert_equal 600, payload[:opening][:opening_width]
            assert_equal 180, payload[:opening][:opening_height]
            assert_equal 500, payload[:opening][:opening_depth]
          end

          def test_millimeter_specification_is_not_converted_twice
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id)
            specification = Specification.new(
              unit_system: 'millimeters',
              drawer_system_id: system_id,
              source: 'assigned',
              opening: { opening_width: 600, opening_height: 180, opening_depth: 500 }
            )

            assert_equal 600, present([opening], system_id, opening, specification)[:opening][:opening_width]
          end

          def test_slide_only_payload_uses_vietnamese_slide_names
            system_id = Identity.generate_system_id
            slide = assigned('drawer_slide_left', system_id)
            specification = Specification.new(
              drawer_system_id: system_id,
              source: 'assigned',
              slides: valid_slides.merge(slide_type: 'custom', label_vi: 'Ray tùy chỉnh')
            )

            payload = present([slide], system_id, slide, specification)

            assert payload[:slides][:enabled]
            assert_equal 'custom', payload[:slides][:slide_type]
            assert_includes payload[:slide_options].map { |item| item[:label] }, 'Ray tùy chỉnh'
            assert_equal 'Ray trái', payload[:selected_role_label]
          end

          def test_box_only_manual_mode_and_role_summary
            system_id = Identity.generate_system_id
            box = assigned('drawer_box', system_id)
            specification = Specification.new(
              drawer_system_id: system_id,
              source: 'assigned',
              box: valid_box.merge(dimension_mode: 'manual')
            )

            payload = present([box], system_id, box, specification)

            assert_equal 'manual', payload[:box][:dimension_mode]
            assert_equal 'Nhập thủ công', payload[:box][:dimension_indicator]
            assert_equal 'Hệ hiện có: Chỉ có thùng ngăn kéo', payload[:role_summary]
          end

          def test_complete_specification_uses_automatic_mode
            system_id = Identity.generate_system_id
            entities = %w[drawer_opening drawer_slide_left drawer_slide_right drawer_box].map do |role|
              assigned(role, system_id)
            end
            specification = Specification.new(
              drawer_system_id: system_id,
              source: 'assigned',
              opening: { opening_width: 1200, opening_height: 360, opening_depth: 1000 },
              slides: valid_slides,
              box: valid_box.merge(dimension_mode: 'calculated')
            )

            payload = present(entities, system_id, entities.first, specification)

            assert_equal :complete, payload[:system_state]
            assert_equal 'calculated', payload[:box][:dimension_mode]
            assert_equal 'Tự động tính', payload[:box][:dimension_indicator]
            assert_match(/Khoang ngăn kéo/, payload[:role_summary])
          end

          def test_unsupported_slide_strategy_is_marked_in_vietnamese
            system_id = Identity.generate_system_id
            slide = assigned('drawer_slide_left', system_id)
            specification = Specification.new(
              drawer_system_id: system_id,
              source: 'assigned',
              slides: valid_slides.merge(slide_type: 'undermount', calculation_strategy: nil)
            )

            payload = present([slide], system_id, slide, specification)

            refute payload[:slides][:automatic_supported]
            assert_equal(
              'Chưa có công thức tính tự động cho loại ray này.',
              payload[:slides][:unsupported_message]
            )
          end

          def test_presentation_does_not_write_any_member_metadata
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id)
            slide = assigned('drawer_slide_left', system_id)
            counts = [opening, slide].map { |entity| [entity.writes.length, entity.deletes.length] }

            present([slide, opening], system_id, slide, nil)

            assert_equal counts, [opening, slide].map { |entity| [entity.writes.length, entity.deletes.length] }
          end

          private

          def assigned(role, system_id, model_depth: nil, y_scale: 1.0)
            entity = EntityStub.new(model_depth: model_depth, y_scale: y_scale)
            Metadata.write(
              entity,
              Identity.create(object_type: role, system_id: system_id, source: 'user_assigned')
            )
            entity
          end

          def present(scope, system_id, selected, specification)
            SpecificationEditorPresenter.present(
              scope: scope,
              drawer_system_id: system_id,
              selected_entity: selected,
              specification: specification
            )
          end

          def valid_slides
            {
              slide_type: 'custom',
              calculation_strategy: 'clearance',
              left_clearance: 25,
              right_clearance: 25,
              top_clearance: 0,
              bottom_clearance: 0,
              front_setback: 40,
              rear_clearance: 40,
              slide_thickness: 25
            }
          end

          def valid_box
            {
              box_width: 1150,
              box_height: 360,
              box_depth: 920,
              board_thickness: 30,
              bottom_thickness: 12,
              front_thickness: 30,
              back_thickness: 30
            }
          end
        end
      end
    end
  end
end
