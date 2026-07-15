# frozen_string_literal: true

# Development-only CLI for generating the RSA key pair and manually issuing
# signed offline tokens. Exclude this tools folder from every customer RBZ.

require 'base64'
require 'fileutils'
require 'io/console'
require 'json'
require 'openssl'
require 'securerandom'

module SonVu
  module CNCPlugins
    module Licensing
      module Tools
        module Issuer
          PRODUCT_ID = 'sonvu_cnc_plugins'
          DEFAULT_FEATURES = 'dogbone_joinery,furniture_builder'
          SECONDS_PER_DAY = 86_400

          module_function

          def run(arguments)
            command = arguments.shift.to_s
            case command
            when 'init'
              initialize_keys(arguments.shift)
            when 'issue'
              issue_from_arguments(arguments)
            else
              warn usage
              1
            end
          rescue StandardError => e
            warn "Error: #{e.message}"
            1
          end

          def initialize_keys(directory)
            raise ArgumentError, 'Provide a secure key directory outside sonvu_cnc_plugins.' if directory.to_s.strip.empty?

            key_directory = File.expand_path(directory)
            reject_plugin_directory!(key_directory)
            FileUtils.mkdir_p(key_directory)
            private_path = File.join(key_directory, 'sonvu_license_private.pem')
            public_path = File.join(key_directory, 'sonvu_license_public.pem')
            raise ArgumentError, 'Key files already exist; refusing to overwrite them.' if File.exist?(private_path) || File.exist?(public_path)

            password = read_new_password
            key = OpenSSL::PKey::RSA.new(3072)
            cipher = OpenSSL::Cipher.new('aes-256-cbc')
            File.binwrite(private_path, key.export(cipher, password))
            File.chmod(0o600, private_path)
            File.binwrite(public_path, key.public_key.to_pem)

            puts "Private key: #{private_path}"
            puts "Public key:  #{public_path}"
            puts 'Back up the private key securely. Copy only the public PEM into Licensing::Config.'
            0
          end

          def issue_from_arguments(arguments)
            private_path, device_id, output_path, customer, days, features = arguments
            raise ArgumentError, usage unless private_path && device_id && output_path
            normalized_device_id = normalize_device_id!(device_id)

            duration_days = Integer(days || 30)
            raise ArgumentError, 'Days must be between 1 and 3660.' unless duration_days.between?(1, 3660)

            feature_list = (features || DEFAULT_FEATURES).split(',').map(&:strip).reject(&:empty?)
            raise ArgumentError, 'At least one feature is required.' if feature_list.empty?

            password = read_password('Private-key password: ')
            private_key = OpenSSL::PKey::RSA.new(File.binread(private_path), password)
            issued_at = Time.now.to_i
            payload = {
              license_id: "SV-#{SecureRandom.hex(6).upcase}",
              product_id: PRODUCT_ID,
              device_id: normalized_device_id,
              features: feature_list,
              customer_name: customer.to_s.strip,
              license_type: 'manual_offline',
              issued_at: issued_at,
              offline_until: issued_at + (duration_days * SECONDS_PER_DAY)
            }
            token = sign_payload(payload, private_key)
            File.binwrite(File.expand_path(output_path), token)

            puts "Issued #{payload[:license_id]} through #{Time.at(payload[:offline_until]).getlocal}."
            puts "Token: #{File.expand_path(output_path)}"
            0
          end

          def sign_payload(payload, private_key)
            encoded_payload = encode(JSON.generate(payload))
            signature = private_key.sign(OpenSSL::Digest::SHA256.new, encoded_payload)
            "#{encoded_payload}.#{encode(signature)}"
          end

          def encode(value)
            Base64.urlsafe_encode64(value).delete('=')
          end

          def normalize_device_id!(device_id)
            raw_value = device_id.to_s.strip
            contiguous_match = raw_value.match(/(?<![0-9a-fA-F])([0-9a-fA-F]{64})(?![0-9a-fA-F])/)
            return contiguous_match[1].downcase if contiguous_match

            compact_value = raw_value.gsub(/[\s-]/, '')
            return compact_value.downcase if compact_value.match?(/\A[0-9a-fA-F]{64}\z/)

            hexadecimal_count = raw_value.scan(/[0-9a-fA-F]/).length
            detail = if hexadecimal_count == 24
                       'The value looks like the shortened 24-character display code.'
                     else
                       "Received #{raw_value.length} characters (#{hexadecimal_count} hexadecimal)."
                     end
            raise ArgumentError,
                  "Device ID must contain the full 64-character hexadecimal value shown in License Manager. #{detail}"
          end

          def reject_plugin_directory!(directory)
            plugin_directory = File.expand_path('../../..', __dir__)
            normalized = directory.downcase
            plugin = plugin_directory.downcase
            return unless normalized == plugin || normalized.start_with?("#{plugin}#{File::SEPARATOR}")

            raise ArgumentError, 'Store private keys outside sonvu_cnc_plugins so they cannot enter an RBZ.'
          end

          def read_new_password
            first = read_password('New private-key password: ')
            second = read_password('Confirm password: ')
            raise ArgumentError, 'Passwords do not match.' unless first == second
            raise ArgumentError, 'Use a password with at least 12 characters.' if first.length < 12

            first
          end

          def read_password(prompt)
            $stdout.print(prompt)
            value = $stdin.noecho(&:gets).to_s.chomp
            $stdout.puts
            value
          end

          def usage
            <<~TEXT
              Usage:
                ruby issuer.rb init KEY_DIRECTORY
                ruby issuer.rb issue PRIVATE_KEY DEVICE_ID OUTPUT_TOKEN [CUSTOMER] [DAYS] [FEATURES]

              FEATURES is a comma-separated list; default: dogbone_joinery,furniture_builder
            TEXT
          end

          exit(run(ARGV)) if __FILE__ == $PROGRAM_NAME
        end
      end
    end
  end
end
