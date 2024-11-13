# lib/pr_lister/ai_reviewer.rb
require 'parallel'
require 'base64'
require 'diffy'

module PRLister
  class AIReviewer
    class AIReviewError < PRLister::Error; end


    TEMPLATES = {
      'default' => <<~TEMPLATE,
      You are an expert code reviewer. Please review this Pull Request focusing on:
      1. Code correctness and potential bugs
      2. Security implications
      3. Performance considerations
      4. Best practices and coding standards
      5. Suggestions for improvement

      Files changed:
      {{files_changed}}

      Code changes:
      {{diff}}

      Please structure your review as follows:
      1. Summary (2-3 sentences)
      2. Key Observations
      3. Potential Issues
      4. Recommendations
      5. Code-specific comments (if any)
    TEMPLATE

      'ruby' => <<~TEMPLATE,
      You are reviewing a Ruby codebase. Focus on:
      1. Ruby idioms and best practices
      2. Performance implications
      3. Gem usage and compatibility
      4. Security considerations
      5. Test coverage

      {{standard_review_section}}
    TEMPLATE
    }.freeze

    def initialize(config)
      @config = config
      @clients = {}  # Lazy-loaded AI clients
      @logger = Logger.new(STDOUT)
      @logger.level = Logger.const_get(@config.log_level.upcase)
      verify_ai_configuration!

    end

    def review_pr(pr, selected_files = nil)
      return unless @config.ai_review&.enabled

      @logger.info "Starting AI review for PR ##{pr.number} in #{pr.repo}"

      begin
        files = fetch_changed_files(pr)
        files = filter_files(files, selected_files) if selected_files

        categorized_files = FileAnalyzer.categorize_files(files)
        templates = FileAnalyzer.determine_review_templates(files)

        reviews = generate_reviews_for_templates(pr, files, templates)
        combined_review = combine_reviews(reviews, categorized_files)

        post_review_comment(pr, combined_review)

        @logger.info "AI review completed for PR ##{pr.number}"
      rescue => e
        @logger.error "Error during AI review: #{e.message}"
        @logger.error e.backtrace.join("\n")
      end
    end

    def review_multiple_prs(prs, selected_files = nil)
      return unless @config.ai_review&.enabled

      concurrent = [@config.ai_review.concurrent_reviews || 3, prs.size].min

      Parallel.map(prs, in_threads: concurrent) do |pr|
        review_pr(pr, selected_files)
      end
    end

    private

    def verify_ai_configuration!
      case @config.ai_review.provider
      when 'openai'
        raise AIReviewError, "OpenAI API key not configured" unless @config.ai_review.openai.api_key
      when 'claude'
        raise AIReviewError, "Claude API key not configured" unless ENV['ANTHROPIC_API_KEY']
      else
        raise AIReviewError, "Unknown AI provider: #{@config.ai_review.provider}"
      end
    end


    def generate_reviews_for_templates(pr, files, templates)
      templates.map do |template_name|
        diff = fetch_pr_diff(pr, files)
        prompt = build_review_prompt(template_name, pr, diff, files)

        {
          template: template_name,
          review: generate_review(prompt)
        }
      end
    end

    def combine_reviews(reviews, categorized_files)
      sections = []

      # Add security warning if sensitive files are changed
      if categorized_files[:security_sensitive].any?
        sections << "⚠️ **Security-Sensitive Files Modified**\n" +
          "Please pay extra attention to these changes:\n" +
          categorized_files[:security_sensitive].map { |f| "- #{f.filename}" }.join("\n")
      end

      # Add main review
      reviews.each do |review|
        sections << "## #{review[:template].capitalize} Review\n\n#{review[:review]}"
      end

      sections.join("\n\n")
    end

    def get_ai_client(provider = nil)
      provider ||= @config.ai_review.provider
      @logger.debug "Using OpenAI API key: #{@config.ai_review.openai.api_key}"
      @clients[provider] ||= create_ai_client(provider)
    end

    def create_ai_client(provider)
      case provider
      when 'claude'
        require 'anthropic'
        Anthropic::Client.new(api_key: @config.ai_review.claude.api_key)
      when 'openai'
        require 'ruby-openai'
        OpenAI::Client.new(api_key: @config.ai_review.openai.api_key)
      else
        raise ConfigurationError, "Unknown AI provider: #{provider}"
      end
    end

    def fetch_pr_diff(pr, files = nil)
      client = Octokit::Client.new(access_token: @config.token)

      if files
        diffs = files.map do |file|
          content = client.get(file.contents_url).content
          decoded_content = Base64.decode64(content)
          "File: #{file.filename}\n#{decoded_content}"
        end
        diffs.join("\n\n")
      else
        diff = client.pull_request(pr.repo.full_name, pr.number, accept: 'application/vnd.github.v3.diff')
      end

      truncate_if_needed(diff)
    end

    def fetch_changed_files(pr)
      client = Octokit::Client.new(access_token: @config.token)
      client.pull_request_files(pr.repo.full_name, pr.number)
    end

    def filter_files(files, selected_files)
      return files unless selected_files
      files.select { |f| selected_files.include?(f.filename) }
    end

    def build_review_prompt(template_name, pr, diff, files)
      template = TEMPLATES[template_name] || TEMPLATES['default']

      # Replace standard review section if present
      if template.include?('{{standard_review_section}}')
        template = template.gsub('{{standard_review_section}}', @config.ai_review.templates['default'])
      end

      template
        .gsub('{{files_changed}}', format_files_list(files))
        .gsub('{{diff}}', diff)
        .gsub('{{pr_title}}', pr.title)
        .gsub('{{pr_description}}', pr.description || 'No description provided')
    end

    def format_files_list(files)
      files.map do |f|
        "#{f.filename} (#{f.status}, +#{f.additions}/-#{f.deletions})"
      end.join("\n")
    end

    def generate_review(prompt)
      case @config.ai_review.provider
      when 'claude'
        generate_claude_review(prompt)
      when 'openai'
        generate_openai_review(prompt)
      end
    end

    def generate_claude_review(prompt)
      response = get_ai_client('claude').messages.create(
        model: @config.ai_review.claude.model,
        max_tokens: 4096,
        messages: [{
                     role: 'user',
                     content: prompt
                   }],
        temperature: 0.7
      )
      response.content.first.text
    end

    def generate_openai_review(prompt)

      response = get_ai_client('openai').chat(
        parameters: {
          model: @config.ai_review.openai.model,
          messages: [{ role: 'user', content: prompt }],
          max_tokens: 4096,
          temperature: 0.7
        }
      )
      response.dig('choices', 0, 'message', 'content')
    end

    def post_review_comment(pr, review)
      client = Octokit::Client.new(access_token: @config.token)

      # Format review with metadata
      formatted_review = <<~REVIEW
        # 🤖 AI Code Review

        _Generated at #{Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")}_
        _Using #{@config.ai_review.provider} (#{provider_model})_

        #{review}

        ---
        This is an automated review. Please verify all suggestions before implementing.
      REVIEW

      client.create_pull_request_review(
        pr.repo.full_name,
        pr.number,
        event: 'COMMENT',
        body: formatted_review
      )
    end

    def provider_model
      case @config.ai_review.provider
      when 'claude'
        @config.ai_review.claude.model
      when 'openai'
        @config.ai_review.openai.model
      end
    end

    def truncate_if_needed(text, max_length = 12000)
      return "" if text.nil? # Return an empty string if text is nil

      if text.length > max_length
        text.slice(0, max_length) + "\n... (truncated for length)"
      else
        text
      end
    end
  end
end