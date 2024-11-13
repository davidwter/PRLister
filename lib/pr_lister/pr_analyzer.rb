# lib/pr_lister/pr_analyzer.rb
module PRLister
  class PRAnalyzer
    def initialize(config)
      @config = config
      @logger = Logger.new(STDOUT)
      @logger.level = Logger.const_get(@config.log_level.upcase)
    end

    def analyze_pr(pr)
      return [] unless pr.review_data

      @config.developers.map do |reviewer|
        next if reviewer == pr.user
        analyze_reviewer_feedback(pr, reviewer)
      end.compact
    end

    private

    def analyze_reviewer_feedback(pr, reviewer)
      feedback = find_latest_feedback(pr, reviewer)

      if feedback
        {
          reviewer: reviewer,
          delay: calculate_delay(pr.created_at, feedback[:time]),
          status: feedback[:state],
          feedback_type: feedback[:type]
        }
      else
        {
          reviewer: reviewer,
          delay: nil,
          status: :pending,
          feedback_type: nil
        }
      end
    end

    def find_latest_feedback(pr, reviewer)
      # Check reviews first
      latest_review = pr.review_data[:reviews]
                        .select { |review| review[:user][:login] == reviewer }
                        .max_by { |review| review[:submitted_at] }

      if latest_review
        return {
          time: latest_review[:submitted_at],
          state: latest_review[:state],
          type: 'review'
        }
      end

      # Then check comments
      first_comment = pr.review_data[:comments]
                        .find { |comment| comment[:user][:login] == reviewer }

      if first_comment
        return {
          time: first_comment[:created_at],
          state: 'COMMENTED',
          type: 'comment'
        }
      end

      nil
    end

    def calculate_delay(start_time, end_time)
      ((end_time - start_time) / (60 * 60 * 24)).round(2)
    end
  end
end