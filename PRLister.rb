require 'octokit'
require 'yaml'
require 'ruby-progressbar'
require 'colorize'

# Load configuration
config = YAML.load_file('config.yml')

client = Octokit::Client.new(access_token: config['token'])
client.auto_paginate = true

def fetch_open_prs(client, repo, developers)
  prs = client.pull_requests(repo, state: 'open')
  prs.select { |pr| developers.include?(pr[:user][:login]) }
end

all_prs = []
progressbar = ProgressBar.create(title: "Fetching PRs", total: config['repos'].size, format: '%a %B %p%% %t')

config['repos'].each do |repo|
  prs = fetch_open_prs(client, repo, config['developers'])
  all_prs.concat(prs)
  progressbar.increment
end

# Output the PR information
all_prs.each do |pr|
  puts "PR: #{pr[:title]} by #{pr[:user][:login]}".colorize(:light_blue)
  puts "URL: #{pr[:html_url]}".colorize(:yellow)
  puts "-" * 20
end
