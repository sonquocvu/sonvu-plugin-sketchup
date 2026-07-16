# frozen_string_literal: true

# Compact bulk-preview session state and JSON-ready Vietnamese presentation
# data. Per-connection controls stay in the immutable planning layer but are
# intentionally not exposed by this workflow.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class PreviewState
          attr_reader :board_descriptors, :settings, :plan, :skipped_connections,
                      :ignored_entity_count, :stale, :display_settings,
                      :preview_calculated, :input_valid

          def initialize(board_descriptors:, settings:, ignored_entity_count: 0,
                         bulk_analyzer: BulkPreviewAnalyzer.new,
                         display_settings: PreviewDisplaySettings.defaults)
            @bulk_analyzer = bulk_analyzer
            @board_descriptors = board_descriptors.freeze
            @settings = settings
            @display_settings = display_settings
            @ignored_entity_count = ignored_entity_count.to_i
            @plan = empty_plan
            @skipped_connections = [].freeze
            @preview_calculated = false
            @input_valid = true
            @stale = false
          end

          def calculate_preview(new_settings = settings)
            @settings = new_settings
            analysis = @bulk_analyzer.analyze(board_descriptors, settings.specification)
            @plan = analysis.plan
            @skipped_connections = analysis.skipped_connections
            @preview_calculated = true
            @input_valid = true
            @stale = false
            self
          end

          alias recalculate calculate_preview

          def replace_candidates(board_descriptors:, ignored_entity_count: 0)
            @board_descriptors = board_descriptors.freeze
            @ignored_entity_count = ignored_entity_count.to_i
            clear_preview
            self
          end

          def replace_analysis(board_descriptors:, ignored_entity_count: 0)
            replace_candidates(
              board_descriptors: board_descriptors,
              ignored_entity_count: ignored_entity_count
            )
            calculate_preview
          end

          def update_display_settings(payload)
            @display_settings = PreviewDisplaySettings.from_payload(payload, current: display_settings)
            self
          end

          def mark_input_invalid
            clear_preview
            @input_valid = false
            self
          end

          def mark_stale
            @stale = true
            self
          end

          def clear_preview
            @plan = empty_plan
            @skipped_connections = [].freeze
            @preview_calculated = false
            @input_valid = true
            @stale = false
            self
          end

          def valid_connection_count
            plan.connections.length
          end

          def preview_joint_count
            plan.connections.sum { |connection| connection.joint_instances.length }
          end

          def skipped_position_count
            skipped_connections.length + ignored_entity_count
          end

          def skipped_reason_counts
            counts = skipped_connections.each_with_object(Hash.new(0)) do |record, result|
              result[record.reason_code] += 1
            end
            counts['invalid_entity'] += ignored_entity_count if ignored_entity_count.positive?
            counts.freeze
          end

          def ready?
            readiness_code == 'ready'
          end

          def readiness_code
            return 'invalid_input' unless input_valid
            return 'preview_not_calculated' unless preview_calculated
            return 'stale_model' if stale
            return 'no_valid_joints' unless preview_joint_count.positive?

            'ready'
          end

          private

          def empty_plan
            PreviewPlan.new(connections: [])
          end
        end

        class PreviewStateSerializer
          READINESS_MESSAGES = {
            'ready' => 'Bản xem trước đã sẵn sàng để tạo toàn bộ mộng hợp lệ.',
            'invalid_input' => 'Vui lòng sửa thông số trước khi tạo mộng.',
            'preview_not_calculated' => 'Bấm Xem trước để phân tích vùng chọn.',
            'stale_model' => 'Mô hình đã thay đổi. Vui lòng bấm Xem trước để phân tích lại.',
            'no_valid_joints' => 'Không có mộng hợp lệ để tạo với thông số hiện tại.'
          }.freeze
          SKIPPED_REASON_LABELS = {
            ValidationResult::CONTACT_REGION_TOO_SHORT => 'Không đủ chiều dài',
            ValidationResult::OFFSETS_CONSUME_AVAILABLE_LENGTH => 'Khoảng cách hai đầu chiếm hết chiều dài',
            ValidationResult::MINIMUM_GAP_CANNOT_BE_MAINTAINED => 'Không giữ được khoảng cách tối thiểu',
            ValidationResult::AMBIGUOUS_BOARD_THICKNESS => 'Không xác định được chiều dày tấm',
            ValidationResult::UNSUPPORTED_CONTACT_TYPE => 'Kiểu tiếp xúc không được hỗ trợ',
            ValidationResult::LINE_ONLY_CONTACT => 'Chỉ tiếp xúc theo đường',
            ValidationResult::POINT_ONLY_CONTACT => 'Chỉ tiếp xúc tại điểm',
            ValidationResult::CONTACT_AREA_TOO_SMALL => 'Vùng tiếp xúc quá nhỏ',
            ValidationResult::NO_CONTACT => 'Không có vùng tiếp xúc dùng được',
            ValidationResult::DUPLICATE_CONNECTION => 'Liên kết trùng',
            ValidationResult::JOINT_LENGTH_INVALID => 'Chiều dài mộng không hợp lệ',
            ValidationResult::JOINT_WIDTH_INVALID => 'Chiều rộng mộng không hợp lệ',
            ValidationResult::JOINT_THICKNESS_INVALID => 'Chiều dày mộng không hợp lệ',
            ValidationResult::BOARD_THICKNESS_INVALID => 'Độ dày tấm không hợp lệ',
            ValidationResult::TENON_THICKNESS_INVALID => 'Độ dày mộng dương không hợp lệ',
            ValidationResult::TENON_HEIGHT_INVALID => 'Chiều cao mộng dương không hợp lệ',
            ValidationResult::MORTISE_OPENING_INVALID => 'Miệng mộng âm không phù hợp',
            ValidationResult::MORTISE_DEPTH_INVALID => 'Chiều sâu mộng âm không phù hợp',
            ValidationResult::CUTTER_RADIUS_INVALID => 'Bán kính dao không hợp lệ',
            ValidationResult::COUNT_INVALID => 'Số lượng mộng không hợp lệ',
            BulkPreviewAnalyzer::INFEASIBLE_VERTICAL_TBONE => 'Bán kính dao không phù hợp mộng âm dọc (T-bone)',
            'invalid_entity' => 'Chi tiết không hợp lệ hoặc không phải Group/Component'
          }.freeze
          SKIPPED_NOTE = 'Một số vị trí không đủ điều kiện đã được bỏ qua. ' \
                         'Bạn có thể tạo mộng đơn lẻ tại các vị trí này sau.'.freeze

          def initialize(unit_converter: CNCPlugins::Units)
            @unit_converter = unit_converter
          end

          def serialize(state)
            readiness = state.readiness_code
            values = state.settings.to_h
            values[:edge_offset_mm] = values[:start_offset_mm]
            {
              settings: values,
              preview_display: state.display_settings.to_h,
              summary: {
                scanned_part_count: state.board_descriptors.length,
                valid_connection_count: state.valid_connection_count,
                preview_joint_count: state.preview_joint_count,
                skipped_position_count: state.skipped_position_count
              },
              skipped_groups: serialize_skipped_groups(state.skipped_reason_counts),
              skipped_note: state.skipped_position_count.positive? ? SKIPPED_NOTE : nil,
              stale: state.stale,
              stale_message: state.stale ? READINESS_MESSAGES['stale_model'] : nil,
              input_valid: state.input_valid,
              preview_calculated: state.preview_calculated,
              ready_for_generation: state.ready?,
              readiness_code: readiness,
              readiness_message: READINESS_MESSAGES.fetch(readiness)
            }
          end

          private

          def serialize_skipped_groups(reason_counts)
            reason_counts.keys.sort.map do |reason_code|
              {
                reason_code: reason_code,
                label: SKIPPED_REASON_LABELS.fetch(reason_code, 'Không đủ điều kiện an toàn'),
                count: reason_counts[reason_code]
              }
            end
          end
        end
      end
    end
  end
end
