# frozen_string_literal: true

require 'minitest/autorun'

module UI
  class HtmlDialog
    STYLE_DIALOG = 1

    class << self
      attr_reader :instances

      def reset
        @instances = []
      end
    end

    attr_reader :options, :callbacks, :scripts, :file
    attr_reader :shown, :closed, :centered, :focused

    def initialize(options)
      @options = options
      @callbacks = {}
      @scripts = []
      @shown = false
      @closed = false
      self.class.instances << self
    end

    def set_file(path)
      @file = path
    end

    def add_action_callback(name, &block)
      @callbacks[name] = block
    end

    def set_on_closed(&block)
      @on_closed = block
    end

    def center
      @centered = true
    end

    def show
      @shown = true
    end

    def bring_to_front
      @focused = true
    end

    def execute_script(script)
      @scripts << script
    end

    def close
      @closed = true
      @on_closed.call if @on_closed
    end

    def simulate_window_close
      @closed = true
      @on_closed.call if @on_closed
    end

    def trigger(name, *arguments)
      @callbacks.fetch(name).call(nil, *arguments)
    end

    reset
  end

  class << self
    attr_reader :messages

    def reset_messages
      @messages = []
    end

    def messagebox(message, *_flags)
      @messages << message
      nil
    end
  end

  reset_messages
end

