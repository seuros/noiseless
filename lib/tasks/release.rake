# frozen_string_literal: true

namespace :release do
  desc "Run lightweight release checks without booting the dummy app"
  task :check do
    require "shellwords"

    spec = Gem::Specification.load("noiseless.gemspec")
    raise "Failed to load noiseless.gemspec" unless spec

    version_path = File.expand_path("../../lib/noiseless/version", __dir__)
    require version_path

    if spec.version.to_s != Noiseless::VERSION
      raise "Version mismatch: gemspec=#{spec.version} lib=#{Noiseless::VERSION}"
    end

    ruby = Shellwords.escape(RbConfig.ruby)
    sh "#{ruby} -Ilib -e 'require \"noiseless\"; abort(\"version mismatch\") unless Noiseless::VERSION == \"#{Noiseless::VERSION}\"'"
    sh "gem build noiseless.gemspec"
  end
end
