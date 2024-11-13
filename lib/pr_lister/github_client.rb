# lib/pr_lister/github_client.rb
require 'octokit'
require 'logger'

module PRLister
  class GithubClient
    def initialize(config)
      @config = config
      @client = Octokit::Client.new(access_token: config.token)
      @client.auto_paginate = true
      @logger = Logger.new(STDOUT)
      @logger.level = Logger.const_get(@config.log_level.upcase)
      verify_access!
    end

    def fetch_repository_prs(repo_string)
      repo = GithubRepo.new(repo_string)
      @logger.debug "Fetching PRs from #{repo}"

      prs = fetch_open_prs(repo)
      prs = filter_prs(prs, repo)

      prs.map do |pr_data|
        pr = PullRequest.new(repo, pr_data)
        load_review_data(pr)
        pr
      end
    end

    private

    def verify_access!
      test_repo = GithubRepo.new(@config.repos.first)
      @client.repository(test_repo.full_name)
      @logger.debug "Successfully authenticated and accessed #{test_repo}"
    rescue Octokit::Unauthorized
      raise APIError, "Token unauthorized. Please check token permissions"
    rescue Octokit::NotFound
      raise APIError, "Repository #{test_repo} not found or token lacks access"
    end

    def fetch_open_prs(repo)
      with_retry do
        @client.pull_requests(repo.full_name, state: 'open')
      end
    end

    def filter_prs(prs, repo)
      filtered = prs
      filtered = filtered.reject { |pr| pr[:draft] } unless @config.include_drafts
      @logger.debug "Found #{filtered.size} non-draft PRs in #{repo}"

      filtered = filtered.select { |pr| @config.developers.include?(pr[:user][:login]) }
      @logger.debug "Found #{filtered.size} PRs from tracked developers in #{repo}"

      filtered
    end

    def load_review_data(pr)
      @logger.debug "Loading review data for #{pr.repo.full_name}##{pr.number}"

      begin
        reviews = fetch_reviews(pr)
        @logger.debug "Fetched #{reviews.size} reviews"

        comments = fetch_comments(pr)
        @logger.debug "Fetched #{comments.size} PR comments"

        issue_comments = fetch_issue_comments(pr)
        @logger.debug "Fetched #{issue_comments.size} issue comments"

        pr.load_review_data(reviews, comments, issue_comments)
        @logger.debug "Successfully loaded all review data"
      rescue => e
        @logger.error "Error fetching review data for #{pr.repo.full_name}##{pr.number}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        pr.load_review_data([], [], [])
      end
    end

    def fetch_reviews(pr)
      with_retry do
        @client.pull_request_reviews(pr.repo.full_name, pr.number)
      end
    end

    def fetch_comments(pr)
      with_retry do
        @client.pull_request_comments(pr.repo.full_name, pr.number)
      end
    end

    def fetch_issue_comments(pr)
      with_retry do
        @client.issue_comments(pr.repo.full_name, pr.number)
      end
    end

    def with_retry
      retries = 0
      begin
        yield
      rescue Octokit::Error => e
        retries += 1
        if retries <= @config.retry_count
          @logger.warn "API error: #{e.message}. Retry #{retries}/#{@config.retry_count}"
          sleep(@config.retry_delay * retries)
          retry
        else
          raise APIError, "GitHub API error after #{@config.retry_count} retries: #{e.message}"
        end
      end
    end
  end
end