
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "tiun/version"

Gem::Specification.new do |spec|
  spec.name          = "tiun"
  spec.version       = Tiun::VERSION
  spec.authors       = ["Malo Skrylevo"]
  spec.email         = ["majioa@yandex.ru"]

  spec.summary       = %q{Tiun is a backend gem for admin rails application.}
  spec.description   = %q{Tiun is an old russian high level manager for a city from a prince or boyar. According the repo tiun is a backend gem for admin rails application.}
  spec.homepage      = "https://codeberg.org/znamenica/tiun"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 12.0", ">= 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pundit", "~> 1.1"
  spec.add_development_dependency "pry", "~> 0.11"
  spec.add_development_dependency "rails", "~> 5.2"
  spec.add_development_dependency "rspec-rails", "~> 4.0.1"
  spec.add_development_dependency "pg", "~> 1.2"
  spec.add_development_dependency "sqlite3", "~> 1.3.6"
  spec.add_development_dependency "bootsnap", "~> 1.4"
  spec.add_development_dependency "listen", "~> 3.0"
  spec.add_development_dependency "cucumber-rails"
  spec.add_development_dependency "shoulda-matchers-cucumber", "~> 1.0"
  spec.add_development_dependency "match_hash", "~> 0.1.2"
  spec.add_development_dependency "dawnscanner", "~> 1.6"
  # spec.add_development_dependency "active_model_serializers", "~> 0.10", ">= 0.10.6"
  spec.add_runtime_dependency "activesupport", ">= 4.1.0"
  spec.add_runtime_dependency "railties", ">= 4.1.0"
  spec.add_runtime_dependency "jsonize", "~> 0.2"
end
