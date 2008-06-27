# Sam's tvdb.com scraper 
# Written by Sam Saffron - sam.saffron@gmail.com 
# 
# Scrapes information from http://thetvdb.com/ which is an open directory 
# 	for tv show metadata

# 31 Jan 2008 - fixed issue with house md
# 2 Feb 2008 - Fix issue where it destroys files when there is overlap using the -f option 

require "getoptlong"
require "net/http"
require "cgi"
require 'rexml/document'
require 'pathname'
require 'find'
include REXML

def usage()
	puts
	puts "Scrapes information from thetvdb.org"
	puts 
	puts "Usage: ruby scraper.rb directory [--fixnames|-f] [--refresh|-r]"
	puts
	puts "\t--fixnames   sets filename to: episode number-episode name"
	puts "\tEg. 01-The first episode.avi"
	puts 
	puts "\t--refresh   refresh meta data for all tv shows"
end


class Series 
	
	attr_reader :name 
	
	def initialize(name, series_path, refresh)
		
		@series_xml_path = series_path + "series.xml"
		@name = name
		
		@series_xml_path.delete if refresh && @series_xml_path.file?
		
		if not @series_xml_path.file?  
			series_xml = get_series_xml()	
			@series_xml_path.open("w")  {|file| file.puts series_xml}
			@xmldoc = Document.new(series_xml)
		else 
			@series_xml_path.open("r") {|file| @xmldoc = Document.new(file) }
		end  
		
		
		@name = @xmldoc.elements["Item/SeriesName"].text
		
	end
	
	def id()
		@xmldoc.elements["/Item/id"].text 
	end 
	
	def strip_dots(s)
	  s.gsub(".","")
	end 
	
	def get_series_xml()
		
		url = URI.parse('http://thetvdb.com')
		res = Net::HTTP.start(url.host, url.port) do |http|
			http.get('/interfaces/GetSeries.php?seriesname=' +   CGI::escape(@name))
		end
		
		doc = Document.new res.body
		
		series_xml = nil 
		
		doc.elements.each("Items/Item") do |element|
		  
		  if strip_dots(element.elements["SeriesName"].text.downcase) == strip_dots(@name.downcase)	
			  series_xml = element.to_s
			  break
			end
		end 
		
		if series_xml == nil 
		  doc.elements.each("Items/Item") do |element|
			  series_xml = element.to_s
			  break
		  end 
	  end 
		
		series_xml
	end 
	
	def get_episode(filename, season, episode_number, refresh)
		Episode.new(self, filename, season, episode_number,refresh)
	end 
end 

class Episode
	
	attr_reader :series
	attr_reader :filename
	
	def initialize(series, filename, season, episode_number,refresh)
	
		@filename = filename
		@series = series
		@episode_xml_path = (filename.dirname + "metadata") + (drop_extension(filename.basename).to_s + ".xml")
		
		@episode_xml_path.delete if refresh && @episode_xml_path.file?
		
		if not @episode_xml_path.file? 
			episode_xml = get_episode_xml(series,season,episode_number)

			#ensure we have a metadata dir 
			unless @episode_xml_path.dirname.directory? 
				Dir.mkdir(@episode_xml_path.dirname.to_s)  
				IO.popen("ATTRIB +H " + "\"" + @episode_xml_path.dirname +  "\"")
			end 
			
			@xmldoc = Document.new(episode_xml)
			element = @xmldoc.elements["Item"].add_element("ShowName").text = series.name
			
			@episode_xml_path.open("w")  {|file| file.puts @xmldoc.to_s}
			
		else 
			@episode_xml_path.open("r") {|file| @xmldoc = Document.new(file) }
		end  
		
		thumb_name = @xmldoc.elements["Item/filename"].text if @xmldoc.elements["Item/filename"] 
		
		if thumb_name && thumb_name.length > 0 
		
			thumb_filename = @episode_xml_path.dirname + ((Pathname.new thumb_name).basename)
			
			thumb_filename.delete if refresh && thumb_filename.file?
			
			unless thumb_filename.file? 
				# download it
				url = URI.parse('http://thetvdb.com')
				res = Net::HTTP.start(url.host, url.port) do |http|
					http.get('/banners/' + thumb_name)
				end
		
				thumb_filename.open("wb")  {|file| file.puts res.body} 
			end
		end 
	end
	
	# Renames the file to episode number - episode name
	def fix_name!()
		new_basename = ("0" + episode_number)[-2,2] + " - " + name
		# sanitize the name 
		new_basename.sub!(":", " -")
		["?","\\",":","\"","|",">", "<", "*", "/"].each {|l| new_basename.sub!(l,"")}
		
		
		new_filename = @filename.dirname + (new_basename + @filename.extname)
		new_episode_xml_path = @episode_xml_path.dirname + (new_basename + ".xml")
		
		raise "can not rename #{@filename} detected a duplicate" if new_filename.file? 
		
		File.rename(@filename, new_filename)
		File.rename(@episode_xml_path, new_episode_xml_path)
		
		@filename = new_filename
		@episode_xml_path = new_episode_xml_path
		
	end 
	
	def get_episode_xml(series, season, episode_number)
		url = URI.parse('http://thetvdb.com')
		res = Net::HTTP.start(url.host, url.port) do |http|
			http.get('/interfaces/GetEpisodes.php?seriesid=' + 
				CGI::escape(series.id) + "&season=" + season + "&episode=" + CGI::escape(episode_number) )
		
		end
		
		doc = Document.new res.body
		
		# TODO: error handling ... 
		id = doc.elements["Items/Item/id"].text	
		
		res = Net::HTTP.start(url.host, url.port) do |http|
			http.get('/interfaces/EpisodeUpdates.php?lasttime=0&idlist=' + CGI::escape(id))
		
		end
		
		doc = Document.new res.body
		episode_xml = nil 
		doc.elements.each("Items/Item") do |element|
			# TODO : smart heuristic to figure out the correct name
			
			found_id = element.elements["id"].text if element.elements["id"]
			if found_id == id 
				episode_xml = element.to_s
				break
			end 
		end 
		episode_xml
	end 
	
	def name()
		@xmldoc.elements["/Item/EpisodeName"].text 
	end 
	
	def episode_number()
		@xmldoc.elements["/Item/EpisodeNumber"].text 
	end 
