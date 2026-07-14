# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module Licensing
      module Manager
        module_function

        def require_feature(feature)
          return true unless Config::ENFORCEMENT_ENABLED

          result = status(feature)
          result = refresh_status(feature) if refresh_needed?(result)
          return true if result.valid?

          Dialog.show(required_feature: feature, notice: result.message)
          false
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không kiểm tra được giấy phép:\n#{e.message}")
          false
        end

        def status(feature = nil, now: Time.now.to_i)
          return setup_result unless Config::ENFORCEMENT_ENABLED
          return configuration_result unless public_key_configured?
          return clock_result if clock_rolled_back?(now)

          token = stored_token
          return missing_result if token.empty?

          result = verify(token, feature, now)
          write_last_seen(now) if result.valid?
          result
        end

        def activate(value)
          candidate = value.to_s.strip
          raise LicenseClient::Error, 'Vui lòng nhập mã giấy phép.' if candidate.empty?

          token = token_format?(candidate) ? candidate : activate_online(candidate)
          install_token(token)
        end

        def install_token(token)
          raise LicenseClient::Error, 'Khóa công khai chưa được cấu hình.' unless public_key_configured?

          result = verify(token, nil, Time.now.to_i)
          raise LicenseClient::Error, result.message unless result.valid?

          write_token(token)
          write_last_seen(Time.now.to_i)
          result
        end

        def refresh(feature = nil)
          raise LicenseClient::Error, 'Không có giấy phép để làm mới.' if stored_token.empty?

          response = LicenseClient.refresh(stored_token)
          token = response['token'].to_s
          raise LicenseClient::Error, 'Máy chủ không trả về token giấy phép.' if token.empty?

          result = install_token(token)
          feature_result = verify(token, feature, Time.now.to_i)
          raise LicenseClient::Error, feature_result.message unless feature_result.valid?

          result
        end

        def deactivate
          token = stored_token
          return true if token.empty?

          LicenseClient.deactivate(token) if LicenseClient.configured? && online_license?(token)
          clear_local_license
          true
        end

        def clear_local_license
          write_token('')
          Sketchup.write_default(
            Config::PREFERENCES_SECTION,
            Config::LAST_SEEN_AT_PREFERENCE,
            0
          )
        end

        def view_model(feature = nil, notice: nil)
          result = status(feature)
          payload = result.payload || {}
          {
            licensed: result.valid?,
            state: result.state.to_s,
            message: notice.to_s.empty? ? result.message : notice,
            customer: payload['customer_name'] || payload['customer'] || '',
            license_id: payload['license_id'].to_s,
            license_type: payload['license_type'].to_s,
            expires_at: formatted_expiry(payload),
            device_id: DeviceIdentity.id,
            device_short_id: DeviceIdentity.short_id,
            enforcement_enabled: Config::ENFORCEMENT_ENABLED,
            server_configured: LicenseClient.configured?,
            public_key_configured: public_key_configured?
          }
        end

        def stored_token
          Sketchup.read_default(
            Config::PREFERENCES_SECTION,
            Config::TOKEN_PREFERENCE,
            ''
          ).to_s.strip
        end

        def public_key_configured?
          !Config::PUBLIC_KEY_PEM.to_s.strip.empty?
        end

        def verify(token, feature, now)
          LicenseToken.verify(
            token,
            public_key_pem: Config::PUBLIC_KEY_PEM,
            device_id: DeviceIdentity.id,
            product_id: Config::PRODUCT_ID,
            feature: feature,
            now: now
          )
        end

        def activate_online(license_key)
          response = LicenseClient.activate(license_key)
          token = response['token'].to_s
          raise LicenseClient::Error, 'Máy chủ không trả về token giấy phép.' if token.empty?

          token
        end

        def refresh_status(feature)
          refresh(feature)
        rescue LicenseClient::Error
          status(feature)
        end

        def refresh_needed?(result)
          return false unless LicenseClient.configured? && !stored_token.empty?
          return true if result.state == :expired
          return false unless result.valid?

          expiry = LicenseToken.expires_at(result.payload)
          expiry && (expiry - Time.now.to_i) <= Config::REFRESH_BEFORE_EXPIRY_SECONDS
        end

        def clock_rolled_back?(now)
          last_seen = Sketchup.read_default(
            Config::PREFERENCES_SECTION,
            Config::LAST_SEEN_AT_PREFERENCE,
            0
          ).to_i
          last_seen.positive? && now < (last_seen - Config::CLOCK_ROLLBACK_TOLERANCE_SECONDS)
        end

        def write_token(token)
          Sketchup.write_default(
            Config::PREFERENCES_SECTION,
            Config::TOKEN_PREFERENCE,
            token.to_s
          )
        end

        def write_last_seen(timestamp)
          Sketchup.write_default(
            Config::PREFERENCES_SECTION,
            Config::LAST_SEEN_AT_PREFERENCE,
            timestamp.to_i
          )
        end

        def token_format?(value)
          value.count('.') == 1 && value.length > 100
        end

        def online_license?(token)
          result = verify(token, nil, Time.now.to_i)
          result.payload && result.payload['license_type'] != 'manual_offline'
        end

        def formatted_expiry(payload)
          timestamp = LicenseToken.expires_at(payload)
          timestamp ? Time.at(timestamp).getlocal.strftime('%d/%m/%Y %H:%M') : ''
        end

        def setup_result
          LicenseToken::Result.new(
            valid: true,
            state: :setup,
            message: 'Chế độ phát triển: kiểm tra giấy phép chưa được bật.',
            payload: nil
          )
        end

        def configuration_result
          LicenseToken::Result.new(
            valid: false,
            state: :not_configured,
            message: 'Hệ thống giấy phép chưa được cấu hình đầy đủ.',
            payload: nil
          )
        end

        def missing_result
          LicenseToken::Result.new(
            valid: false,
            state: :missing,
            message: 'Thiết bị này chưa được kích hoạt.',
            payload: nil
          )
        end

        def clock_result
          LicenseToken::Result.new(
            valid: false,
            state: :clock_rollback,
            message: 'Đồng hồ hệ thống đã lùi bất thường. Hãy chỉnh lại ngày giờ rồi thử lại.',
            payload: nil
          )
        end
      end
    end
  end
end
