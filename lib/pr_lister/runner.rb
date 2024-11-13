# lib/pr_lister/runner.rb
require_relative 'feature_flags'

module PRLister
  class Runner
    def initialize(config_path = 'config.yml')
      @config = Configuration.new(config_path)
      @client = GithubClient.new(@config)
      @reporter = Reporter.new(@config)
    end

    def run
      prs = fetch_all_pull_requests

      if FeatureFlags.ai_review_enabled? && @config.ai_review&.enabled
        process_ai_reviews(prs)
      end

      @reporter.generate_report(prs)
    end

    private

    def fetch_all_pull_requests
      if FeatureFlags.parallel_processing_enabled?
        fetch_in_parallel
      else
        fetch_sequentially
      end
    end

    def fetch_in_parallel
      require 'parallel'
      Parallel.map(@config.repos, in_threads: @config.parallel_threads) do |repo|
        fetch_repo_prs(repo)
      end.flatten
    end

    def fetch_sequentially
      @config.repos.map do |repo|
        fetch_repo_prs(repo)
      end.flatten
    end

    def process_ai_reviews(prs)
      reviewer = AIReviewer.new(@config)
      selected_prs = select_prs_for_review(prs)

      if selected_prs.any?
        if @config.ai_review.concurrent_reviews && @config.ai_review.concurrent_reviews > 1
          reviewer.review_multiple_prs(selected_prs)
        else
          selected_prs.each { |pr| reviewer.review_pr(pr) }
        end
      end
    end
  end
end
