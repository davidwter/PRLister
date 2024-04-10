require 'octokit'
require 'yaml'

# Load configuration
config = YAML.load_file('config.yml')

client = Octokit::Client.new(access_token: config['token'])
client.auto_paginate = true

def fetch_open_prs(client, repo, developers)
  prs = client.pull_requests(repo, state: 'open')
  prs.select { |pr| developers.include?(pr[:user][:login]) }
end

all_prs = []
config['repos'].each do |repo|
  prs = fetch_open_prs(client, repo, config['developers'])
  all_prs.concat(prs)
end

# Output the PR information
all_prs.each do |pr|
  puts "PR: #{pr[:title]} by #{pr[:user][:login]}"
  puts "URL: #{pr[:html_url]}"
  puts "-" * 20
end
