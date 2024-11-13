require 'octokit'
require 'yaml'
require 'ruby-progressbar'
require 'colorize'
require 'date'
require 'optparse'

# Method to prompt user for input if required fields are missing
def prompt(message)
  print "#{message}: "
  gets.chomp
end

# Load configuration file or handle missing file
begin
  config = YAML.load_file('config.yml')
rescue Errno::ENOENT
  puts "Configuration file not found!".colorize(:red)
  exit
end

# Ensure required fields are present or prompt user for input
config['token'] ||= prompt("Please enter your GitHub token")
config['repos'] ||= [prompt("Please enter the repository name")]
config['developers'] ||= prompt("Please enter developer logins (comma separated)").split(',').map(&:strip)
config['include_drafts'] = prompt("Include drafts? (yes/no)") == 'yes'

# Initialize command-line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: pr_script.rb [options]"

  opts.on("-r", "--repo REPOSITORY", "Specify repository (overrides config)") do |r|
    options[:repo] = r
  end

  opts.on("-d", "--developer DEVELOPER", "Specify developer(s)") do |d|
    options[:developers] ||= []
    options[:developers] << d
  end

  opts.on("--include-drafts", "Include draft PRs") do
    options[:include_drafts] = true
  end

  opts.on("-v", "--verbose", "Show detailed output") do |v|
    options[:verbose] = v
  end

  opts.on("-o", "--output FILE", "Save output to file") do |file|
    options[:output_file] = file
  end
end.parse!

# Use options if provided, fallback to config.yml
repos = options[:repo] ? [options[:repo]] : config['repos']
developers = options[:developers] || config['developers']
include_drafts = options[:include_drafts] || config['include_drafts']

# Initialize Octokit Client
client = Octokit::Client.new(access_token: config['token'])
client.auto_paginate = true

# Method to fetch open pull requests and include review request details
def fetch_open_prs(client, repo, developers, include_drafts)
  options = { state: 'open', accept: 'application/vnd.github.shadow-cat-preview+json' }
  prs = client.pull_requests(repo, options)
  prs.reject! { |pr| pr[:draft] } unless include_drafts
  prs.select! { |pr| developers.include?(pr[:user][:login]) }
  prs.map do |pr|
    # Calculate the duration the PR has been open in days
    pr[:days_open] = ((Time.now - pr[:created_at]) / (60 * 60 * 24)).round
    review_requests_response = client.pull_request_review_requests(repo, pr[:number])
    pr[:review_requests] = review_requests_response || { users: [] }
    pr[:review_comments] = client.pull_request_comments(repo, pr[:number])
    pr
  end
end

# Method to calculate and print delays in reviews
def calculate_feedback_delay(pr, relevant_reviewers)
  return [] unless pr[:created_at] && pr[:review_comments]

  delays = []
  relevant_reviewers.each do |reviewer|
    first_feedback = pr[:review_comments].find { |comment| comment[:user][:login] == reviewer }
    if first_feedback && first_feedback[:created_at]
      delay = ((first_feedback[:created_at] - pr[:created_at]) / (60 * 60 * 24)).round(2)
      delays << { reviewer: reviewer, delay: delay }
    else
      delays << { reviewer: reviewer, delay: nil }
    end
  end
  delays
end

# Method to display time in human-readable format
def time_ago_in_words(time)
  days_open = ((Time.now - time) / (60 * 60 * 24)).round
  case days_open
  when 0 then "today"
  when 1 then "1 day ago"
  else "#{days_open} days ago"
  end
end

# Main processing block
all_prs = []
progressbar = ProgressBar.create(
  title: "Fetching PRs",
  total: repos.size,
  format: '%a %B %p%% %t - %c/%C repos, %E eta'
)

repos.each do |repo|
  begin
    prs = fetch_open_prs(client, repo, developers, include_drafts)
    all_prs.concat(prs)
    progressbar.increment
  rescue Octokit::Error => e
    puts "Error fetching PRs from #{repo}: #{e.message}".colorize(:red)
  end
end

# Sort PRs by days open
all_prs.sort_by! { |pr| -pr[:days_open] }

# Output the PR information
output_lines = []
all_prs.each do |pr|
  pr_info = []
  pr_info << "PR: #{pr[:title]} by #{pr[:user][:login]} has been open for #{time_ago_in_words(pr[:created_at])}".colorize(:light_blue)

  feedback_delays = calculate_feedback_delay(pr, developers)
  feedback_delays.each do |delay_info|
    if delay_info[:delay]
      pr_info << "Feedback from #{delay_info[:reviewer]} first received after #{delay_info[:delay]} days".colorize(:green)
    else
      pr_info << "Feedback from #{delay_info[:reviewer]} pending".colorize(:red)
    end
  end

  pr_info << "URL: #{pr[:html_url]}".colorize(:yellow)
  pr_info << "-" * 20

  output_lines << pr_info.join("\n")

  # Print output if verbose mode is enabled
  if options[:verbose]
    puts pr_info.join("\n")
  end
end

# Save output to file if specified
if options[:output_file]
  File.open(options[:output_file], 'w') do |file|
    file.puts output_lines.join("\n")
  end
  puts "Results saved to #{options[:output_file]}".colorize(:green)
else
  # Otherwise, print the output to the console
  puts output_lines.join("\n") unless options[:verbose]
end