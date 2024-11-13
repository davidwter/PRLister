# lib/pr_lister/pull_request.rb
module PRLister
  class PullRequest
    attr_reader :repo, :data, :review_data

    def initialize(repo, pr_data)
      @repo = repo
      @data = pr_data
      @review_data = nil
    end

    def description
      @data[:body]
    end


    def number
      @data[:number]
    end

    def title
      @data[:title]
    end

    def user
      @data[:user][:login]
    end

    def created_at
      @data[:created_at]
    end

    def html_url
      @data[:html_url]
    end

    def draft?
      @data[:draft]
    end

    def days_open
      ((Time.now - created_at) / (60 * 60 * 24)).round
    end

    def load_review_data(reviews, comments, issue_comments)
      @review_data = {
        reviews: reviews || [],
        comments: (comments || []) + (issue_comments || [])
      }
    end
  end
end