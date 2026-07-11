# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'
require_relative 'errors'
require_relative 'http_helpers'

module GitHubAPI
  class Authenticator
    include HttpHelpers

    DEFAULT_API_BASE = 'https://api.github.com'

    def initialize(app_id:, private_key:, api_base: DEFAULT_API_BASE)
      raise ConfigurationError, 'GitHub App ID is required' if app_id.to_s.empty?
      raise ConfigurationError, 'GitHub App private key is required' if private_key.to_s.empty?

      @app_id = app_id.to_s
      @private_key = OpenSSL::PKey::RSA.new(private_key)
      @api_base = normalize_base(api_base)
    end

    def installation_token(repository:)
      installation_id = repository_installation_id(repository: repository)
      response = request_json(
        method: :post,
        path: "/app/installations/#{installation_id}/access_tokens",
        body: {}
      )

      response.fetch('token')
    end

    def repository_installation_id(repository:)
      response = request_json(
        method: :get,
        path: "/repos/sage/#{repository}/installation"
      )

      response.fetch('id')
    end

    private

    def apply_auth_headers(request)
      request['Authorization'] = "Bearer #{jwt}"
    end

    def jwt
      header = { alg: 'RS256', typ: 'JWT' }
      now = Time.now.to_i
      payload = { iat: now - 60, exp: now + 540, iss: @app_id }
      signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join(".")
      signature = @private_key.sign(OpenSSL::Digest.new('SHA256'), signing_input)

      "#{signing_input}.#{base64url(signature)}"
    end

    def base64url(value)
      Base64.urlsafe_encode64(value).delete("=")
    end

    def normalize_base(api_base)
      api_base.to_s.sub(%r{/*\z}, '')
    end
  end
end
