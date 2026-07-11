# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative 'response'

module GitHubAPI
  module HttpHelpers
    private

    def request_json(method:, path:, body: nil)
      raw_response = perform_request(method: method, path: path, body: body)
      Response.parse!(raw_response)
    end

    def perform_request(method:, path:, body:)
      uri = URI("#{@api_base}#{path}")
      request_class = Net::HTTP.const_get(method.to_s.capitalize)
      request = request_class.new(uri)
      request['Accept'] = 'application/vnd.github+json'
      request['User-Agent'] = 'sbc-shared-buildkite-plugin'
      request['Content-Type'] = 'application/json'
      apply_auth_headers(request)
      request.body = JSON.generate(body) if body

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end
    end
  end
end
