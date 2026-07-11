# frozen_string_literal: true

require_relative 'github_api/workflow'

begin
  GitHubAPI::Workflow.run!
rescue GitHubAPI::ConfigurationError, GitHubAPI::ResponseError => e
  warn e.message
  warn e.body unless e.body.to_s.empty?
  exit 1
end
