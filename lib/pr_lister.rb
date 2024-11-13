# lib/pr_lister.rb
require 'octokit'
require 'yaml'
require 'parallel'
require 'colorize'
require 'logger'
require 'ostruct'  # Added OpenStruct require

module PRLister
  VERSION = "1.0.0"

  class Runner
    def initialize(config_path = 'config.yml')
      @config = load_config(config_path)
      @logger = setup_logger
      @client = setup_client

      @logger.debug "Watching developers: #{@config['developers'].join(', ')}"
      @logger.debug "Watching repositories: #{@config['repos'].join(', ')}"
    end

    def run
      puts "\nPR Lister v#{VERSION}"
      puts "Monitoring repositories:".cyan
      @config['repos'].each { |repo| puts "  - #{repo}" }

      puts "\nMonitoring developers:".cyan
      @config['developers'].each { |dev| puts "  - #{dev}" }

      puts "\nFetching pull requests...".cyan
      all_prs = fetch_all_pull_requests

      if all_prs.empty?
        puts "\nNo open pull requests found for the specified developers in the specified repositories.".yellow
        exit 0
      end

      display_summary(all_prs)
      display_pull_requests(all_prs)
      save_to_file(all_prs) if @config['output_file']
    end

    private

    def load_config(config_path)
      begin
        config = YAML.load_file(config_path)
        validate_config(config)
        config
      rescue Errno::ENOENT
        puts "Error: Configuration file not found at #{config_path}".red
        exit 1
      rescue Psych::SyntaxError
        puts "Error: Invalid YAML syntax in configuration file".red
        exit 1
      end
    end

    def validate_config(config)
      required_keys = ['token', 'repos', 'developers']
      missing_keys = required_keys - config.keys

      unless missing_keys.empty?
        puts "Error: Missing required configuration keys: #{missing_keys.join(', ')}".red
        exit 1
      end

      if config['repos'].empty?
        puts "Error: No repositories specified in configuration".red
        exit 1
      end

      if config['developers'].empty?
        puts "Error: No developers specified in configuration".red
        exit 1
      end
    end

    def setup_logger
      logger = Logger.new(STDOUT)
      logger.level = Logger.const_get(@config.fetch('log_level', 'warn').upcase)
      logger.formatter = proc { |severity, _, _, msg| "\n#{severity}: #{msg}\n" }
      logger
    end

    def setup_client
      Octokit::Client.new(
        access_token: @config['token'],
        auto_paginate: true,
        retry_limit: @config['retry_count'] || 3,
        retry_wait: @config['retry_delay'] || 2
      )
    rescue Octokit::Unauthorized
      puts "Error: Invalid GitHub token".red
      exit 1
    end

    def fetch_all_pull_requests
      thread_count = @config['parallel_threads'] || 4
      @logger.info "Fetching PRs using #{thread_count} threads"

      Parallel.map(@config['repos'], in_threads: thread_count) do |repo|
        next unless @config['repos'].include?(repo) # Extra safety check
        fetch_repository_prs(repo)
      end.flatten.compact
    rescue Parallel::DeadWorker => e
      @logger.error "Error in parallel processing: #{e.message}"
      exit 1
    end

    def fetch_repository_prs(repo)
      @logger.debug "Fetching PRs for #{repo}"
      prs = @client.pull_requests(repo, state: 'open')

      # Strict filtering based on configuration
      filtered_prs = prs.select do |pr|
        next false unless @config['developers'].include?(pr.user.login)
        next false if pr.draft? && !@config['include_drafts']
        true
      end

      @logger.debug "Found #{filtered_prs.size} matching PRs in #{repo}"
      filtered_prs.map { |pr| enrich_pr_data(pr, repo) }
    rescue Octokit::NotFound
      @logger.error "Repository not found: #{repo}"
      []
    rescue Octokit::Error => e
      @logger.error "Error fetching PRs for #{repo}: #{e.message}"
      []
    end

    def enrich_pr_data(pr, repo)
      OpenStruct.new(
        repo: repo,
        number: pr.number,
        title: pr.title,
        user: pr.user.login,
        created_at: pr.created_at,
        html_url: pr.html_url,
        draft: pr.draft?,
        days_old: ((Time.now - pr.created_at) / (60 * 60 * 24)).round
      )
    end

    def display_summary(prs)
      puts "\nSummary:".bold
      total_prs = prs.size
      puts "Found #{total_prs} open pull request#{'s' if total_prs != 1} from monitored developers".cyan

      puts "\nPRs by Repository:".bold
      @config['repos'].each do |repo|
        repo_prs = prs.select { |pr| pr.repo == repo }
        if repo_prs.any?
          puts "  #{repo}: #{repo_prs.size} PR#{'s' if repo_prs.size != 1}".cyan
        end
      end

      puts "\nPRs by Developer:".bold
      @config['developers'].each do |dev|
        dev_prs = prs.select { |pr| pr.user == dev }
        if dev_prs.any?
          puts "  #{dev}: #{dev_prs.size} PR#{'s' if dev_prs.size != 1}".cyan
        end
      end

      old_prs = prs.select { |pr| pr.days_old > 30 }
      if old_prs.any?
        puts "\nPRs older than 30 days:".yellow.bold
        old_prs.each do |pr|
          puts "  #{pr.repo}##{pr.number} (#{pr.days_old} days old)".yellow
        end
      end

      puts "\n" + "-" * 80 + "\n"
    end

    def display_pull_requests(prs)
      puts "Pull Requests:".bold

      prs.sort_by(&:days_old).reverse.each do |pr|
        puts format_pr(pr)
      end
    end

    def format_pr(pr)
      [
        "#{pr.repo}".cyan,
        "##{pr.number}".blue,
        pr.title.white,
        "by #{pr.user}".green,
        format_age(pr.days_old),
        pr.html_url.underline
      ].join(" | ")
    end

    def format_age(days)
      color = case days
              when 0..7 then :green
              when 8..30 then :yellow
              else :red
              end

      "(#{days} days old)".colorize(color)
    end

    def save_to_file(prs)
      File.open(@config['output_file'], 'w') do |file|
        file.puts "PR Lister Report - Generated at #{Time.now}"
        file.puts "\nMonitored Repositories:"
        @config['repos'].each { |repo| file.puts "  - #{repo}" }

        file.puts "\nMonitored Developers:"
        @config['developers'].each { |dev| file.puts "  - #{dev}" }

        file.puts "\nPull Requests:"
        prs.sort_by(&:days_old).reverse.each do |pr|
          file.puts [
                      pr.repo,
                      "##{pr.number}",
                      pr.title,
                      "by #{pr.user}",
                      "(#{pr.days_old} days old)",
                      pr.html_url
                    ].join(" | ")
        end
      end
      puts "\nReport saved to #{@config['output_file']}".green
    end
  end
end