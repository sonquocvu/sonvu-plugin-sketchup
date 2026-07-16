# frozen_string_literal: true

# Unit-agnostic joint layout input, fit validation, and shared-axis calculation.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class JointLayoutSpecification
          FIELDS = [
            :joint_length,
            :fit_clearance,
            :tenon_height,
            :mortise_depth,
            :cutter_radius,
            :requested_count,
            :start_offset,
            :end_offset,
            :minimum_gap,
            :geometric_tolerance
          ].freeze

          attr_reader(*FIELDS)

          def initialize(joint_length: nil, joint_width: nil, joint_thickness: nil,
                         fit_clearance: 0.0, tenon_height: 10.0, mortise_depth: 10.0,
                         cutter_radius: 3.0, requested_count:, start_offset: 0.0,
                         end_offset: 0.0, minimum_gap: 0.0, geometric_tolerance: 0.001)
            @joint_length = joint_length.nil? ? joint_width : joint_length
            @fit_clearance = fit_clearance
            @tenon_height = tenon_height
            @mortise_depth = mortise_depth
            @cutter_radius = cutter_radius
            @requested_count = requested_count
            @start_offset = start_offset
            @end_offset = end_offset
            @minimum_gap = minimum_gap
            @geometric_tolerance = geometric_tolerance
            # Accepted only so older in-memory callers do not fail. Automatic
            # thickness is now resolved from the male BoardDescriptor.
            joint_thickness
            freeze
          end

          # Read compatibility for pre-migration planning callers. New plans and
          # serialized settings expose only joint_length.
          def joint_width
            joint_length
          end

          def to_h
            FIELDS.each_with_object({}) { |field, hash| hash[field] = public_send(field) }
          end
        end

        class ValidationResult
          VALID = 'valid'
          CONTACT_REGION_TOO_SHORT = 'contact_region_too_short'
          JOINT_LENGTH_INVALID = 'joint_length_invalid'
          JOINT_WIDTH_INVALID = 'joint_width_invalid'
          JOINT_THICKNESS_INVALID = 'joint_thickness_invalid'
          BOARD_THICKNESS_INVALID = 'board_thickness_invalid'
          TENON_THICKNESS_INVALID = 'tenon_thickness_invalid'
          TENON_HEIGHT_INVALID = 'tenon_height_invalid'
          MORTISE_OPENING_INVALID = 'mortise_opening_invalid'
          MORTISE_DEPTH_INVALID = 'mortise_depth_invalid'
          CUTTER_RADIUS_INVALID = 'cutter_radius_invalid'
          COUNT_INVALID = 'count_invalid'
          OFFSETS_CONSUME_AVAILABLE_LENGTH = 'offsets_consume_available_length'
          MINIMUM_GAP_CANNOT_BE_MAINTAINED = 'minimum_gap_cannot_be_maintained'
          UNSUPPORTED_CONTACT_TYPE = 'unsupported_contact_type'
          AMBIGUOUS_BOARD_THICKNESS = 'ambiguous_board_thickness'
          DUPLICATE_CONNECTION = 'duplicate_connection'
          LINE_ONLY_CONTACT = 'line_only_contact'
          POINT_ONLY_CONTACT = 'point_only_contact'
          CONTACT_AREA_TOO_SMALL = 'contact_area_too_small'
          NO_CONTACT = 'no_contact'

          CODES = [
            VALID,
            CONTACT_REGION_TOO_SHORT,
            JOINT_LENGTH_INVALID,
            JOINT_WIDTH_INVALID,
            JOINT_THICKNESS_INVALID,
            BOARD_THICKNESS_INVALID,
            TENON_THICKNESS_INVALID,
            TENON_HEIGHT_INVALID,
            MORTISE_OPENING_INVALID,
            MORTISE_DEPTH_INVALID,
            CUTTER_RADIUS_INVALID,
            COUNT_INVALID,
            OFFSETS_CONSUME_AVAILABLE_LENGTH,
            MINIMUM_GAP_CANNOT_BE_MAINTAINED,
            UNSUPPORTED_CONTACT_TYPE,
            AMBIGUOUS_BOARD_THICKNESS,
            DUPLICATE_CONNECTION,
            LINE_ONLY_CONTACT,
            POINT_ONLY_CONTACT,
            CONTACT_AREA_TOO_SMALL,
            NO_CONTACT
          ].freeze

          attr_reader :code, :details

          def self.valid(details = {})
            new(VALID, details)
          end

          def initialize(code, details = {})
            raise ArgumentError, 'Mã kiểm tra không được hỗ trợ.' unless CODES.include?(code.to_s)

            @code = code.to_s.freeze
            @details = ValueSupport.freeze_hash(details)
            freeze
          end

          def valid?
            code == VALID
          end

          def to_h
            { valid: valid?, code: code, details: details }
          end
        end

        module VietnameseValidationMessages
          MESSAGES = {
            ValidationResult::VALID => 'Bố trí mộng hợp lệ.',
            ValidationResult::CONTACT_REGION_TOO_SHORT => 'Vùng tiếp xúc quá ngắn cho số lượng và kích thước mộng đã yêu cầu.',
            ValidationResult::JOINT_LENGTH_INVALID => 'Chiều dài mộng phải là số hữu hạn lớn hơn 0.',
            ValidationResult::JOINT_WIDTH_INVALID => 'Chiều rộng mộng phải là số hữu hạn lớn hơn 0.',
            ValidationResult::JOINT_THICKNESS_INVALID => 'Chiều dày mộng không hợp lệ hoặc vượt quá chiều dày chi tiết nhận mộng.',
            ValidationResult::BOARD_THICKNESS_INVALID => 'Độ dày tấm phải là số hữu hạn lớn hơn 0.',
            ValidationResult::TENON_THICKNESS_INVALID => 'Độ dày mộng dương sau độ hở không hợp lệ.',
            ValidationResult::TENON_HEIGHT_INVALID => 'Chiều cao mộng dương không hợp lệ.',
            ValidationResult::MORTISE_OPENING_INVALID => 'Kích thước miệng mộng âm không phù hợp vùng tiếp xúc.',
            ValidationResult::MORTISE_DEPTH_INVALID => 'Chiều sâu mộng âm vượt quá độ dày tấm nhận mộng.',
            ValidationResult::CUTTER_RADIUS_INVALID => 'Bán kính dao không hợp lệ.',
            ValidationResult::COUNT_INVALID => 'Số lượng mộng phải là số nguyên lớn hơn hoặc bằng 1.',
            ValidationResult::OFFSETS_CONSUME_AVAILABLE_LENGTH => 'Khoảng lùi hai đầu đã chiếm hết chiều dài bố trí mộng.',
            ValidationResult::MINIMUM_GAP_CANNOT_BE_MAINTAINED => 'Không thể giữ khoảng hở tối thiểu giữa các mộng.',
            ValidationResult::UNSUPPORTED_CONTACT_TYPE => 'Kiểu tiếp xúc này chưa hỗ trợ tạo mộng tự động.',
            ValidationResult::AMBIGUOUS_BOARD_THICKNESS => 'Không xác định được chiều dày tấm ván một cách tin cậy.',
            ValidationResult::DUPLICATE_CONNECTION => 'Liên kết này đã được phát hiện trước đó.',
            ValidationResult::LINE_ONLY_CONTACT => 'Hai chi tiết chỉ tiếp xúc theo một đường.',
            ValidationResult::POINT_ONLY_CONTACT => 'Hai chi tiết chỉ tiếp xúc tại một điểm.',
            ValidationResult::CONTACT_AREA_TOO_SMALL => 'Diện tích vùng tiếp xúc nhỏ hơn dung sai hình học.',
            ValidationResult::NO_CONTACT => 'Hai chi tiết không có vùng tiếp xúc phẳng hợp lệ.'
          }.freeze

          module_function

          def message_for(validation_or_code)
            code = validation_or_code.respond_to?(:code) ? validation_or_code.code : validation_or_code.to_s
            MESSAGES.fetch(code, 'Không thể kiểm tra bố trí mộng.')
          end
        end

        class LayoutCalculation
          attr_reader :contact_length, :usable_contact_length, :total_joint_length,
                      :remaining_distributable_space, :calculated_gap, :maximum_feasible_count,
                      :axis_starts, :axis_ends, :axis_centers, :validation

          def initialize(contact_length:, usable_contact_length:, total_joint_length:,
                         remaining_distributable_space:, calculated_gap:, maximum_feasible_count:,
                         axis_starts:, axis_ends:, axis_centers:, validation:)
            @contact_length = contact_length
            @usable_contact_length = usable_contact_length
            @total_joint_length = total_joint_length
            @remaining_distributable_space = remaining_distributable_space
            @calculated_gap = calculated_gap
            @maximum_feasible_count = maximum_feasible_count
            @axis_starts = axis_starts.freeze
            @axis_ends = axis_ends.freeze
            @axis_centers = axis_centers.freeze
            @validation = validation
            freeze
          end

          def valid?
            validation.valid?
          end

          def total_joint_width
            total_joint_length
          end

          def to_h
            {
              contact_length: contact_length,
              usable_contact_length: usable_contact_length,
              total_joint_length: total_joint_length,
              remaining_distributable_space: remaining_distributable_space,
              calculated_gap: calculated_gap,
              maximum_feasible_count: maximum_feasible_count,
              axis_starts: axis_starts,
              axis_ends: axis_ends,
              axis_centers: axis_centers,
              validation: validation.to_h
            }
          end
        end

        class JointLayoutCalculator
          def calculate(contact_length:, axis_min:, specification:, female_board_thickness: nil,
                        board_thickness_ambiguous: false)
            length = numeric_value(contact_length)
            start_offset = numeric_value(specification.start_offset)
            end_offset = numeric_value(specification.end_offset)
            joint_length = numeric_value(specification.joint_length)
            minimum_gap = numeric_value(specification.minimum_gap)
            tolerance = positive_tolerance(specification.geometric_tolerance)
            count = valid_count(specification.requested_count)

            usable = value_or_nil(length, start_offset, end_offset) do
              length - start_offset - end_offset
            end
            total_length = count && joint_length ? count * joint_length : nil
            remaining = usable && total_length ? usable - total_length : nil
            maximum = maximum_count(usable, joint_length, minimum_gap)

            validation = validate(
              length: length,
              usable: usable,
              joint_length: joint_length,
              count: count,
              requested_count: specification.requested_count,
              start_offset: start_offset,
              end_offset: end_offset,
              minimum_gap: minimum_gap,
              tolerance: tolerance,
              total_length: total_length,
              remaining: remaining,
              maximum: maximum
            )

            # These keywords belonged to the old global-thickness contract.
            # Accept them without allowing them to influence new layouts.
            female_board_thickness
            board_thickness_ambiguous

            starts = []
            ends = []
            centers = []
            calculated_gap = calculated_gap(count, remaining)
            if validation.valid?
              starts, ends, centers = shared_positions(
                axis_min.to_f,
                joint_length,
                count,
                start_offset,
                usable,
                remaining,
                calculated_gap
              )
            end

            LayoutCalculation.new(
              contact_length: length,
              usable_contact_length: usable,
              total_joint_length: total_length,
              remaining_distributable_space: remaining,
              calculated_gap: calculated_gap,
              maximum_feasible_count: maximum,
              axis_starts: starts,
              axis_ends: ends,
              axis_centers: centers,
              validation: validation
            )
          end

          private

          def validate(values)
            details = calculation_details(values)
            unless positive?(values[:joint_length], values[:tolerance])
              return ValidationResult.new(ValidationResult::JOINT_LENGTH_INVALID, details)
            end
            return ValidationResult.new(ValidationResult::COUNT_INVALID, details) unless values[:count]
            unless nonnegative?(values[:start_offset]) && nonnegative?(values[:end_offset])
              return ValidationResult.new(ValidationResult::OFFSETS_CONSUME_AVAILABLE_LENGTH, details)
            end
            return ValidationResult.new(ValidationResult::CONTACT_REGION_TOO_SHORT, details) unless positive?(values[:length], values[:tolerance])
            if values[:length] + values[:tolerance] < values[:joint_length]
              return ValidationResult.new(ValidationResult::CONTACT_REGION_TOO_SHORT, details)
            end
            unless values[:usable] && values[:usable] + values[:tolerance] >= values[:joint_length]
              return ValidationResult.new(ValidationResult::OFFSETS_CONSUME_AVAILABLE_LENGTH, details)
            end
            if values[:total_length] > values[:usable] + values[:tolerance]
              return ValidationResult.new(ValidationResult::CONTACT_REGION_TOO_SHORT, details)
            end
            unless nonnegative?(values[:minimum_gap])
              return ValidationResult.new(ValidationResult::MINIMUM_GAP_CANNOT_BE_MAINTAINED, details)
            end
            if values[:count] > 1 && calculated_gap(values[:count], values[:remaining]) + values[:tolerance] < values[:minimum_gap]
              return ValidationResult.new(ValidationResult::MINIMUM_GAP_CANNOT_BE_MAINTAINED, details)
            end

            ValidationResult.valid(details)
          end

          def calculation_details(values)
            {
              contact_length: values[:length],
              usable_contact_length: values[:usable],
              joint_length: values[:joint_length],
              requested_count: values[:requested_count],
              start_offset: values[:start_offset],
              end_offset: values[:end_offset],
              minimum_gap: values[:minimum_gap],
              total_joint_length: values[:total_length],
              remaining_distributable_space: values[:remaining],
              maximum_feasible_count: values[:maximum]
            }
          end

          def shared_positions(axis_min, width, count, start_offset, usable, remaining, gap)
            if count == 1
              first = axis_min + start_offset + ((usable - width) / 2.0)
              return [[first], [first + width], [first + (width / 2.0)]]
            end

            starts = count.times.map { |index| axis_min + start_offset + (index * (width + gap)) }
            ends = starts.map { |start| start + width }
            centers = starts.zip(ends).map { |start, finish| (start + finish) / 2.0 }
            [starts, ends, centers]
          end

          def calculated_gap(count, remaining)
            return nil unless count && remaining
            return 0.0 if count == 1

            remaining / (count - 1).to_f
          end

          def maximum_count(usable, width, minimum_gap)
            return nil unless usable && positive?(width, 0.0) && nonnegative?(minimum_gap)
            return 0 if usable < width

            ((usable + minimum_gap) / (width + minimum_gap)).floor
          end

          def valid_count(value)
            return nil unless ValueSupport.finite_number?(value)

            integer = value.to_i
            integer >= 1 && value.to_f == integer.to_f ? integer : nil
          end

          def numeric_value(value)
            ValueSupport.finite_number?(value) ? value.to_f : nil
          end

          def positive_tolerance(value)
            numeric = numeric_value(value)
            numeric && numeric.positive? ? numeric : 1.0e-9
          end

          def positive?(value, tolerance)
            value && value > tolerance
          end

          def nonnegative?(value)
            value && value >= 0.0
          end

          def value_or_nil(*values)
            values.all? { |value| !value.nil? } ? yield : nil
          end
        end
      end
    end
  end
end
