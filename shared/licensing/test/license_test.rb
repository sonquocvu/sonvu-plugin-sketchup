# frozen_string_literal: true

require 'minitest/autorun'
require 'base64'
require 'json'
require 'openssl'

module Sketchup
  @preferences = {}

  class << self
    def read_default(section, key, default = nil)
      @preferences.fetch([section, key], default)
    end

    def write_default(section, key, value)
      @preferences[[section, key]] = value
    end

    def platform
      :platform_win
    end

    def reset_preferences
      @preferences = {}
    end
  end
end

module SonVu
  module CNCPlugins
    PLUGIN_ID = 'sonvu_cnc_plugins'
    VERSION = '0.2.0'
  end
end

require_relative '../../../constants'
require_relative '../config'
require_relative '../device_identity'
require_relative '../license_token'
require_relative '../manager'
require_relative '../tools/issuer'

module SonVu
  module CNCPlugins
    module Licensing
      class LicenseTest < Minitest::Test
        def setup
          Sketchup.reset_preferences
          @private_key = OpenSSL::PKey::RSA.new(2048)
          @public_key = @private_key.public_key.to_pem
          @now = 1_800_000_000
          @payload = {
            'license_id' => 'LIC-TEST-001',
            'product_id' => Config::PRODUCT_ID,
            'device_id' => 'device-123',
            'features' => [Config::FEATURE_DOGBONE_JOINERY],
            'issued_at' => @now - 60,
            'offline_until' => @now + 86_400,
            'license_type' => 'perpetual'
          }
        end

        def test_accepts_valid_signed_token
          result = verify(issue_token(@payload))

          assert result.valid?
          assert_equal :licensed, result.state
          assert_equal 'LIC-TEST-001', result.payload['license_id']
        end

        def test_rejects_tampered_payload
          token = issue_token(@payload)
          _encoded_payload, signature = token.split('.')
          tampered_payload = @payload.merge('offline_until' => @now + 10_000_000)
          tampered = "#{encode(JSON.generate(tampered_payload))}.#{signature}"
          result = verify(tampered)

          refute result.valid?
          assert_equal :invalid_signature, result.state
        end

        def test_rejects_token_for_another_device
          result = verify(issue_token(@payload.merge('device_id' => 'another-device')))

          refute result.valid?
          assert_equal :wrong_device, result.state
        end

        def test_rejects_missing_feature_entitlement
          result = verify(issue_token(@payload.merge('features' => ['future_module'])))

          refute result.valid?
          assert_equal :feature_missing, result.state
        end

        def test_rejects_expired_offline_lease
          result = verify(issue_token(@payload.merge('offline_until' => @now - 1)))

          refute result.valid?
          assert_equal :expired, result.state
        end

        def test_device_id_is_stable_and_hashed
          first_id = DeviceIdentity.id
          second_id = DeviceIdentity.id

          assert_equal first_id, second_id
          assert_match(/\A[0-9a-f]{64}\z/, first_id)
          refute_includes first_id, Socket.gethostname.downcase
        end

        def test_offline_issuer_creates_tokens_accepted_by_runtime_verifier
          token = Tools::Issuer.sign_payload(@payload, @private_key)

          assert verify(token).valid?
        end

        def test_issuer_normalizes_full_device_id_copied_with_label_or_hyphens
          device_id = '0123456789abcdef' * 4
          grouped = device_id.scan(/.{1,4}/).join('-')

          assert_equal device_id, Tools::Issuer.normalize_device_id!("Mã thiết bị: #{device_id}")
          assert_equal device_id, Tools::Issuer.normalize_device_id!(grouped)
        end

        def test_issuer_reports_short_device_code
          error = assert_raises(ArgumentError) do
            Tools::Issuer.normalize_device_id!('0123-4567-89AB-CDEF-0123-4567')
          end

          assert_includes error.message, 'shortened 24-character'
        end

        private

        def verify(token)
          LicenseToken.verify(
            token,
            public_key_pem: @public_key,
            device_id: 'device-123',
            product_id: Config::PRODUCT_ID,
            feature: Config::FEATURE_DOGBONE_JOINERY,
            now: @now
          )
        end

        def issue_token(payload)
          encoded_payload = encode(JSON.generate(payload))
          signature = @private_key.sign(OpenSSL::Digest::SHA256.new, encoded_payload)
          "#{encoded_payload}.#{encode(signature)}"
        end

        def encode(value)
          Base64.urlsafe_encode64(value).delete('=')
        end
      end
    end
  end
end
