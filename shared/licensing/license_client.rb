# frozen_string_literal: true

require 'json'
require 'net/http'
require 'timeout'
require 'uri'

module SonVu
  module CNCPlugins
    module Licensing
      module LicenseClient
        class Error < StandardError; end

        module_function

        def configured?
          uri = server_uri
          uri && uri.is_a?(URI::HTTPS) && !Config::PUBLIC_KEY_PEM.to_s.strip.empty?
        rescue URI::InvalidURIError
          false
        end

        def activate(license_key)
          post_json('activate', common_payload.merge(license_key: license_key.to_s.strip))
        end

        def refresh(token)
          post_json('refresh', common_payload.merge(token: token.to_s))
        end

        def deactivate(token)
          post_json('deactivate', common_payload.merge(token: token.to_s))
        end

        def common_payload
          payload = {
            product_id: Config::PRODUCT_ID,
            device_id: DeviceIdentity.id,
            plugin_version: CNCPlugins::VERSION
          }
          payload[:sketchup_version] = Sketchup.version.to_s if Sketchup.respond_to?(:version)
          payload
        end

        def post_json(path, payload)
          raise Error, 'Máy chủ giấy phép chưa được cấu hình.' unless configured?

          uri = endpoint_uri(path)
          request = Net::HTTP::Post.new(uri.request_uri)
          request['Accept'] = 'application/json'
          request['Content-Type'] = 'application/json; charset=utf-8'
          request.body = JSON.generate(payload)

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: true,
            open_timeout: Config::CONNECT_TIMEOUT_SECONDS,
            read_timeout: Config::READ_TIMEOUT_SECONDS
          ) { |http| http.request(request) }

          body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
          unless response.is_a?(Net::HTTPSuccess)
            raise Error, body['message'].to_s.empty? ? "Máy chủ trả về lỗi HTTP #{response.code}." : body['message']
          end

          body
        rescue JSON::ParserError
          raise Error, 'Máy chủ giấy phép trả về dữ liệu không hợp lệ.'
        rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
          raise Error, "Không kết nối được máy chủ giấy phép: #{e.message}"
        end

        def server_uri
          value = Config::SERVER_URL.to_s.strip
          return nil if value.empty?

          URI.parse(value)
        end

        def endpoint_uri(path)
          base = server_uri.to_s.sub(%r{/+\z}, '')
          URI.parse("#{base}/#{path}")
        end
      end
    end
  end
end