end 

def drop_extension(filename)
	Pathname.new(filename.to_s[0, filename.to_s.length - filename.extname.length])
end 

def get_details(file, refresh)
	
	# figure out what the show is based on path and filename
	season = nil 
	show_name = nil
	
	contains_season_path = false
	
	file.parent.ascend do |item|  
		if not season 
			season = /\d+/.match(item.basename.to_s)
			if season			
				#possibly we may want special handling for 24 
				season = season[0] 
				contains_season_path = true
			else
				season = "1" 
				show_name = item.basename.to_s
				break 
			end 
			
		else 
			show_name = item.basename.to_s 
			break 
		end 	
	end
	
	return nil unless  /\d+/ =~ file.basename
	
	# check for a match in the style of 1x01
	if /(\d+)[x|X](\d+)/ =~ file.basename
		season, episode_number = $1.to_s, $2.to_s
	
	else 
		# check for s01e01
		if /[s|S](\d+)x?[e|E](\d+)/ =~ file.basename
			season, episode_number = $1.to_s, $2.to_s
		else 	
			# the simple case 
			episode_number = /\d+/.match(file.basename)[0]
			if episode_number.to_i > 99 && episode_number.to_i < 1900 
				# handle the format 308 (season, episode) with special exclusion to year names Eg. 2000 1995
				season = episode_number[0,episode_number.length-2]
				episode_number = episode_number[episode_number.length-2 , episode_number.length]
			end  
		end 
	end 
	
	season = season.to_i.to_s 
	episode_number = episode_number.to_i.to_s
	
	return nil if episode_number.to_i > 99
	
	series_path = file.dirname
	
	if contains_season_path 
		series_path = series_path.dirname
	end
	
	# p "#{file} , show #{show_name} ,  path #{series_path} , episode #{episode_number} , season #{season}"
	
	if (series_path + "skip").file? 
		puts "Path Skipped (contains a file named skip)" 
		nil 
	else
	
		series = Series.new show_name, series_path, refresh
		begin 
			series.get_episode file, season, episode_number, refresh
		rescue
			nil 
		end	
	end
end


# Main program


if not ARGV[0]
	usage
	exit
end 

path = Pathname.new(ARGV[0]) 

if not path.directory?   
	puts "Directory not found " + path	
	usage 
	exit
end
	
fixnames = false
refresh = false

parser = GetoptLong.new 
parser.set_options(
	["-h", "--help", GetoptLong::NO_ARGUMENT],
	["-f", "--fixnames", GetoptLong::NO_ARGUMENT], 
	["-r", "--refresh", GetoptLong::NO_ARGUMENT]
) 

loop do 

	opt, arg = parser.get
	break if not opt
	
	case opt
		when "-h"
			usage
			break
		when "-f"
			fixnames = true
			break 
		when "-r" 
			refresh = true
			break
	end
		
end

Find.find(path.to_s) do |filename| 
	
	Find.prune if [".",".."].include? filename

	if filename =~ /\.(avi|mpg|mpeg|mp4|divx|mkv)$/ 
		
		puts filename
		
		episode = get_details(Pathname.new(filename), refresh)
		
		if episode
			puts "found: #{episode.episode_number} - #{episode.name} - #{episode.series.name}"
			begin 
			  episode.fix_name! if fixnames
			rescue
        puts "Error: " + $! 
      end
		else 
			puts "no data found for #{filename}" 
		end 
		
		puts
	end
	
end

#show_name, show_season, episode_number = get_details(file)


# e:\videos\tv\family guy\season 1
# e:\videos\tv\family guy
# e:\videos\tv