require_relative '../specification_editor'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SpecificationEditorTest < Minitest::Test
          class ModelStub
            attr_reader :selection, :active_entities, :operations, :commits, :aborts

            def initialize
              @selection = []
              @active_entities = []
              @operations = []
              @commits = 0
              @aborts = 0
            end

            def start_operation(name, transparent)
              @operations << [name, transparent]
            end

            def commit_operation
              @commits += 1
            end

            def abort_operation
              @aborts += 1
            end
          end

          class EntityStub
            attr_accessor :fail_specification_write
            attr_reader :model, :writes, :deletes, :geometry_changes

            def initialize(model:, type: :group, valid: true, values: {})
              @model = model
              @type = type
              @valid = valid
              @attributes = {}
              @writes = []
              @deletes = []
              @geometry_changes = 0
              @fail_specification_write = false
              values.each { |key, value| @attributes[[Metadata::DICTIONARY, key.to_s]] = value }
              model.active_entities << self
            end

            def drawer_assignment_entity_type
              @type
            end

            def valid?
              @valid
            end

            def deleted?
              !@valid
            end

            def locked?
              false
            end

            def delete_from_model!
              @valid = false
            end

            def get_attribute(dictionary, key, default = nil)
              @attributes.fetch([dictionary, key], default)
            end

            def set_attribute(dictionary, key, value)
              if @fail_specification_write && key == Persistence::SPECIFICATION_KEY
                raise 'simulated attribute write failure'
              end

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
            UI::HtmlDialog.reset
            UI.reset_messages
            SpecificationEditor.reset_sessions!
            CNCPlugins::Units.define_singleton_method(:millimeters_to_model_units) { |value| value.to_f }
            CNCPlugins::Units.define_singleton_method(:model_units_to_millimeters) { |value| value.to_f }
            @model = ModelStub.new
          end

          def test_assigned_group_opens_vietnamese_html_dialog
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity

            result = SpecificationEditor.open_selected(model: @model)
            dialog = result[:details][:session].dialog

            assert_success result, :opened
            assert dialog.shown
            assert dialog.centered
            assert_equal 'Thông số ngăn kéo', dialog.options[:dialog_title]
            assert_equal File.expand_path('../ui/specification_editor.html', __dir__), dialog.file
            assert_equal %w[
              drawer_editor_ready drawer_editor_preview drawer_editor_save
              drawer_editor_cancel drawer_editor_reset drawer_editor_resolve_slide
            ].sort, dialog.callbacks.keys.sort
          end

          def test_assigned_component_instance_opens
            entity = assigned_entity(:drawer_box, type: :component_instance)
            @model.selection << entity

            result = SpecificationEditor.open_selected(model: @model)

            assert_success result, :opened
            assert_equal :component_instance, result[:entity].drawer_assignment_entity_type
          end

          def test_unassigned_empty_and_multiple_selections_are_rejected
            unassigned = new_entity
            @model.selection << unassigned
            assert_failure SpecificationEditor.open_selected(model: @model), :entity_not_assigned

            @model.selection.clear
            assert_failure SpecificationEditor.open_selected(model: @model), :empty_selection

            @model.selection.replace([new_entity, new_entity])
            assert_failure SpecificationEditor.open_selected(model: @model), :multiple_selection
            assert_empty UI::HtmlDialog.instances
          end

          def test_ready_and_reset_restore_initial_payload_without_writes
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            before = entity.snapshot
            writes = entity.writes.length

            session.dialog.trigger('drawer_editor_ready')
            session.dialog.trigger('drawer_editor_reset')

            assert_equal 2, session.dialog.scripts.count { |script| script.include?('.load(') }
            assert_equal before, entity.snapshot
            assert_equal writes, entity.writes.length
            assert_empty @model.operations
          end

          def test_preview_succeeds_without_persistence_or_model_operation
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            before = entity.snapshot

            result = SpecificationEditor.handle_preview(session, automatic_payload)

            assert_success result, :previewed
            assert_equal 575.0, result[:details][:preview][:box_width]
            assert_equal 180.0, result[:details][:preview][:box_height]
            assert_equal 531.0, result[:details][:preview][:box_depth]
            assert session.dialog.scripts.last.include?('showPreview')
            assert_equal before, entity.snapshot
            assert_nil Persistence.read(entity)
            assert_empty @model.operations
            assert_equal 0, entity.geometry_changes
          end

          def test_preview_validation_failure_is_vietnamese_and_does_not_persist
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            payload = automatic_payload
            payload[:opening][:opening_width] = ''

            result = SpecificationEditor.handle_preview(session, payload)

            assert_failure result, :missing_field
            assert_equal 'Chiều rộng khoang phải lớn hơn 0.', result[:details][:message]
            assert session.dialog.scripts.last.include?('showError')
            assert_nil Persistence.read(entity)
            assert_empty @model.operations
          end

          def test_automatic_save_uses_one_operation_and_closes
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session

            result = SpecificationEditor.handle_save(session, automatic_payload)
            restored = Persistence.read(entity)

            assert_success result, :saved
            assert_equal 575.0, restored.box[:box_width]
            assert_equal 180.0, restored.box[:box_height]
            assert_equal 531.0, restored.box[:box_depth]
            assert_equal 12.5, restored.slides[:left_clearance]
            assert_equal 12.5, restored.slides[:right_clearance]
            assert_equal [[SpecificationEditor::OPERATION_SAVE, true]], @model.operations
            assert_equal 1, @model.commits
            assert_equal 0, @model.aborts
            assert session.dialog.closed
            assert_equal 0, entity.geometry_changes
          end

          def test_manual_box_only_save_is_valid_partial_specification
            entity = assigned_entity(:drawer_box)
            @model.selection << entity
            session = open_session

            result = SpecificationEditor.handle_save(session, manual_box_payload)
            restored = Persistence.read(entity)

            assert_success result, :saved
            assert_nil restored.opening
            assert_nil restored.slides
            assert_equal 'manual', restored.box[:dimension_mode]
            assert_equal 575.5, restored.box[:box_width]
          end

          def test_opening_only_save_is_valid_partial_specification
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            payload = opening_only_payload

            result = SpecificationEditor.handle_save(session, payload)
            restored = Persistence.read(entity)

            assert_success result, :saved
            assert_equal 600.0, restored.opening[:opening_width]
            assert_nil restored.slides
            assert_nil restored.box
          end

          def test_save_preserves_existing_specification_and_unrelated_metadata
            system_id = Identity.generate_system_id
            entity = assigned_entity(
              :drawer_opening,
              system_id: system_id,
              values: { 'part_kind' => 'cabinet_part', 'cnc_operation' => 'pocket' }
            )
            Persistence.write(
              entity,
              Specification.new(
                drawer_system_id: system_id,
                cabinet_id: 'CAB-07',
                source: 'assigned',
                opening: { opening_width: 500, opening_height: 150, opening_depth: 450 }
              )
            )
            @model.selection << entity
            session = open_session

            result = SpecificationEditor.handle_save(session, opening_only_payload)
            restored = Persistence.read(entity)

            assert_success result, :saved
            assert_equal 'CAB-07', restored.cabinet_id
            assert_equal 'cabinet_part', entity.get_attribute(Metadata::DICTIONARY, 'part_kind')
            assert_equal 'pocket', entity.get_attribute(Metadata::DICTIONARY, 'cnc_operation')
          end

          def test_manual_oversize_warning_is_nonblocking_and_vietnamese
            entity = assigned_entity(:drawer_box)
            @model.selection << entity
            session = open_session
            payload = manual_box_payload
            payload[:opening] = opening_only_payload[:opening]
            payload[:box][:box_width] = '650'

            result = SpecificationEditor.handle_save(session, payload)

            assert_success result, :saved
            assert_equal ['Kích thước thùng ngăn kéo đang lớn hơn khoang lắp đặt.'], UI.messages
            assert_equal 1, @model.commits
          end

          def test_cancel_and_window_close_do_not_persist
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            first = open_session
            before = entity.snapshot

            first.dialog.trigger('drawer_editor_cancel')
            assert first.dialog.closed
            assert_equal before, entity.snapshot
            assert_empty @model.operations

            second_result = SpecificationEditor.open_selected(model: @model)
            second = second_result[:details][:session]
            second.dialog.simulate_window_close
            assert_equal before, entity.snapshot
            assert_empty @model.operations
          end

          def test_duplicate_editor_for_same_system_focuses_existing_dialog
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            first = SpecificationEditor.open_selected(model: @model)

            second = SpecificationEditor.open_selected(model: @model)

            assert_success first, :opened
            assert_success second, :focused
            assert_equal 1, UI::HtmlDialog.instances.length
            assert first[:details][:session].dialog.focused
          end

          def test_stale_system_id_is_rejected_before_operation
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            Metadata.write(
              entity,
              Identity.create(object_type: :drawer_opening, system_id: Identity.generate_system_id)
            )

            result = SpecificationEditor.handle_save(session, opening_only_payload)

            assert_failure result, :stale_dialog
            assert_empty @model.operations
          end

          def test_deleted_entity_is_rejected_before_operation
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            entity.delete_from_model!

            result = SpecificationEditor.handle_save(session, opening_only_payload)

            assert_failure result, :deleted_entity
            assert_empty @model.operations
          end

          def test_reassigned_entity_is_rejected_before_operation
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            Metadata.write(
              entity,
              Identity.create(
                object_type: :drawer_box,
                system_id: session.drawer_system_id
              )
            )

            result = SpecificationEditor.handle_save(session, opening_only_payload)

            assert_failure result, :stale_dialog
            assert_empty @model.operations
          end

          def test_owner_change_while_open_is_rejected
            opening = assigned_entity(:drawer_opening)
            @model.selection << opening
            session = open_session
            assigned_entity(:drawer_system, system_id: session.drawer_system_id)

            result = SpecificationEditor.handle_save(session, opening_only_payload)

            assert_failure result, :stale_dialog
            assert_empty @model.operations
          end

          def test_persistence_failure_aborts_the_single_operation
            entity = assigned_entity(:drawer_opening)
            @model.selection << entity
            session = open_session
            entity.fail_specification_write = true

            result = SpecificationEditor.handle_save(session, opening_only_payload)

            assert_failure result, :save_failed
            assert_equal [[SpecificationEditor::OPERATION_SAVE, true]], @model.operations
            assert_equal 0, @model.commits
            assert_equal 1, @model.aborts
            refute session.dialog.closed
          end

          private

          def new_entity(type: :group, values: {})
            EntityStub.new(model: @model, type: type, values: values)
          end

          def assigned_entity(role, type: :group, system_id: nil, values: {})
            entity = new_entity(type: type, values: values)
            Metadata.write(
              entity,
              Identity.create(object_type: role, system_id: system_id)
            )
            entity
          end

          def open_session
            result = SpecificationEditor.open_selected(model: @model)
            assert result[:success], result.inspect
            result[:details][:session]
          end

          def opening_only_payload
            {
              opening: {
                enabled: true,
                opening_width: '600',
                opening_height: '180',
                opening_depth: '571'
              },
              slides: { enabled: false },
              box: { enabled: false }
            }
          end

          def automatic_payload
            {
              opening: opening_only_payload[:opening],
              slides: {
                enabled: true,
                slide_type: 'side_mount_ball_bearing',
                preset_name: SlideConfigurations::LEGACY_PRESET_KEY,
                manufacturer: '',
                left_clearance: '', right_clearance: '',
                top_clearance: '', bottom_clearance: '',
                front_setback: '', rear_clearance: '', slide_thickness: '',
                slide_height: '', slide_length: '',
                minimum_drawer_depth: '', maximum_drawer_depth: ''
              },
              box: {
                enabled: true,
                dimension_mode: 'calculated',
                box_width: '', box_height: '', box_depth: '',
                board_thickness: '15', bottom_thickness: '6',
                front_thickness: '15', back_thickness: '15'
              }
            }
          end

          def manual_box_payload
            {
              opening: { enabled: false },
              slides: { enabled: false },
              box: {
                enabled: true,
                dimension_mode: 'manual',
                box_width: '575,5', box_height: '170', box_depth: '470',
                board_thickness: '15', bottom_thickness: '6',
                front_thickness: '15', back_thickness: '15'
              }
            }
          end

          def assert_success(result, status)
            assert_equal true, result[:success], result.inspect
            assert_nil result[:error_code]
            assert_equal status, result[:details][:status]
          end

          def assert_failure(result, code)
            assert_equal false, result[:success], result.inspect
            assert_equal code, result[:error_code]
          end
        end
      end
    end
  end
end
