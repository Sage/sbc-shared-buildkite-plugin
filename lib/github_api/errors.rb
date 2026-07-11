# frozen_string_literal: true

module GitHubAPI
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class ResponseError < Error
    attr_reader :status, :body

    def initialize(message, status:, body:)
      super(message)
      @status = status
      @body = body
    end
  end
end
