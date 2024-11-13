# lib/pr_lister/file_analyzer.rb
module PRLister
  class FileAnalyzer
    PATTERNS = {
      ruby: /\.(rb|rake)$/,
      javascript: /\.(js|jsx|ts|tsx)$/,
      database: /db\/migrate|schema\.rb|_spec\.rb|\.sql$/,
      security_sensitive: /\/(auth|login|password|token|secret|credential)/i,
      test: /_spec\.rb|_test\.rb|\.test\.js|\.spec\.js$/
    }

    def self.categorize_files(files)
      categories = Hash.new { |h, k| h[k] = [] }

      files.each do |file|
        PATTERNS.each do |category, pattern|
          categories[category] << file if file.filename =~ pattern
        end
      end

      categories
    end

    def self.determine_review_templates(files)
      categories = categorize_files(files)
      templates = ['default']

      templates << 'ruby' if categories[:ruby].any?
      templates << 'javascript' if categories[:javascript].any?
      templates << 'database' if categories[:database].any?

      templates
    end
  end
end