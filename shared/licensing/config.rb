# frozen_string_literal: true

# Deployment configuration for SonVu licensing. Keep the production private
# signing key on the license server; only its public counterpart belongs here.

module SonVu
  module CNCPlugins
    module Licensing
      module Config
        PRODUCT_ID = CNCPlugins::PLUGIN_ID
        FEATURE_DOGBONE_JOINERY = 'dogbone_joinery'
        FEATURE_FURNITURE_BUILDER = 'furniture_builder'

        # Leave enforcement disabled during development. Before producing a
        # customer RBZ, configure HTTPS SERVER_URL, embed the RSA public key,
        # run the test suite, and change this value to true.
        ENFORCEMENT_ENABLED = true
        SERVER_URL = ''.freeze
        PUBLIC_KEY_PEM = (<<~PEM).freeze
          -----BEGIN PUBLIC KEY-----
          MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAj6p5p2dPYskMvS7zM8pI
          zyWFNCbWSx6BdTqNka+sq9K+uZ3OTOXPFxty56ymnVZlVtmg41p4YQd5s2y2046s
          fTD/pVH1RYJvca7U8VHhBfmGU2tErBQSKENiQrPvXEKsgQNmbY/7qmALtXYvft45
          kASO0ieEhRjWDNHnWJWKNi85/cyW7XK2LuCwKYWrHs+rdfjlNXdFtlvnpTpJVjQX
          J2XBzFyDCcE+eV/K8cqGLaOHhkUSleBGFknrbfMQQZTj158E4hvPr9B6XNDOGHjZ
          J4EJR95zBfnU24g1OyZNApV7k2I6Qh451RxHHN+RyIjra2bPBYLUuANMC3tAVlgD
          xO24hEZtyHQp7PP4PASr55A83/IxshkmM+rmeVMtg3Fs1ZLuGDig9P3j3SAThin6
          gz9nnffw+MSwxiSLQHXm7GmkvmsNwR4zyNDyenxjma3RCpfVNqCzfHD20Om8fgJX
          kQ38zKpFNlp5Iiomld9I6mDjmSLOWuCW0M9vLO/5uzAPAgMBAAE=
          -----END PUBLIC KEY-----
        PEM

        CONNECT_TIMEOUT_SECONDS = 4
        READ_TIMEOUT_SECONDS = 7
        TRIAL_DAYS = 14
        SECONDS_PER_DAY = 24 * 60 * 60
        REFRESH_BEFORE_EXPIRY_SECONDS = 3 * 24 * 60 * 60
        CLOCK_ROLLBACK_TOLERANCE_SECONDS = 6 * 60 * 60
        PREFERENCES_SECTION = CNCPlugins::PLUGIN_ID
        TOKEN_PREFERENCE = 'license_token'
        INSTALLATION_ID_PREFERENCE = 'installation_id'
        LAST_SEEN_AT_PREFERENCE = 'license_last_seen_at'
        TRIAL_STARTED_AT_PREFERENCE = 'trial_started_at'
      end
    end
  end
end
