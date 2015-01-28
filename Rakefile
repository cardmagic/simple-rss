require 'bundler/setup'
require 'rake'
require 'rake/testtask'
require 'rdoc/task'
require 'rubygems/package_task'
require './lib/simple-rss'

PKG_VERSION = SimpleRSS::VERSION
PKG_FILES = FileList[
    "lib/*", "bin/*", "test/**/*", "[A-Z]*", "Rakefile", "html/**/*"
]

desc "Default Task"
task :default => [ :test ]

# Run the unit tests
desc "Run all unit tests"
Rake::TestTask.new("test") { |t|
  t.libs << ["lib", "test"]
  t.pattern = 'test/*/*_test.rb'
  t.verbose = true
}

# Make a console, useful when working on tests
desc "Generate a test console"
task :console do
   verbose( false ) { sh "irb -I lib/ -r 'simple-rss'" }
end

# Genereate the RDoc documentation
desc "Create documentation"
Rake::RDocTask.new("doc") { |rdoc|
  rdoc.title = "Simple RSS - A Flexible RSS and Atom reader for Ruby"
  rdoc.rdoc_dir = 'html'
  rdoc.rdoc_files.include('README.markdown')
  rdoc.rdoc_files.include('lib/*.rb')
}

# Genereate the package
spec = Gem::Specification.new do |s|

  #### Basic information.

  s.name = 'simple-rss'
  s.version = PKG_VERSION
  s.summary = <<-EOF
   A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation.
  EOF
  s.description = <<-EOF
   A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. It is designed to be backwards compatible with the standard RSS parser, but will never do RSS generation.
  EOF

  #### Which files are to be included in this gem?  Everything!  (Except CVS directories.)

  s.files = PKG_FILES

  #### Load-time details: library and application (you will need one or both).

  s.require_path = 'lib'

  #### Documentation and testing.

  s.has_rdoc = true

  #### Author and project details.

  s.author = "Lucas Carlson"
  s.email = "lucas@rufy.com"
  s.homepage = "https://github.com/cardmagic/simple-rss"
end

Gem::PackageTask.new(spec) do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

desc "Report code statistics (KLOCs, etc) from the application"
task :stats do
  require 'code_statistics'
  CodeStatistics.new(
    ["Library", "lib"],
    ["Units", "test"]
  ).to_s
end
