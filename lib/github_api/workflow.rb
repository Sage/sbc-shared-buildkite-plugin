# frozen_string_literal: true

require 'json'
require_relative 'client'
require_relative 'authenticator'
require_relative 'resources'

module GitHubAPI
  class Workflow
    def self.run!(env: ENV, stdout: $stdout)
      new(env: env, stdout: stdout).run!
    end

    def initialize(env:, stdout:)
      @env = env
      @stdout = stdout
    end

    def run!
      action = required_value('GITHUB_ACTION')

      case action
      when 'create_commit_comment'
        create_commit_comment(build_client)
      else
        raise ConfigurationError, "Unknown GitHub action: #{action}"
      end
    end

    private

    def build_client
      api_base = Authenticator::DEFAULT_API_BASE

      authenticator = Authenticator.new(
        app_id: required_value('GITHUB_APP_ID'),
        private_key: private_key,
        api_base: api_base
      )

      Client.new(
        repository: required_value('GITHUB_REPOSITORY'),
        authenticator: authenticator,
        api_base: api_base
      )
    end

    def create_commit_comment(client)
      sha = @env['GITHUB_SHA']
      body = required_value('COMMENT_MESSAGE')

      response = Resources::CommitComments.new(client).create(sha: sha, body: body)
      @stdout.puts JSON.pretty_generate(response)
      response
    end

    def private_key
      required_value('GITHUB_APP_PRIVATE_KEY')
    end

    def required_value(name)
      value = @env[name]
      return value unless value.nil? || value.empty?

      raise ConfigurationError, "Missing required GitHub workflow env var: #{name}"
    end
  end
end
