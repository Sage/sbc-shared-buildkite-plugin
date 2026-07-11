# frozen_string_literal: true

require 'json'
require 'net/http'
require_relative 'errors'

module GitHubAPI
  class Response
    def self.parse!(raw_response)
      body = raw_response.body.to_s

      unless raw_response.is_a?(Net::HTTPSuccess)
        raise ResponseError.new(
          "GitHub API request failed with #{raw_response.code}",
          status: raw_response.code.to_i,
          body: body
        )
      end

      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise ResponseError.new(
        "GitHub API returned invalid JSON: #{e.message}",
        status: raw_response.code.to_i,
        body: body
      )
    end
  end
end
