# frozen_string_literal: true

# Partial-success adapter for the compact automatic-joint workflow. The core
# Analyzer remains unchanged for future advanced workflows; this adapter keeps
# only safe connection plans and converts local failures to lightweight records.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class SkippedConnectionRecord
          attr_reader :reason_code, :first_part_id, :second_part_id, :details

          def self.from_connection(connection)
            new(
              reason_code: connection.validation.code,
              first_part_id: connection.first_part_identity.stable_id,
              second_part_id: connection.second_part_identity.stable_id,
              details: {
                requested_count: connection.requested_settings.requested_count,
                maximum_feasible_count: connection.calculated_settings.maximum_feasible_count
              }
            )
          end

          def self.from_diagnostic(diagnostic)
            new(
              reason_code: diagnostic.validation.code,
              first_part_id: diagnostic.first_part_id,
              second_part_id: diagnostic.second_part_id
            )
          end

          def self.for_connection_reason(connection, reason_code, details: {})
            new(
              reason_code: reason_code,
              first_part_id: connection.first_part_identity.stable_id,
              second_part_id: connection.second_part_identity.stable_id,
              details: details
            )
          end

          def initialize(reason_code:, first_part_id: nil, second_part_id: nil, details: {})
            @reason_code = reason_code.to_s.freeze
            @first_part_id = first_part_id && first_part_id.to_s.freeze
            @second_part_id = second_part_id && second_part_id.to_s.freeze
            @details = ValueSupport.freeze_hash(details)
            freeze
          end

          def to_h
            {
              reason_code: reason_code,
              first_part_id: first_part_id,
              second_part_id: second_part_id,
              details: details
            }
          end
        end

        class BulkPreviewAnalysis
          attr_reader :plan, :skipped_connections, :raw_connection_count

          def initialize(plan:, skipped_connections:, raw_connection_count:)
            @plan = plan
            @skipped_connections = skipped_connections.freeze
            @raw_connection_count = raw_connection_count.to_i
            freeze
          end

          def valid_connection_count
            plan.connections.length
          end

          def joint_count
            plan.connections.sum { |connection| connection.joint_instances.length }
          end

          def skipped_reason_counts
            skipped_connections.each_with_object(Hash.new(0)) do |record, counts|
              counts[record.reason_code] += 1
            end.freeze
          end
        end

        class BulkPreviewAnalyzer
          INFEASIBLE_VERTICAL_TBONE = 'infeasible_vertical_tbone'.freeze

          def initialize(analyzer: Analyzer.new)
            @analyzer = analyzer
          end

          def analyze(board_descriptors, specification)
            raw_plan = @analyzer.analyze(board_descriptors, specification)
            planned_connections = raw_plan.connections.select do |connection|
              connection.valid? && !connection.joint_instances.empty?
            end
            valid_connections, infeasible_tbone = planned_connections.partition do |connection|
              vertical_tbone_feasible?(connection)
            end
            skipped = raw_plan.connections.reject do |connection|
              connection.valid? && !connection.joint_instances.empty?
            end.map { |connection| SkippedConnectionRecord.from_connection(connection) }
            skipped.concat(infeasible_tbone.map do |connection|
              first_joint = connection.joint_instances.first
              SkippedConnectionRecord.for_connection_reason(
                connection,
                INFEASIBLE_VERTICAL_TBONE,
                details: {
                  cutter_radius: first_joint && first_joint.cutter_radius,
                  joint_length: first_joint && first_joint.joint_length,
                  mortise_opening_thickness: first_joint && first_joint.mortise_opening_thickness
                }
              )
            end)
            skipped.concat(
              raw_plan.diagnostics.map { |diagnostic| SkippedConnectionRecord.from_diagnostic(diagnostic) }
            )
            result = BulkPreviewAnalysis.new(
              plan: PreviewPlan.new(connections: valid_connections),
              skipped_connections: skipped,
              raw_connection_count: raw_plan.connections.length
            )
            BulkPreviewDiagnostics.log_analysis(board_descriptors.length, result)
            result
          end

          private

          def vertical_tbone_feasible?(connection)
            connection.joint_instances.all? do |joint|
              VerticalTBoneGeometry.feasible?(
                width: joint.joint_length,
                height: joint.mortise_opening_thickness,
                radius: joint.cutter_radius
              )
            end
          end
        end

        module BulkPreviewDiagnostics
          module_function

          def enabled?
            defined?(ENV) && ENV['SONVU_CNC_DEBUG'] == '1'
          end

          def log_analysis(part_count, result)
            return unless enabled?

            $stdout.puts(
              "[SonVu CNC] chi_tiet=#{part_count} " \
              "lien_ket_hop_le=#{result.valid_connection_count} " \
              "tong_mong=#{result.joint_count} " \
              "bo_qua=#{result.skipped_reason_counts.inspect}"
            )
          end

          def log_primitive_count(count)
            return unless enabled?

            $stdout.puts("[SonVu CNC] preview_primitives=#{count}")
          end
        end
      end
    end
  end
end
