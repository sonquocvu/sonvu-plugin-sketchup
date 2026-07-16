# frozen_string_literal: true

require 'json'

# SketchUp-facing selection, HtmlDialog, lifecycle, stale-state observer, and
# non-persistent View drawing for one automatic joint preview run.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class PreviewSelectionResolution
          attr_reader :board_descriptors, :ignored_entity_count, :warnings,
                      :entity_by_part_id, :entity_paths_by_part_id,
                      :transform_snapshots_by_part_id, :active_path_entities,
                      :active_path_snapshot

          def initialize(attributes)
            @board_descriptors = attributes.fetch(:board_descriptors).freeze
            @ignored_entity_count = attributes.fetch(:ignored_entity_count).to_i
            @warnings = attributes.fetch(:warnings).freeze
            @entity_by_part_id = attributes.fetch(:entity_by_part_id).freeze
            @entity_paths_by_part_id = attributes.fetch(:entity_paths_by_part_id).freeze
            @transform_snapshots_by_part_id = attributes.fetch(:transform_snapshots_by_part_id).freeze
            @active_path_entities = attributes.fetch(:active_path_entities).freeze
            @active_path_snapshot = attributes.fetch(:active_path_snapshot).freeze
            freeze
          end

          def valid?
            board_descriptors.length >= 2
          end
        end

        class PreviewSelectionResolver
          IGNORED_WARNING = 'Một số chi tiết đã bị bỏ qua vì không phải Group hoặc Component.'.freeze

          def initialize(scanner: SketchupBoardScanner.new)
            @scanner = scanner
          end

          def resolve(selection, active_path: nil)
            selected = selection.to_a
            candidates = selected.select { |entity| board_candidate?(entity) }
            ignored = selected.length - candidates.length
            parent_transform, parent_path, active_entities, active_snapshot = active_context(active_path)
            descriptors = @scanner.scan(
              candidates,
              parent_transform: parent_transform,
              parent_path: parent_path
            )
            skipped = @scanner.skipped_entities.length
            ignored += skipped
            warnings = []
            warnings << IGNORED_WARNING if ignored.positive?
            PreviewSelectionResolution.new(
              board_descriptors: descriptors,
              ignored_entity_count: ignored,
              warnings: warnings,
              entity_by_part_id: @scanner.entity_by_part_id.dup,
              entity_paths_by_part_id: @scanner.entity_paths_by_part_id.dup,
              transform_snapshots_by_part_id: @scanner.transform_snapshots_by_part_id.dup,
              active_path_entities: active_entities,
              active_path_snapshot: active_snapshot
            )
          end

          private

          def board_candidate?(entity)
            return true if defined?(::Sketchup::Group) && entity.is_a?(::Sketchup::Group)
            return true if defined?(::Sketchup::ComponentInstance) && entity.is_a?(::Sketchup::ComponentInstance)

            false
          end

          def active_context(active_path)
            transform = Transform3.identity
            ids = []
            entities = active_path.to_a
            snapshot = entities.map do |entity|
              local = Transform3.from_sketchup(entity.transformation)
              transform = transform * local
              ids << persistent_identity(entity)
              local.values
            end
            [transform, ids, entities, snapshot]
          end

          def persistent_identity(entity)
            return entity.persistent_id.to_s if entity.respond_to?(:persistent_id)
            return entity.entityID.to_s if entity.respond_to?(:entityID)

            "object-#{entity.object_id}"
          end
        end

        module PreviewSessionRegistry
          module_function

          def replace(model, session)
            key = model.object_id
            existing = sessions[key]
            existing.close if existing && !existing.equal?(session)
            sessions[key] = session
          end

          def remove(model, session)
            key = model.object_id
            sessions.delete(key) if sessions[key].equal?(session)
          end

          def for_model(model)
            sessions[model.object_id]
          end

          def sessions
            @sessions ||= {}
          end
        end

        PreviewModelObserverBase = if defined?(::Sketchup::ModelObserver)
                                     ::Sketchup::ModelObserver
                                   else
                                     Object
                                   end

        class PreviewModelObserver < PreviewModelObserverBase
          def initialize(session)
            @session = session
          end

          def onTransactionCommit(_model)
            @session.mark_stale_from_model
          end

          def onTransactionUndo(_model)
            @session.mark_stale_from_model
          end

          def onTransactionRedo(_model)
            @session.mark_stale_from_model
          end

          def onEraseAll(_model)
            @session.mark_stale_from_model
          end

          def onDeleteModel(_model)
            @session.close
          end
        end

        class PreviewOverlayTool
          VK_ESCAPE = 27

          def initialize(session)
            @session = session
            @closing = false
          end

          def activate
            @session.overlay_activated
            Sketchup.set_status_text('Tạo mộng tự động: xem toàn bộ mộng hợp lệ, nhấn Esc để đóng.')
          end

          def deactivate(view)
            @session.overlay_deactivated
            view.invalidate if view
          end

          def onKeyDown(key, _repeat, _flags, view)
            return unless key == VK_ESCAPE

            @closing = true
            @session.close
            view.model.select_tool(nil)
          end

          def onCancel(_reason, view)
            return if @closing

            @closing = true
            @session.close
            view.model.select_tool(nil)
          end

          def draw(view)
            return if @session.guard_model_state!

            @session.preview_primitives.each do |primitive|
              draw_primitive(view, primitive)
            end
          rescue StandardError
            @session.mark_stale_from_model
          end

          def getExtents
            bounds = Geom::BoundingBox.new
            @session.preview_primitives.each do |primitive|
              primitive[:points].each { |point| bounds.add(geom_point(point)) }
            end
            bounds
          end

          private

          def draw_primitive(view, primitive)
            return draw_legend(view, primitive) if primitive[:kind] == 'viewport_legend'

            points = primitive[:points].map { |point| geom_point(point) }
            apply_style(view, primitive[:style])
            case primitive[:kind]
            when 'joint_center', 'simplified_joint_marker'
              draw_center(view, points.first, primitive)
            when 'viewport_label'
              draw_label(view, points.first, primitive[:label], primitive[:style])
            else
              view.draw(::GL_LINES, points) unless points.empty?
              if %w[male_board_outline female_board_outline].include?(primitive[:kind])
                label_point = primitive[:label_point]
                draw_label(view, geom_point(label_point), primitive[:label], primitive[:style]) if label_point
              elsif primitive[:kind] == 'invalid_marker'
                draw_label(view, points.first, primitive[:label], :invalid)
              end
            end
          end

          def draw_center(view, point, primitive)
            drawing_style = PreviewDisplayStyles.fetch(primitive[:style])
            point_style = primitive[:state] == 'invalid' ? 5 : (primitive[:enabled] ? 2 : 4)
            view.draw_points(
              [point], drawing_style[:point_size], point_style,
              sketchup_color(drawing_style[:color])
            )
            draw_label(view, point, primitive[:label], primitive[:style])
          end

          def draw_label(view, point, label, style_name = :label)
            return unless label && view.respond_to?(:draw_text)

            options = {
              color: sketchup_color(PreviewDisplayStyles.fetch(style_name)[:color]),
              size: 13,
              bold: style_name.to_sym == :tenon || style_name.to_sym == :invalid
            }
            view.draw_text(point, label.to_s, options)
          rescue ArgumentError
            view.draw_text(point, label.to_s)
          end

          def draw_legend(view, primitive)
            x = 18
            y = 22
            primitive[:legend_entries].each do |entry|
              style = PreviewDisplayStyles.fetch(entry[:style])
              view.drawing_color = sketchup_color(style[:color])
              view.line_width = style[:line_width]
              view.line_stipple = style[:line_stipple] if view.respond_to?(:line_stipple=)
              view.draw2d(::GL_LINES, [Geom::Point3d.new(x, y, 0), Geom::Point3d.new(x + 28, y, 0)])
              draw_screen_text(view, [x + 36, y - 7], entry[:label], entry[:style])
              y += 21
            end
            draw_screen_text(view, [x, y + 2], primitive[:legend_note], :label)
          end

          def draw_screen_text(view, screen_point, label, style_name)
            style = PreviewDisplayStyles.fetch(style_name)
            view.draw_text(
              screen_point, label.to_s,
              color: sketchup_color(style[:color]), size: 12,
              bold: style_name.to_sym == :tenon || style_name.to_sym == :invalid
            )
          rescue ArgumentError
            view.draw_text(screen_point, label.to_s)
          end

          def apply_style(view, style_name)
            style = PreviewDisplayStyles.fetch(style_name)
            view.drawing_color = sketchup_color(style[:color])
            view.line_width = style[:line_width]
            view.line_stipple = style[:line_stipple] if view.respond_to?(:line_stipple=)
          end

          def sketchup_color(values)
            Sketchup::Color.new(values[0], values[1], values[2])
          end

          def geom_point(point)
            Geom::Point3d.new(point.x, point.y, point.z)
          end
        end

        class PreviewSession
          DIALOG_TITLE = 'Tạo mộng âm dương tự động'.freeze
          PREFERENCES_KEY = 'sonvu_automatic_joint_preview'.freeze
          UI_FILE = File.expand_path('ui/automatic_preview.html', __dir__).freeze
          STALE_MESSAGE = 'Mô hình đã thay đổi. Vui lòng bấm Xem trước để phân tích lại.'.freeze

          attr_reader :model, :state, :dialog, :finalized_plan, :resolution

          def self.start(model: Sketchup.active_model)
            resolver = PreviewSelectionResolver.new
            active_path = model.respond_to?(:active_path) ? model.active_path : nil
            resolution = resolver.resolve(model.selection, active_path: active_path)
            unless resolution.valid?
              message = if resolution.board_descriptors.empty?
                          'Không tìm thấy chi tiết dạng tấm phù hợp trong vùng chọn.'
                        else
                          'Vui lòng chọn ít nhất hai chi tiết dạng Group hoặc Component.'
                        end
              CNCPlugins::UIHelpers.message(message)
              return nil
            end

            settings = PreviewSettingsParser.new.defaults
            state = PreviewState.new(
              board_descriptors: resolution.board_descriptors,
              settings: settings,
              ignored_entity_count: resolution.ignored_entity_count
            )
            session = new(model: model, resolution: resolution, state: state, resolver: resolver)
            PreviewSessionRegistry.replace(model, session)
            session.open
            session
          rescue StandardError => error
            session.close if defined?(session) && session
            CNCPlugins::UIHelpers.message("Không mở được xem trước mộng tự động:\n#{error.message}")
            nil
          end

          def initialize(model:, resolution:, state:, resolver: PreviewSelectionResolver.new,
                         settings_parser: PreviewSettingsParser.new,
                         serializer: PreviewStateSerializer.new,
                         primitive_builder: PreviewPrimitiveBuilder.new,
                         executor: nil, diagnostic_logger: nil)
            @model = model
            @resolution = resolution
            @state = state
            @resolver = resolver
            @settings_parser = settings_parser
            @serializer = serializer
            @primitive_builder = primitive_builder
            @executor = executor
            @diagnostic_logger = diagnostic_logger
            @observer = PreviewModelObserver.new(self)
            @overlay_tool = PreviewOverlayTool.new(self)
            @overlay_active = false
            @closed = false
          end

          def open
            raise ArgumentError, 'SketchUp hiện tại không hỗ trợ HtmlDialog.' unless defined?(::UI::HtmlDialog)

            @dialog = create_dialog
            configure_dialog
            model.add_observer(@observer) if model.respond_to?(:add_observer)
            model.select_tool(@overlay_tool)
            dialog.show
            self
          end

          def close(dialog_closed: false)
            return if @closed

            @closed = true
            state.clear_preview
            model.remove_observer(@observer) if model.respond_to?(:remove_observer)
            PreviewSessionRegistry.remove(model, self)
            current_dialog = dialog
            current_dialog.close if current_dialog && !dialog_closed && current_dialog.respond_to?(:close)
            model.select_tool(nil) if @overlay_active && model.respond_to?(:select_tool)
            model.active_view.invalidate if model.respond_to?(:active_view)
            @dialog = nil
            @resolution = nil
            @finalized_plan = nil
            @executor = nil
            @observer = nil
            @overlay_tool = nil
            true
          rescue StandardError
            true
          end

          def overlay_activated
            @overlay_active = true
          end

          def overlay_deactivated
            @overlay_active = false
          end

          def preview_primitives
            return [] if state.stale || !state.preview_calculated

            primitives = @primitive_builder.build(
              state.plan,
              display_settings: state.display_settings
            )
            BulkPreviewDiagnostics.log_primitive_count(primitives.length)
            primitives
          end

          def guard_model_state!
            changed = !active_model? || !entities_unchanged?
            mark_stale_from_model if changed
            state.stale
          end

          def mark_stale_from_model
            return if @closed || state.stale

            state.mark_stale
            push_state
            invalidate_view
          rescue StandardError
            nil
          end

          def handle_ready
            push_state
          end

          def handle_update_preview_display(payload)
            state.update_display_settings(parse_json_object(payload))
            refresh_all
          rescue ArgumentError => error
            send_error(error.message, 'invalid_preview_display')
          end

          def handle_analyze_selection(payload)
            settings = @settings_parser.parse(parse_json_object(payload))
            active_path = model.respond_to?(:active_path) ? model.active_path : nil
            updated = @resolver.resolve(model.selection, active_path: active_path)
            unless updated.valid?
              state.clear_preview
              refresh_all
              return send_error('Vui lòng chọn ít nhất hai chi tiết dạng Group hoặc Component.', 'invalid_selection')
            end

            @resolution = updated
            state.replace_candidates(
              board_descriptors: updated.board_descriptors,
              ignored_entity_count: updated.ignored_entity_count
            )
            state.calculate_preview(settings)
            model.select_tool(@overlay_tool) unless @overlay_active
            refresh_all
          rescue PreviewSettingsError => error
            handle_invalid_settings(error)
          end

          def handle_recalculate_preview(payload)
            return send_error(STALE_MESSAGE, 'stale_model') if guard_model_state!

            settings = @settings_parser.parse(parse_json_object(payload))
            state.calculate_preview(settings)
            refresh_all
          rescue PreviewSettingsError => error
            handle_invalid_settings(error)
          end

          def handle_ready_for_generation
            guard_model_state!
            unless state.ready?
              return send_error(
                PreviewStateSerializer::READINESS_MESSAGES.fetch(state.readiness_code),
                state.readiness_code
              )
            end

            @finalized_plan = state.plan
            request = AutomaticExecution::AutomaticJointExecutionRequest.new(
              model: model,
              plan: @finalized_plan,
              settings: state.settings,
              resolution: resolution,
              skipped_planning_count: state.skipped_position_count,
              stale: state.stale,
              finalized: true
            )
            set_generation_state(true)
            result = automatic_executor.execute(
              model: model,
              request: request,
              current_settings: state.settings
            )
            if result.success?
              message = result.user_message
              close
              CNCPlugins::UIHelpers.message(message)
              return result
            end

            state.mark_stale
            push_state
            set_generation_state(false)
            send_error(
              result.user_message,
              result.failure_code,
              details: result.failure_details
            )
            result
          rescue StandardError => error
            diagnostic = record_unexpected_execution_failure(error)
            safely_report_secondary_failure { state.mark_stale }
            safely_report_secondary_failure { set_generation_state(false) }
            safely_report_secondary_failure do
              send_error(
                'Không thể hoàn tất việc tạo mộng. Toàn bộ thay đổi đã được hoàn tác.',
                'unexpected_execution_failure',
                details: diagnostic_details(diagnostic)
              )
            end
            nil
          end

          private

          def create_dialog
            options = {
              dialog_title: DIALOG_TITLE,
              preferences_key: PREFERENCES_KEY,
              scrollable: true,
              resizable: true,
              width: 620,
              height: 650,
              min_width: 520,
              min_height: 540
            }
            options[:style] = ::UI::HtmlDialog::STYLE_DIALOG if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
            ::UI::HtmlDialog.new(options)
          end

          def configure_dialog
            dialog.set_file(UI_FILE)
            dialog.add_action_callback('preview_ready') { |_context| handle_ready }
            dialog.add_action_callback('update_preview_display') do |_context, payload|
              handle_update_preview_display(payload)
            end
            dialog.add_action_callback('preview_selection') { |_context, payload| handle_analyze_selection(payload) }
            dialog.add_action_callback('recalculate_preview') do |_context, payload|
              handle_recalculate_preview(payload)
            end
            dialog.add_action_callback('ready_for_generation') { |_context| handle_ready_for_generation }
            dialog.add_action_callback('close_preview') { |_context| close }
            dialog.set_on_closed { close(dialog_closed: true) }
            dialog.center if dialog.respond_to?(:center)
          end

          def push_state
            return unless dialog

            payload = JSON.generate(@serializer.serialize(state))
            dialog.execute_script("window.SonVuAutomaticPreview.receiveState(#{payload});")
          end

          def refresh_all
            push_state
            invalidate_view
            state
          end

          def invalidate_view
            model.active_view.invalidate if model.respond_to?(:active_view)
          end

          def send_error(message, code, field: nil, details: nil)
            diagnostic = details.respond_to?(:to_h) ? details.to_h : {}
            payload = JSON.generate(
              message: message,
              code: code,
              field: field,
              diagnostic_id: diagnostic[:diagnostic_id],
              diagnostic_detail: diagnostic[:diagnostic_detail],
              diagnostic_log_path: diagnostic[:diagnostic_log_path]
            )
            dialog.execute_script("window.SonVuAutomaticPreview.showError(#{payload});") if dialog
            nil
          end

          def set_generation_state(value)
            return unless dialog

            dialog.execute_script(
              "window.SonVuAutomaticPreview.setGenerating(#{value ? 'true' : 'false'});"
            )
          end

          def automatic_executor
            @executor ||= AutomaticExecution::AutomaticJointGeometryExecutor.new
          end

          def diagnostic_logger
            @diagnostic_logger ||= AutomaticExecution::AutomaticJointDiagnosticLogger.new
          end

          def record_unexpected_execution_failure(error)
            diagnostic_logger.record(error)
          rescue StandardError => log_error
            Kernel.puts(
              "[SonVu CNC] Could not record unexpected execution failure: " \
              "#{log_error.class}: #{log_error.message}"
            )
            Kernel.puts("#{error.class}: #{error.message}")
            error.backtrace.to_a.each { |line| Kernel.puts("  #{line}") }
            nil
          end

          def diagnostic_details(diagnostic)
            return {} unless diagnostic

            {
              diagnostic_id: diagnostic.id,
              diagnostic_log_path: diagnostic.path,
              diagnostic_detail: diagnostic.detail
            }
          end

          def safely_report_secondary_failure
            yield
          rescue StandardError => error
            record_unexpected_execution_failure(error)
            nil
          end

          def handle_invalid_settings(error)
            state.mark_input_invalid
            refresh_all
            send_error(error.message, error.code, field: error.field)
          end

          def parse_json_object(payload)
            parsed = JSON.parse(payload.to_s)
            raise ArgumentError, 'Dữ liệu từ hộp thoại không hợp lệ.' unless parsed.is_a?(Hash)

            parsed
          rescue JSON::ParserError, TypeError
            raise ArgumentError, 'Dữ liệu từ hộp thoại không hợp lệ.'
          end

          def active_model?
            !defined?(::Sketchup) || !::Sketchup.respond_to?(:active_model) || ::Sketchup.active_model.equal?(model)
          end

          def entities_unchanged?
            resolution.active_path_entities.each_with_index do |entity, index|
              return false unless valid_entity?(entity)
              current = Transform3.from_sketchup(entity.transformation).values
              return false unless current == resolution.active_path_snapshot[index]
            end
            resolution.entity_paths_by_part_id.each do |part_id, path|
              snapshots = resolution.transform_snapshots_by_part_id[part_id]
              path.each_with_index do |entity, index|
                return false unless valid_entity?(entity)
                current = Transform3.from_sketchup(entity.transformation).values
                return false unless current == snapshots[index]
              end
            end
            true
          end

          def valid_entity?(entity)
            !entity.respond_to?(:valid?) || entity.valid?
          end
        end
      end
    end
  end
end
