# lib/pr_lister/feature_flags.rb
module PRLister
  module FeatureFlags
    class << self
      def ai_review_enabled?
        return @ai_review_enabled if defined?(@ai_review_enabled)
        @ai_review_enabled = begin
                               ENV['ENABLE_AI_REVIEW'] == 'true' &&
                                 required_gems_available?(['anthropic', 'ruby-openai'])
                             end
      end

      def parallel_processing_enabled?
        return @parallel_enabled if defined?(@parallel_enabled)
        @parallel_enabled = begin
                              ENV['ENABLE_PARALLEL'] == 'true' &&
                                required_gems_available?(['parallel'])
                            end
      end

      private

      def required_gems_available?(gems)
        gems.all? do |gem_name|
          require gem_name
          true
        rescue LoadError
          false
        end
      end
    end
  end
end