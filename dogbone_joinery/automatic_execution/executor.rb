# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticExecution
        class PreparedJointExecution
          attr_reader :connection, :joint, :male_reference, :female_reference,
                      :male_placement, :female_placement, :tenon_params,
                      :mortise_params

          def initialize(attributes)
            @connection = attributes.fetch(:connection)
            @joint = attributes.fetch(:joint)
            @male_reference = attributes.fetch(:male_reference)
            @female_reference = attributes.fetch(:female_reference)
            @male_placement = attributes.fetch(:male_placement)
            @female_placement = attributes.fetch(:female_placement)
            @tenon_params = attributes.fetch(:tenon_params)
            @mortise_params = attributes.fetch(:mortise_params)
            freeze
          end
        end

        class AutomaticJointGeometryExecutor
          DEFAULT_OPERATION_NAME = 'Tạo mộng âm dương tự động'.freeze
          INTEGRITY_MESSAGE = 'Mô hình hoặc bản xem trước đã thay đổi. ' \
                              'Vui lòng phân tích lại trước khi tạo mộng.'.freeze
          FAILURE_MESSAGE = 'Không thể hoàn tất việc tạo mộng. ' \
                            'Toàn bộ thay đổi đã được hoàn tác.'.freeze

          def initialize(geometry_adapter: ManualGeometryExecutionAdapter.new,
                         parameter_adapter: GeometryParameterAdapter.new,
                         transform_adapter: JointTransformAdapter.new,
                         active_model_provider: nil)
            @geometry_adapter = geometry_adapter
            @parameter_adapter = parameter_adapter
            @transform_adapter = transform_adapter
            @active_model_provider = active_model_provider || lambda { Sketchup.active_model }
          end

          def execute(model:, request:, current_settings:, operation_name: DEFAULT_OPERATION_NAME)
            operation_started = false
            registry, prepared = prepare_execution(model, request, current_settings)

            model.start_operation(operation_name, true)
            operation_started = true
            ensure_unique_targets!(registry)
            executed_connection_ids = {}

            prepared.each do |item|
              tenon_result = @geometry_adapter.generate_tenon(
                target: item.male_reference.entity,
                params: item.tenon_params,
                placement: item.male_placement,
                parent_entities: item.male_reference.parent_entities
              )
              validate_generated_result!(tenon_result, 'tenon_generation_failed', item)
              registry.replace(item.connection.male_part_identity, tenon_result)

              mortise_result = @geometry_adapter.generate_mortise(
                target: item.female_reference.entity,
                params: item.mortise_params,
                placement: item.female_placement,
                parent_entities: item.female_reference.parent_entities
              )
              validate_generated_result!(mortise_result, 'mortise_generation_failed', item)
              registry.replace(item.connection.female_part_identity, mortise_result)
              executed_connection_ids[item.connection.stable_id] = true
            end

            model.commit_operation
            operation_started = false
            JointExecutionResult.success(
              connection_count: executed_connection_ids.length,
              joint_pair_count: prepared.length,
              skipped_count: request.skipped_planning_count
            )
          rescue JointExecutionFailure => error
            abort_operation(model) if operation_started
            log_failure(error)
            JointExecutionResult.failure(
              code: error.code,
              user_message: error.message,
              details: error_details(error),
              skipped_count: request ? request.skipped_planning_count : 0
            )
          rescue StandardError => error
            abort_operation(model) if operation_started
            log_failure(error)
            JointExecutionResult.failure(
              code: 'unexpected_execution_failure',
              user_message: FAILURE_MESSAGE,
              details: error_details(error),
              skipped_count: request ? request.skipped_planning_count : 0
            )
          end

          private

          def prepare_execution(model, request, current_settings)
            validate_request!(model, request, current_settings)
            registry = ExecutionEntityRegistry.new(request.resolution)
            jobs = executable_jobs(request.plan)
            validate_jobs!(jobs, request)
            prepared = jobs.map do |connection, joint|
              male_reference = registry.validate_for!(connection.male_part_identity, :male)
              female_reference = registry.validate_for!(connection.female_part_identity, :female)
              PreparedJointExecution.new(
                connection: connection,
                joint: joint,
                male_reference: male_reference,
                female_reference: female_reference,
                male_placement: @transform_adapter.placement_for(
                  connection, joint, male_reference, :male
                ),
                female_placement: @transform_adapter.placement_for(
                  connection, joint, female_reference, :female
                ),
                tenon_params: @parameter_adapter.tenon_parameters(
                  connection, joint, request.settings
                ),
                mortise_params: @parameter_adapter.mortise_parameters(
                  connection, joint, request.settings
                )
              )
            end
            [registry, prepared.freeze]
          end

          def validate_request!(model, request, current_settings)
            fail_integrity('execution_request_missing') unless request
            fail_integrity('plan_not_finalized') unless request.finalized
            fail_integrity('preview_stale') if request.stale
            fail_integrity('wrong_model') unless request.model_identity == model.object_id
            fail_integrity('inactive_model') unless @active_model_provider.call.equal?(model)
            fail_integrity('settings_changed') unless request.settings_match?(current_settings)
            fail_integrity('resolution_missing') unless request.resolution
          end

          def executable_jobs(plan)
            plan.connections.sort_by(&:stable_id).flat_map do |connection|
              next [] unless connection.enabled && connection.valid?

              connection.joint_instances.select(&:enabled).sort_by(&:stable_id).map do |joint|
                [connection, joint]
              end
            end
          end

          def validate_jobs!(jobs, request)
            fail_integrity('no_executable_joints') if jobs.empty?
            validate_connection_uniqueness!(jobs)
            joint_ids = {}
            geometry_keys = {}
            jobs.each do |connection, joint|
              fail_integrity('assignment_missing') unless connection.male_part_identity &&
                                                         connection.female_part_identity
              fail_integrity('same_part_assignment') if connection.male_part_identity ==
                                                         connection.female_part_identity
              fail_integrity('joint_id_missing') if joint.stable_id.to_s.empty?
              fail_integrity('duplicate_joint_id') if joint_ids[joint.stable_id]

              joint_ids[joint.stable_id] = true
              validate_joint_geometry!(connection, joint)
              key = duplicate_geometry_key(connection, joint)
              fail_integrity('duplicate_joint_geometry') if geometry_keys[key]

              geometry_keys[key] = true
              unless connection.requested_settings.to_h == request.settings.specification.to_h
                fail_integrity('connection_settings_changed')
              end
            end
          end

          def validate_connection_uniqueness!(jobs)
            connection_ids = {}
            part_pairs = {}
            jobs.map(&:first).uniq.each do |connection|
              fail_integrity('connection_id_missing') if connection.stable_id.to_s.empty?
              fail_integrity('duplicate_connection_id') if connection_ids[connection.stable_id]

              connection_ids[connection.stable_id] = true
              pair = [
                connection.male_part_identity && connection.male_part_identity.stable_id,
                connection.female_part_identity && connection.female_part_identity.stable_id
              ].compact.sort
              fail_integrity('duplicate_part_pair') if pair.length == 2 && part_pairs[pair]

              part_pairs[pair] = true if pair.length == 2
            end
          end

          def validate_joint_geometry!(connection, joint)
            values = [
              joint.joint_length,
              joint.detected_male_board_thickness,
              joint.tenon_thickness,
              joint.mortise_opening_thickness,
              joint.tenon_height,
              joint.mortise_depth,
              joint.cutter_radius
            ]
            unless values.all? do |value|
                     AutomaticPlanning::ValueSupport.finite_number?(value) && value.to_f.positive?
                   end
              fail_integrity('joint_dimensions_invalid')
            end
            unless AutomaticPlanning::ValueSupport.finite_number?(joint.fit_clearance) &&
                   joint.fit_clearance.to_f >= 0.0
              fail_integrity('joint_clearance_invalid')
            end
            tolerance = connection.requested_settings.geometric_tolerance.to_f
            unless (joint.mortise_opening_thickness -
                    joint.tenon_thickness - joint.fit_clearance).abs <= tolerance
              fail_integrity('joint_clearance_contract_changed')
            end
            unless (joint.detected_male_board_thickness -
                    joint.mortise_opening_thickness).abs <= tolerance
              fail_integrity('joint_board_thickness_changed')
            end
            fail_integrity('joint_center_invalid') unless joint.center_position
            placements = [joint.male_placement, joint.female_placement]
            fail_integrity('joint_placement_missing') unless placements.all?
            fail_integrity('joint_center_mismatch') unless placements.all? do |placement|
              same_point?(placement.origin, joint.center_position)
            end
            directions = [connection.tenon_inward_direction, connection.mortise_inward_direction]
            fail_integrity('joint_direction_invalid') unless directions.all? do |direction|
              direction && direction.length > AutomaticPlanning::Vector3::EPSILON
            end
            fail_integrity('joint_placement_invalid') unless placements.all? do |placement|
              valid_placement?(placement)
            end
            thickness_axis = joint.thickness_axis
            fail_integrity('joint_thickness_axis_invalid') unless thickness_axis &&
                                                                      thickness_axis.length > AutomaticPlanning::Vector3::EPSILON
            canonical_thickness = thickness_axis.normalized.canonical
            fail_integrity('joint_thickness_axis_mismatch') unless placements.all? do |placement|
              (placement.y_axis.normalized.canonical - canonical_thickness).length <=
                AutomaticPlanning::Vector3::EPSILON
            end
          end

          def same_point?(first, second)
            first && second && (first - second).length <= AutomaticPlanning::Vector3::EPSILON
          end

          def valid_placement?(placement)
            axes = [placement.x_axis, placement.y_axis, placement.z_axis]
            axes.all? { |axis| axis && axis.length > AutomaticPlanning::Vector3::EPSILON } &&
              placement.insertion_direction &&
              placement.insertion_direction.length > AutomaticPlanning::Vector3::EPSILON
          end

          def duplicate_geometry_key(connection, joint)
            parts = [
              connection.male_part_identity.stable_id,
              connection.female_part_identity.stable_id
            ].sort
            center = joint.center_position.to_a.map { |value| value.round(8) }
            [parts, center]
          end

          def validate_generated_result!(result, code, item)
            valid = result && (!result.respond_to?(:valid?) || result.valid?)
            solid = valid && result.respond_to?(:manifold?) && result.manifold?
            return if solid

            message = if code == 'tenon_generation_failed'
                        'Kết quả mộng dương không còn là solid hợp lệ. Toàn bộ thay đổi đã được hoàn tác.'
                      else
                        'Kết quả mộng âm không còn là solid hợp lệ. Toàn bộ thay đổi đã được hoàn tác.'
                      end
            raise JointExecutionFailure.new(
              code,
              message,
              connection_id: item.connection.stable_id,
              joint_id: item.joint.stable_id
            )
          end

          def ensure_unique_targets!(registry)
            registry.ensure_unique_all!
          rescue JointExecutionFailure
            raise
          rescue StandardError => error
            raise JointExecutionFailure.new(
              'entity_isolation_failed',
              'Không thể tách riêng component dùng chung trước khi tạo mộng. ' \
              'Toàn bộ thay đổi đã được hoàn tác.',
              error_class: error.class.name,
              error_message: error.message
            )
          end

          def fail_integrity(code)
            raise JointExecutionFailure.new(code, INTEGRITY_MESSAGE)
          end

          def error_details(error)
            details = {
              error_class: error.class.name,
              message: error.message
            }
            details[:context] = error.details if error.respond_to?(:details)
            details
          end

          def log_failure(error)
            return unless defined?(ENV) && ENV['SONVU_CNC_DEBUG'] == '1'

            $stderr.puts("[SonVu CNC] automatic_joint_failure=#{error.class}: #{error.message}")
            if error.respond_to?(:details) && !error.details.empty?
              $stderr.puts("[SonVu CNC] automatic_joint_details=#{error.details.inspect}")
            end
            $stderr.puts(error.backtrace.join("\n")) if error.backtrace
          end

          def abort_operation(model)
            model.abort_operation
          rescue StandardError => abort_error
            log_failure(abort_error)
          end
        end
      end
    end
  end
end
