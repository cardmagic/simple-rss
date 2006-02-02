require 'rbconfig'
require 'find'
require 'ftools'

include Config

# this was adapted from rdoc's install.rb by ways of Log4r

$sitedir = CONFIG["sitelibdir"]
unless $sitedir
  version = CONFIG["MAJOR"] + "." + CONFIG["MINOR"]
  $libdir = File.join(CONFIG["libdir"], "ruby", version)
  $sitedir = $:.find {|x| x =~ /site_ruby/ }
  if !$sitedir
    $sitedir = File.join($libdir, "site_ruby")
  elsif $sitedir !~ Regexp.quote(version)
    $sitedir = File.join($sitedir, version)
  end
end

makedirs = %w{ shipping }
makedirs.each {|f| File::makedirs(File.join($sitedir, *f.split(/\//)))}

Dir.chdir("lib")
begin
	require 'rubygems'
	require 'rake'
rescue LoadError
	puts
	puts "Please install Gem and Rake from http://rubyforge.org/projects/rubygems and http://rubyforge.org/projects/rake"
	puts
	exit(-1)
end

files = FileList["**/*"]

# File::safe_unlink *deprecated.collect{|f| File.join($sitedir, f.split(/\//))}
files.each {|f| 
  File::install(f, File.join($sitedir, *f.split(/\//)), 0644, true)
}