# lib/pr_lister/errors.rb
module PRLister
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class APIError < Error; end
end