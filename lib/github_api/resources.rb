# frozen_string_literal: true

module GitHubAPI
  module Resources
    class CommitComments
      def initialize(client)
        @client = client
      end

      def create(sha:, body:)
        @client.create_commit_comment(sha: sha, body: body)
      end
    end
  end
end
