require 'octokit'
require 'yaml'
require 'ruby-progressbar'
require 'colorize'
require 'date'

# Load configuration
config = YAML.load_file('config.yml')

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
    # Include the PR creation time
    pr[:created_at] = pr.created_at
    review_requests_response = client.pull_request_review_requests(repo, pr[:number])
    pr[:review_requests] = review_requests_response || { users: [] }
    pr[:review_comments] = client.pull_request_comments(repo, pr[:number])
    pr
  end
end


# Method to calculate and print delays in reviews
def calculate_feedback_delay(pr, relevant_reviewers)
  # Return empty if there's no PR creation time or review comments
  return [] unless pr[:created_at] && pr[:review_comments]
  delays = []
  relevant_reviewers.each do |reviewer|
    # Find the first comment made by the reviewer on this PR
    first_feedback = pr[:review_comments].find { |comment| comment[:user][:login] == reviewer }
    if first_feedback && first_feedback[:created_at]
      delay = (first_feedback[:created_at] - pr[:created_at]) / (60 * 60 * 24)
      delays << { reviewer: reviewer, delay: delay.round(2) }
    else
      # If there's no comment from this reviewer, record delay as nil
      delays << { reviewer: reviewer, delay: nil }
    end
  end
  delays
end


# Main processing block
all_prs = []
progressbar = ProgressBar.create(title: "Fetching PRs", total: config['repos'].size, format: '%a %B %p%% %t')
config['repos'].each do |repo|
  prs = fetch_open_prs(client, repo, config['developers'], config['include_drafts'])
  all_prs.concat(prs)
  progressbar.increment
end

# Output the PR information
all_prs.each do |pr|
  puts "PR: #{pr[:title]} by #{pr[:user][:login]}".colorize(:light_blue)
  feedback_delays = calculate_feedback_delay(pr, config['developers'])
  feedback_delays.each do |delay_info|
    if delay_info[:delay]
      puts "Feedback from #{delay_info[:reviewer]} first received after #{delay_info[:delay]} days".colorize(:green)
    else
      puts "Feedback from #{delay_info[:reviewer]} pending".colorize(:red)
    end
  end
  puts "URL: #{pr[:html_url]}".colorize(:yellow)
  puts "-" * 20
end
