# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticExecution
        class JointExecutionFailure < StandardError
          attr_reader :code, :details

          def initialize(code, message, details = {})
            @code = code.to_s.freeze
            @details = AutomaticPlanning::ValueSupport.freeze_hash(details)
            super(message)
          end
        end

        class AutomaticJointExecutionRequest
          attr_reader :model_identity, :plan, :settings, :settings_snapshot,
                      :resolution, :skipped_planning_count, :stale, :finalized

          def initialize(model:, plan:, settings:, resolution:, skipped_planning_count:,
                         stale: false, finalized: true)
            @model_identity = model.object_id
            @plan = plan
            @settings = settings
            @settings_snapshot = AutomaticPlanning::ValueSupport.freeze_hash(settings.to_h)
            @resolution = resolution
            @skipped_planning_count = skipped_planning_count.to_i
            @stale = !!stale
            @finalized = !!finalized
            freeze
          end

          def settings_match?(current_settings)
            current_settings && current_settings.to_h == settings_snapshot
          end
        end

        class JointExecutionResult
          attr_reader :success, :executed_connection_count, :executed_joint_pair_count,
                      :generated_mortise_count, :generated_tenon_count,
                      :skipped_planning_count, :warnings, :failure_code,
                      :failure_details, :user_message

          def self.success(connection_count:, joint_pair_count:, skipped_count:, warnings: [])
            message = "Đã tạo #{joint_pair_count} cặp mộng tại #{connection_count} liên kết."
            if skipped_count.positive?
              message = "Đã tạo #{joint_pair_count} cặp mộng tại #{connection_count} liên kết. " \
                        "Bỏ qua #{skipped_count} vị trí không hợp lệ."
            end
            new({
              success: true,
              executed_connection_count: connection_count,
              executed_joint_pair_count: joint_pair_count,
              generated_mortise_count: joint_pair_count,
              generated_tenon_count: joint_pair_count,
              skipped_planning_count: skipped_count,
              warnings: warnings,
              user_message: message
            })
          end

          def self.failure(code:, user_message:, details: {}, skipped_count: 0)
            new({
              success: false,
              executed_connection_count: 0,
              executed_joint_pair_count: 0,
              generated_mortise_count: 0,
              generated_tenon_count: 0,
              skipped_planning_count: skipped_count,
              warnings: [],
              failure_code: code,
              failure_details: details,
              user_message: user_message
            })
          end

          def initialize(attributes)
            @success = !!attributes.fetch(:success)
            @executed_connection_count = attributes.fetch(:executed_connection_count).to_i
            @executed_joint_pair_count = attributes.fetch(:executed_joint_pair_count).to_i
            @generated_mortise_count = attributes.fetch(:generated_mortise_count).to_i
            @generated_tenon_count = attributes.fetch(:generated_tenon_count).to_i
            @skipped_planning_count = attributes.fetch(:skipped_planning_count).to_i
            @warnings = attributes.fetch(:warnings).map(&:to_s).freeze
            @failure_code = attributes[:failure_code] && attributes[:failure_code].to_s.freeze
            @failure_details = AutomaticPlanning::ValueSupport.freeze_hash(attributes.fetch(:failure_details, {}))
            @user_message = attributes.fetch(:user_message).to_s.freeze
            freeze
          end

          def success?
            success
          end
        end

        class JointGeometryPlacement
          attr_reader :role, :world_center, :center, :x_axis, :y_axis, :z_axis,
                      :execution_direction, :world_execution_direction

          def initialize(role:, world_center:, center:, x_axis:, y_axis:, z_axis:,
                         execution_direction:, world_execution_direction:)
            @role = role.to_s.freeze
            @world_center = world_center
            @center = center
            @x_axis = x_axis
            @y_axis = y_axis
            @z_axis = z_axis
            @execution_direction = execution_direction
            @world_execution_direction = world_execution_direction
            freeze
          end

          def to_sketchup_transformation
            Geom::Transformation.axes(
              Geom::Point3d.new(center.x, center.y, center.z),
              Geom::Vector3d.new(x_axis.x, x_axis.y, x_axis.z),
              Geom::Vector3d.new(y_axis.x, y_axis.y, y_axis.z),
              Geom::Vector3d.new(z_axis.x, z_axis.y, z_axis.z)
            )
          end
        end
      end
    end
  end
end
