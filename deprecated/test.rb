#!/usr/bin/env ruby

require "google-search"

[
  "hackerspace new york",
  "makerspace new york",
  "fab lab new york"
].each do |query|
  puts "searching for #{query}"
  Google::Search::Web.new do |search|
    search.query = query
    search.size = :large
  end.each { |item| puts item.title }
end
