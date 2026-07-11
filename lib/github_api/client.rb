# frozen_string_literal: true

require_relative 'errors'
require_relative 'authenticator'
require_relative 'http_helpers'

module GitHubAPI
  class Client
    include HttpHelpers

    def initialize(repository:, authenticator:, api_base: Authenticator::DEFAULT_API_BASE)
      raise ConfigurationError, 'GitHub repository is required' if repository.to_s.empty?

      @repository = repository
      @authenticator = authenticator
      @api_base = normalize_base(api_base)
      @installation_token = nil
    end

    def create_commit_comment(sha:, body:)
      raise ConfigurationError, 'Git commit SHA is required' if sha.to_s.empty?
      raise ConfigurationError, 'GitHub commit comment body is required' if body.to_s.empty?

      request_json(
        method: :post,
        path: "/repos/sage/#{@repository}/commits/#{sha}/comments",
        body: { body: body }
      )
    end

    private

    def normalize_base(api_base)
      api_base.to_s.sub(%r{/*\z}, '')
    end

    def apply_auth_headers(request)
      request['Authorization'] = "Bearer #{installation_token}"
    end

    def installation_token
      @installation_token ||= @authenticator.installation_token(repository: @repository)
    end
  end
end
