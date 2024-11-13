# lib/pr_lister/configuration.rb
require 'yaml'
require_relative 'feature_flags'

module PRLister
  class Configuration
    DEFAULT_CONFIG = {
      'include_drafts' => false,
      'verbose' => false,
      'output_file' => nil,
      'retry_count' => 3,
      'retry_delay' => 2,
      'log_level' => 'info'
    }

    # AI review config only loaded if feature is enabled
    AI_REVIEW_CONFIG = {
      'enabled' => false,
      'provider' => 'openai',
      'concurrent_reviews' => 3,
      'openai' => {
        'model' => 'gpt-4-turbo-preview'
      }
    }

    attr_reader :token, :repos, :developers, :include_drafts,
                :verbose, :output_file, :retry_count, :retry_delay,
                :log_level, :ai_review, :parallel_threads

    def initialize(config_path = 'config.yml')
      @config = DEFAULT_CONFIG.merge(load_yaml(config_path))
      setup_configuration
    end

    private

    def load_yaml(config_path)
      YAML.load_file(config_path)
    rescue Errno::ENOENT
      raise ConfigurationError, "Configuration file not found: #{config_path}"
    end

    def setup_configuration
      @token = @config['token'] || ENV['GITHUB_TOKEN']
      @repos = @config['repos'] || []
      @developers = @config['developers'] || []
      @include_drafts = @config['include_drafts']
      @verbose = @config['verbose']
      @output_file = @config['output_file']
      @retry_count = @config['retry_count']
      @retry_delay = @config['retry_delay']
      @log_level = @config['log_level']
      @parallel_threads = FeatureFlags.parallel_processing_enabled? ? (@config['parallel_threads'] || 4) : 1

      setup_ai_review if FeatureFlags.ai_review_enabled?

      validate_configuration
    end

    def setup_ai_review
      ai_config = @config['ai_review'] || {}
      @ai_review = OpenStruct.new(AI_REVIEW_CONFIG.merge(ai_config))
    end

    def validate_configuration
      raise ConfigurationError, "GitHub token not found" unless @token
      raise ConfigurationError, "No repositories specified" if @repos.empty?
      raise ConfigurationError, "No developers specified" if @developers.empty?
    end
  end
end
