# lib/pr_lister/github_repo.rb
module PRLister
  class GithubRepo
    attr_reader :owner, :name, :full_name

    def initialize(repo_string)
      @owner, @name = repo_string.split('/')
      @full_name = repo_string
    end

    def to_s
      @full_name
    end
  end
end