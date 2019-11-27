#!/usr/bin/env ruby

require 'asciidoctor'
require 'fileutils'
require 'htmlentities'
require 'optparse'
require 'rubypants'
require 'yaml'

def insert_sidenote(id, text)
  ":#{id}: pass:[<label for=\"#{id}\" class=\"margin-toggle sidenote-number\"></label><input type=\"checkbox\" id=\"#{id}\" class=\"margin-toggle\"><span class=\"sidenote\">#{text}</span>]"
end

def insert_marginnote(id, text)
  ":#{id}: pass:[<label for=\"#{id}\" class=\"margin-toggle\"></label><input type=\"checkbox\" id=\"#{id}\" class=\"margin-toggle\"><span class=\"marginnote\">#{text}</span>]"
end

def insert_footnote(id, text)
  ":#{id}: pass:n[#{text}]"
end

def add_classes(text)
  text
    .gsub(/pinyin: _(.*?)_/, "pinyin: [py]##_\\1_##")
    .gsub(/([一-龜，、]+)/, "[zh]##\\1##")
end

def smart_quotes(in_doc)
  doc_txt = File.read(in_doc)
  out_doc = ""
  doc_txt.each_line do |line|
    if line.match(/(^\[)|(^:)|(^''')|(^include::)/)
      out_doc << line
    else
      out_doc << HTMLEntities.new.decode(RubyPants.new(line).to_html)
    end
  end
  out_doc
end

def strip_passthroughs(in_doc)
  doc_txt = File.read(in_doc)
  doc_txt
    .gsub(/\/notes\/notes\.adoc/, "/notes/footnotes.adoc")
    .gsub(/^include::\.\.\/\.\.\/styles\/css\.adoc\[\]/, "")
    .gsub(/\{mn\-.*?\}/, "")
    .gsub(/^:nofooter:\n/, "\n\n[.text-center]\nBy {author}\n")
    .gsub(/\Z/, "\n\n<<<\n")
end

def process_notes
  notes_txt = @notes_dir + "notes.txt"
  notes = File.read(notes_txt)
  notes_out = ""
  fn_out = ""

  notes.each_line do |line|
    id,text = line.chomp.split("\t")
    content = HTMLEntities.new.decode(RubyPants.new(text).to_html)
    content_classes = add_classes(content)
    adoc_out = Asciidoctor.convert content_classes, safe: :safe
    html_out = adoc_out
      .gsub(/\A<div class="paragraph">\n<p>/, "")
      .gsub(/<\/p>\n<\/div>\Z/, "")
    if id.match(/^mn\-/)
      notes_out << insert_marginnote(id, html_out) + "\n"
    else
      notes_out << insert_sidenote(id, html_out) + "\n"
      fn_out << insert_footnote(id, content) + "\n"
    end
  end

  File.open(@notes_dir + "notes.adoc", "w") { |f| f << notes_out }
  File.open(@notes_dir + "footnotes.adoc", "w") { |f| f << fn_out }
end

def generate_html(id, source_path)
  html_outdoc = smart_quotes(source_path + id + ".adoc")
  @output_dir = @html_dir + id + "/"
  FileUtils.mkdir_p @output_dir
  copy_images(id, @output_dir)
  @html_out_adoc = @output_dir + "index.adoc"
  File.open(@html_out_adoc, "w") { |f| f << html_outdoc }
  puts `cd #{@output_dir}; asciidoctor index.adoc`
end

def generate_pdf(id, source_path)
  fonts_dir = @config[:fonts_dir]

  pdf_outdoc_txt = strip_passthroughs(@output_dir + "index.adoc").gsub(/\{sn\-.*?\}/, "footnote:[\\0]")
  @pdf_out_adoc = @output_dir + id + "_pdf.adoc"
  File.open(@pdf_out_adoc, "w") { |f| f << pdf_outdoc_txt }
  theme_file = @styles_dir + "theme.yml"
  puts `cd #{@output_dir}; asciidoctor-pdf #{id}_pdf.adoc -a pdf-style=#{theme_file} -a pdf-fontsdir=#{fonts_dir} -o #{id}.pdf --trace`
end

def clean_up_files
  File.delete(@html_out_adoc)
  File.delete(@pdf_out_adoc)
  File.delete(@epub_file_base + "-cover.png")
  File.delete(@epub_file_base + "-cover.svg")
  File.delete(@epub_file_base + ".adoc")
  File.delete(@epub_file_base + "-content.adoc")

  FileUtils.mv(@epub_file_base + ".epub", @epub_file_base.gsub(/\-epub/, "") + ".epub")
end

def copy_images(id, target_dir)
  images = Dir.glob("../images/#{id}-*")
  images.each do |i|
    FileUtils.cp i, target_dir
  end
end

def generate_booklet(target_dir, id)
  absolute_target = File.absolute_path(target_dir) + "/"
  bookletizer_dir = @config[:bookletizer_dir]
  in_pdf = absolute_target + id + ".pdf"
  `cd "#{bookletizer_dir}"; ./bookletizer.rb -f "#{in_pdf}" -o "#{absolute_target}"`
end

def generate_epub(source_path, id)
  source_adoc = File.read(source_path + id + ".adoc")
  spine_filename = @output_dir + id + "-epub.adoc"
  content_filename = @output_dir + id + "-epub-content.adoc"
  /\A= (?<title>.*?)\n(?<author>.*?)\n(?<attributes>.*:nofooter:\n)/m =~ source_adoc

  epub_frontmatter = ":producer: Open Adocs\n:keywords: Sui Sin Far, Suisinfar, Edith Maude Eaton, Edith Eaton, Public Domain\n:copyright: CC 0\n:publication-type: book\n:idprefix:\n:idseparator: -\n:front-cover-image: image:#{id}-epub-cover.png[Front Cover,368,639]"

  epub_includes = "include::#{id}-epub-content.adoc[]"
  
  spine_content = "= #{title}\n#{author}\n#{attributes}#{epub_frontmatter}\n\n#{epub_includes}\n"
  File.open(spine_filename, "w") {|f| f << spine_content}
  
  core_content = source_adoc
    .gsub(/\A.*:nofooter:\n/m, "")
    .gsub(/\/notes\/notes\.adoc/, "/notes/footnotes.adoc")
    .gsub(/\{mn\-.*?\}/, "")
    .gsub(/\{sn\-.*?\}/, "footnote:[\\0]")

  content_out = "= #{title}\n#{core_content}\n++++\n<div style=\"page-break-before:always;\">&nbsp;</div>\n++++\n"
  File.open(content_filename, "w") {|f| f << content_out }
  epub_basename = File.basename(spine_filename)
  `cd #{@output_dir}; asciidoctor-epub3 #{epub_basename}`

  @epub_file_base = @output_dir + id + "-epub"
end

def publish_adoc(id)
  process_notes

  source_path = File.absolute_path(@adoc_dir + id) + "/"
  adoc_filename = source_path + id + ".adoc"

  if !File.exist?(adoc_filename)
    abort("  Specified file does not exist.")
  end

  generate_html(id, source_path)
  generate_pdf(id, source_path)
  generate_epub(source_path, id)
  generate_booklet(@output_dir, id)

  puts "  Published '#{id}' to output directory."
end

def process_all
  dirs = Dir.glob(@adoc_dir + "*")
  dirs.sort.each do |d|
    id = File.basename(d)
    if id == "spring" then next end
    publish_adoc(id)
    clean_up_files
  end
end

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
