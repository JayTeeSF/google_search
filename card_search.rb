#!/usr/bin/env ruby

require "google-search"

# fail "GET'ng w/ Ruby v#{RUBY_VERSION}" 

[
  "find biology flashcards"
].each do |query|
  puts "searching for #{query}"
  Google::Search::Web.new do |search|
    search.query = query
    search.size = :large
  end.each do |item|
    image_info = ""
    if item.thumbnail_uri
      image_info = "[(#{item.thumbnail_height}x#{item.thumbnail_width}) #{thumbnail_uri}]\n\t"
    end
    puts "#{item.index}) #{item.title}\n\t#{item.uri}#{image_info}\n\t#{item.visible_uri}\n"
  end
end
