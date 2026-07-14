# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'socket'

module SonVu
  module CNCPlugins
    module Licensing
      module DeviceIdentity
        module_function

        def id
          Digest::SHA256.hexdigest(identity_components.join('|'))
        end

        def short_id
          value = id.upcase
          value.scan(/.{1,4}/).first(6).join('-')
        end

        def identity_components
          [
            Config::PRODUCT_ID,
            platform_name,
            stable_machine_value,
            installation_id
          ]
        end

        def installation_id
          stored = Sketchup.read_default(
            Config::PREFERENCES_SECTION,
            Config::INSTALLATION_ID_PREFERENCE,
            ''
          ).to_s.strip
          return stored unless stored.empty?

          generated = SecureRandom.uuid
          Sketchup.write_default(
            Config::PREFERENCES_SECTION,
            Config::INSTALLATION_ID_PREFERENCE,
            generated
          )
          generated
        end

        def platform_name
          return Sketchup.platform.to_s if Sketchup.respond_to?(:platform)

          RUBY_PLATFORM
        end

        def stable_machine_value
          windows_machine_guid || Socket.gethostname.to_s.downcase
        rescue StandardError
          'unknown-host'
        end

        def windows_machine_guid
          return nil unless RUBY_PLATFORM.match?(/mswin|mingw/i)

          require 'win32/registry'
          access = Win32::Registry::KEY_READ
          access |= 0x0100 if defined?(Win32::Registry::KEY_WOW64_64KEY)
          Win32::Registry::HKEY_LOCAL_MACHINE.open(
            'SOFTWARE\\Microsoft\\Cryptography',
            access
          ) { |registry| registry['MachineGuid'].to_s.downcase }
        rescue LoadError, StandardError
          nil
        end
      end
    end
  end
end
