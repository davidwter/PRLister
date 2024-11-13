# lib/pr_lister/ai_review_formatter.rb
require 'diffy'

module PRLister
  # AIReviewFormatter handles the formatting of AI-generated code review suggestions
  # and diff comparisons for better readability in GitHub comments
  class AIReviewFormatter
    class << self
      # Formats a code suggestion by generating a diff between original and suggested code
      # @param original [String] The original code
      # @param suggestion [String] The suggested code changes
      # @return [String] Formatted diff in Markdown-compatible format
      def format_code_suggestion(original, suggestion)
        <<~SUGGESTION
          ```diff
          #{format_diff(original, suggestion)}
          ```
        SUGGESTION
      end

      # Formats multiple suggestions into a single review comment
      # @param suggestions [Array<Hash>] Array of suggestion hashes containing :original and :suggestion keys
      # @return [String] Combined formatted suggestions
      def format_multiple_suggestions(suggestions)
        suggestions.map do |suggestion|
          format_code_suggestion(suggestion[:original], suggestion[:suggestion])
        end.join("\n\n")
      end

      # Formats the entire AI review with metadata and structure
      # @param review_content [String] The main review content
      # @param metadata [Hash] Additional metadata about the review
      # @return [String] Formatted complete review
      def format_complete_review(review_content, metadata = {})
        <<~REVIEW
          # 🤖 AI Code Review

          _Generated at #{Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")}_
          #{format_metadata(metadata)}

          #{review_content}

          ---
          This is an automated review. Please verify all suggestions before implementing.
        REVIEW
      end

      private

      # Generates a colored diff between two code snippets
      # @param original [String] Original code
      # @param suggestion [String] Suggested code
      # @return [String] Colored diff output
      def format_diff(original, suggestion)
        Diffy::Diff.new(original, suggestion,
                        context: 2,           # Show 2 lines of context
                        include_diff_info: false).to_s(:color)
      end

      # Formats review metadata
      # @param metadata [Hash] Review metadata
      # @return [String] Formatted metadata string
      def format_metadata(metadata)
        metadata.map do |key, value|
          "_#{key}: #{value}_"
        end.join("\n")
      end

      # Sanitizes code blocks for markdown
      # @param code [String] Code to be sanitized
      # @return [String] Sanitized code
      def sanitize_code_block(code)
        code.gsub('```', '␣``')
      end
    end
  end
end