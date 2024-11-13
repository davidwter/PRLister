# lib/pr_lister/reporter.rb
require 'colorize'

module PRLister
  class Reporter
    def initialize(config)
      @config = config
      @analyzer = PRAnalyzer.new(config)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger.const_get(@config.log_level.upcase)
    end

    def generate_report(prs)
      report = format_pull_requests(prs)

      if @config.output_file
        save_to_file(report)
      else
        puts report unless @config.verbose
      end
    end

    private

    def format_pull_requests(prs)
      sorted_prs = prs.sort_by(&:days_open).reverse
      sorted_prs.map { |pr| format_single_pr(pr) }.join("\n\n")
    end

    def format_single_pr(pr)
      [
        format_pr_header(pr),
        format_feedback_delays(pr),
        format_pr_url(pr),
        "-" * 50
      ].flatten.join("\n")
    end

    def format_pr_header(pr)
      [
        "#{pr.repo}: #{pr.title}".colorize(:light_blue),
        " by #{pr.user}".colorize(:blue),
        " (#{format_time_ago(pr.created_at)})".colorize(:yellow)
      ].join
    end

    def format_feedback_delays(pr)
      @analyzer.analyze_pr(pr).map do |feedback|
        next if feedback[:reviewer] == pr.user # Skip PR author

        reviewer_prefix = "  • #{feedback[:reviewer]}: "

        if feedback[:delay].nil?
          reviewer_prefix + "pending review".colorize(:red)
        elsif feedback[:status] == 'APPROVED'
          reviewer_prefix + "approved ".colorize(:green) + format_delay(feedback[:delay]).colorize(:light_green)
        elsif feedback[:status] == 'CHANGES_REQUESTED'
          reviewer_prefix + "requested changes ".colorize(:red) + format_delay(feedback[:delay]).colorize(:light_red)
        else
          reviewer_prefix + "commented ".colorize(:yellow) + format_delay(feedback[:delay]).colorize(:light_yellow)
        end
      end.compact
    end


    def format_pr_url(pr)
      "  URL: #{pr.html_url}".colorize(:cyan)
    end

    def format_time_ago(time)
      case (days = days_ago(time))
      when 0 then "opened today"
      when 1 then "opened yesterday"
      else "open for #{days} days"
      end
    end

    def format_delay(days)
      return "" unless days

      case days.round
      when 0 then "today"
      when 1 then "yesterday"
      else "#{days.round} days ago"
      end
    end

    def days_ago(time)
      ((Time.now - time) / (60 * 60 * 24)).round
    end

    def save_to_file(report)
      File.write(@config.output_file, report)
      @logger.info("Report saved to #{@config.output_file}".colorize(:green))
    end
  end
end