#!/usr/bin/env ruby

require_relative 'lib_publish.rb'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: publish_adoc.rb [options]"

  opts.on("-a", "--all", "Process all available texts") { options[:all] = true }
  opts.on("-i", "--id NAME", "Provide name of a single text to process") { |v| options[:id] = v }
  opts.on("-r", "--retain", "Do not delete temporary files") { options[:retain] = true }

end.parse!

@notes_dir = "../notes/"
@adoc_dir = "../source/"
@html_dir = "../docs/"
@styles_dir = "../../styles/"

@config = YAML::load(File.read("config.yml"))

if options[:all]
  process_all
else
  id = ARGV[0]

  if !id
    abort("  Please specify a story ID.")
  end

  publish_adoc(id)
end

if !options[:retain] && !options[:all]
  clean_up_files
end
