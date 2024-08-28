#!/usr/bin/env ruby

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('Gemfile', __dir__)
require 'bundler/setup'

require "nokogiri"
require "ostruct"
require "byebug"

def file_xml(song_file)
  xml_str = File.read(song_file)
  Nokogiri::XML(xml_str)
end

def song_data(song_file)
  doc = file_xml(song_file)
  raw_lyrics = doc.at_xpath('//lyrics').content
  opensong = opensong_sections(raw_lyrics)
  OpenStruct.new(
    title: doc.at_xpath('//title').content,
    raw_lyrics: ,
    opensong: ,
    author: doc.at_xpath('//author').content,
    presentation: doc.at_xpath('//presentation').content.upcase.split(/\s+/),
    tempo: doc.at_xpath('//tempo').content,
    time: doc.at_xpath('//time_sig').content,
    key: doc.at_xpath('//key').content,
    link_youtube: doc.at_xpath('//link_youtube')&.content,
    link_web: doc.at_xpath('//link_web')&.content,
  )
end

def opensong_sections(lyrics)
  current_section = nil
  lyrics.split("\n").each_with_object({}) do |line, acc|
    if line =~ /\A\[/
      current_section = line.gsub(/[\[\]\s]/, "").upcase
      acc[current_section] = []
    elsif line =~ /\A\s/
      acc[current_section] << {line: line, type: :lyric}
    elsif line =~ /\A\./
      acc[current_section] << {line: line, type: :chords}
    elsif line =~ /\A\;/
      acc[current_section] << {line: line[1..-1], type: :comment} unless current_section.nil?
    elsif line =~ /\A\z/
      # empty line
    else
      raise "unkown opensong line type: #{line.inspect}"
    end
  end
end

def convert_to_chordpro(song)
  sections = chordpro_sections(song)
  # Ordered sections according to presentation
  ordered_sections = song.presentation.map do |section|
    "{comment: #{section_to_human(section)}}\n" +
    sections[section].join("\n")
  rescue => ex
    byebug
  end
  # # Only sections without presentation order
  # ordered_sections = chordpro_sections.map do |(name, content)|
  #   "{comment: #{name}}\n" +
  #   content.join("\n")
  # end
  <<~EOS
  {title: #{song.title}}
  {artist: #{song.author} }
  {tempo: #{song.tempo}}
  {time: #{song.time}}
  {key: #{song.key}}
  {flow: #{song.presentation.map { section_to_human(_1) }.join(" ")}}
  
  {comment: #{song.link_youtube}}
  {comment: #{song.link_web}}

  #{ordered_sections.join("\n\n")}
  EOS
end

def chordpro_sections(song)
  song.opensong.each_with_object({}) do |(name, content), acc|
    acc[name] = section_to_chordpro(content)
  end
end

def section_to_chordpro(section)
  last_chord_line_item = nil
  converted_section = section.each_with_object([]) do |line_item, acc|
    case line_item[:type]
    when :lyric
      acc << interpolate_chord_with_line(last_chord_line_item, line_item[:line])
      last_chord_line_item = nil
    when :chords
      acc << chords_to_chordpro(last_chord_line_item)
      last_chord_line_item = line_item
    when :comment
      chords_to_chordpro(last_chord_line_item)
      last_chord_line_item = nil
      acc << "{comment: #{line_item[:line]}}"
    else
      raise "Invalid line item"
    end
  end << chords_to_chordpro(last_chord_line_item)
  converted_section.compact
end

CHORD_REGEXP = /(?<=[\s\.])[a-zA-Z0-9#]+/

def interpolate_chord_with_line(chords_line, lyrics)
  return lyrics if chords_line.nil?

  chords = chords_line[:line]

  chord_queue = chords.scan(CHORD_REGEXP)
  chord_positions = chords.enum_for(:scan, CHORD_REGEXP).map { Regexp.last_match.begin(0) }
  lyrics.chars.each_with_index.map do |char,index|
    if chord_positions.include?(index)
      char + "[#{chord_queue.shift}]"
    else
      char
    end
  end.join + chord_queue.map{"[#{_1}]"}.join(" ")
end

def chords_to_chordpro(chords_line)
  return nil if chords_line.nil?

  chords = chords_line[:line]

  chord_queue = chords.scan(CHORD_REGEXP)
  chord_queue.map{"[#{_1}]"}.join(" ")
end

def convert_to_txt(song)
  sections = txt_sections(song)
  # Ordered sections according to presentation
  ordered_sections = song.presentation.map do |section|
    "#{section_to_human(section)}\n\n" +
    sections[section].join("\n")
  end
  <<~EOS
  title: #{song.title}
  artist: #{song.author}
  tempo: #{song.tempo}
  time: #{song.time}
  key: #{song.key}
  flow: #{song.presentation.map { section_to_human(_1) }.join(" ")}
  
  #{song.link_youtube}
  #{song.link_web}

  #{ordered_sections.join("\n\n")}
  EOS
end

def txt_sections(song)
  song.opensong.each_with_object({}) do |(name, content), acc|
    acc[name] = section_to_txt(content)
  end
end

def section_to_txt(section)
  converted_section = section.each_with_object([]) do |line_item, acc|
    case line_item[:type]
    when :lyric
      acc << line_item[:line]
    when :chords
      acc << line_item[:line]
    when :comment
      acc << "##{line_item[:line]}"
    else
      raise "Invalid line item"
    end
  end
  converted_section.compact
end

def section_to_human(section)
  if section =~ /\AC(\d+|\s+|\z)/
    section.gsub("C", "CORO")
  elsif section =~ /\AB(\d+|\s+|\z)/
    section.gsub("B", "PUENTE")
  elsif section =~ /\AP(\d+|\s+|\z)/
    section.gsub("P", "PRE-CORO")
  elsif section =~ /\AV(\d+|\s+|\z)/
    section.gsub("V", "VERSO")
  else
    section
  end
end

def convert_song_file_to_formats(song_file, verbose: false, formats: [:txt, :chordpro])
  song = song_data(song_file)
  if formats.include? :chordpro
    chordpro = convert_to_chordpro(song)
    if verbose
      puts "Song #{song.title}"
      puts chordpro
    end
    File.write("#{song_file}.chopro", chordpro)
  end
  if formats.include? :txt
    txt = convert_to_txt(song)
    if verbose
      puts "Song #{song.title}"
      puts txt
    end
    File.write("#{song_file}.txt", txt)
  end
end

def convert_path_to_formats(path, verbose: false, formats: [:txt, :chordpro])
  if File.directory?(path)
    Dir.entries(path).each do |file|
      next if file =~ /\A\./ || file =~ /.+\.(chopro|txt)/
      puts "CONVERTING: #{file}"
      convert_song_file_to_formats(File.join(path, file), verbose:, formats:)  
    end
  elsif File.file?(path)
    puts "CONVERTING: #{path}"
    convert_song_file_to_formats(path, verbose:, formats:)
  else
    raise "Invalid path provided"
  end
end

path = ARGV[0] || "tmp/"
formats = ARGV[1].nil? ? [:txt, :chordpro] : Array(ARGV[1].to_sym)
verbose = !ARGV[2].nil?
convert_path_to_formats(path, verbose:)
