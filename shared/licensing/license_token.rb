# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'

module SonVu
  module CNCPlugins
    module Licensing
      module LicenseToken
        Result = Struct.new(:valid, :state, :message, :payload, keyword_init: true) do
          def valid?
            valid == true
          end
        end

        module_function

        def verify(token, public_key_pem:, device_id:, product_id:, feature: nil, now: Time.now.to_i)
          encoded_payload, encoded_signature = split_token(token)
          payload_json = decode_base64url(encoded_payload)
          signature = decode_base64url(encoded_signature)
          public_key = OpenSSL::PKey::RSA.new(public_key_pem)
          verified = public_key.verify(OpenSSL::Digest::SHA256.new, signature, encoded_payload)
          return failure(:invalid_signature, 'Chữ ký giấy phép không hợp lệ.') unless verified

          payload = JSON.parse(payload_json)
          return failure(:invalid_payload, 'Dữ liệu giấy phép không hợp lệ.') unless payload.is_a?(Hash)

          validate_payload(payload, device_id: device_id, product_id: product_id, feature: feature, now: now)
        rescue JSON::ParserError, ArgumentError, OpenSSL::PKey::PKeyError, OpenSSL::PKey::RSAError
          failure(:invalid_token, 'Không đọc được giấy phép đã lưu.')
        end

        def validate_payload(payload, device_id:, product_id:, feature:, now:)
          return failure(:wrong_product, 'Giấy phép không dành cho sản phẩm này.', payload) unless payload['product_id'] == product_id
          return failure(:wrong_device, 'Giấy phép thuộc về một thiết bị khác.', payload) unless payload['device_id'] == device_id
          return failure(:not_yet_valid, 'Giấy phép chưa có hiệu lực.', payload) if future_time?(payload['not_before'], now)
          return failure(:invalid_clock, 'Thời gian phát hành giấy phép không hợp lệ.', payload) if future_time?(payload['issued_at'], now + 300)

          expiry = integer_time(payload['offline_until'] || payload['expires_at'])
          return failure(:invalid_payload, 'Giấy phép thiếu thời hạn sử dụng ngoại tuyến.', payload) unless expiry
          return failure(:expired, 'Giấy phép ngoại tuyến đã hết hạn.', payload) if now > expiry

          if feature && !feature_allowed?(payload, feature)
            return failure(:feature_missing, 'Giấy phép không bao gồm tính năng này.', payload)
          end

          Result.new(valid: true, state: :licensed, message: 'Giấy phép hợp lệ.', payload: payload)
        end

        def feature_allowed?(payload, feature)
          features = Array(payload['features']).map(&:to_s)
          features.include?('*') || features.include?(feature.to_s)
        end

        def expires_at(payload)
          integer_time(payload && (payload['offline_until'] || payload['expires_at']))
        end

        def split_token(token)
          parts = token.to_s.strip.split('.', -1)
          raise ArgumentError unless parts.length == 2 && parts.none?(&:empty?)

          parts
        end

        def decode_base64url(value)
          padding = '=' * ((4 - (value.length % 4)) % 4)
          Base64.urlsafe_decode64(value + padding)
        end

        def integer_time(value)
          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end

        def future_time?(value, comparison_time)
          timestamp = integer_time(value)
          timestamp && timestamp > comparison_time
        end

        def failure(state, message, payload = nil)
          Result.new(valid: false, state: state, message: message, payload: payload)
        end
      end
    end
  end
end
