# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticExecution
        class AutomaticJointDiagnosticLogger
          LOG_PATH = File.expand_path('automatic_joint_diagnostics.log', __dir__).freeze
          Entry = Struct.new(:id, :path, :detail)

          def initialize(path: LOG_PATH, clock: nil, console: nil, console_controller: nil)
            @path = path
            @clock = clock || lambda { Time.now }
            @console = console
            @console_controller = console_controller
            @sequence = 0
            @instance_token = format('%04X', object_id & 0xffff)
          end

          def record(error)
            timestamp = @clock.call
            diagnostic_id = next_id(timestamp)
            detail = root_detail(error)
            payload = format_record(diagnostic_id, timestamp, error, detail)
            file_error = append_record(payload)
            emit_to_ruby_console(payload)
            if file_error
              emit_to_ruby_console(
                "[SonVu CNC] Could not write diagnostic file: " \
                "#{file_error.class}: #{file_error.message}"
              )
            end
            Entry.new(diagnostic_id, file_error ? nil : @path, detail)
          rescue StandardError => log_error
            emit_to_ruby_console(
              "[SonVu CNC] Diagnostic logger failure: #{log_error.class}: #{log_error.message}"
            )
            Entry.new(diagnostic_id || 'SVJ-LOG-ERROR', nil, detail || error.message.to_s)
          end

          private

          def next_id(timestamp)
            @sequence += 1
            "SVJ-#{timestamp.strftime('%Y%m%d-%H%M%S')}-#{@instance_token}-#{format('%03d', @sequence)}"
          end

          def append_record(payload)
            File.open(@path, 'a:UTF-8') { |file| file.write(payload) }
            nil
          rescue StandardError => error
            error
          end

          def emit_to_ruby_console(message)
            show_ruby_console
            output = @console
            if output
              output.puts(message)
              output.flush if output.respond_to?(:flush)
            else
              Kernel.puts(message)
              $stdout.flush if $stdout.respond_to?(:flush)
            end
            true
          rescue StandardError => console_error
            begin
              Kernel.puts(
                "[SonVu CNC] Ruby Console output failure: " \
                "#{console_error.class}: #{console_error.message}"
              )
              Kernel.puts(message)
            rescue StandardError
              nil
            end
            false
          end

          def show_ruby_console
            controller = @console_controller
            controller ||= ::SKETCHUP_CONSOLE if defined?(::SKETCHUP_CONSOLE)
            controller.show if controller && controller.respond_to?(:show)
          rescue StandardError => error
            Kernel.puts(
              "[SonVu CNC] Could not show Ruby Console: #{error.class}: #{error.message}"
            )
          end

          def root_detail(error)
            details = error.respond_to?(:details) ? error.details : {}
            value = details[:error_message] || details['error_message'] || error.message
            value.to_s.gsub(/\s+/, ' ').strip[0, 500]
          end

          def format_record(diagnostic_id, timestamp, error, detail)
            code = error.respond_to?(:code) ? error.code : 'unexpected_execution_failure'
            details = error.respond_to?(:details) ? error.details : {}
            backtrace = error.backtrace.to_a.first(40)
            lines = [
              "\n=== SonVu Automatic Joint Diagnostic #{diagnostic_id} ===",
              "time=#{timestamp.strftime('%Y-%m-%d %H:%M:%S %z')}",
              "code=#{code}",
              "error_class=#{error.class}",
              "message=#{error.message}",
              "root_detail=#{detail}",
              "context=#{details.inspect}",
              'backtrace:'
            ]
            lines.concat(backtrace.map { |line| "  #{line}" })
            lines << "=== End #{diagnostic_id} ===\n"
            lines.join("\n")
          end
        end
      end
    end
  end
end
