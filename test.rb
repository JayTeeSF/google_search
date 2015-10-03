#!/usr/bin/env ruby

require "google-search"

# calling open for "http://www.google.com/uds/GwebSearch?start=0&rsz=large&hl=en&key=notsupplied&v=1.0&q=flashcards&filter=1"
# calling open for "http://www.google.com/uds/GwebSearch?start=32&rsz=large&hl=en&key=notsupplied&v=1.0&q=flashcards&filter=1"

SEARCH_PATHS = [
  {query: "flashcards", target_path: "/"},
  {query: "Spanish flashcards", target_path: "/learn/spanish"},
  {query: "Learn Anatomy", target_path: "/subjects/anatomy"},
  {query: "Learn Biology", target_path: "/subjects/biology"},
  {query: "CPA Exam Prep", target_path: "/subjects/cpa"},
  {query: "Learn to Speak German", target_path: "/subjects/german"},
  {query: "Bible Study", target_path: "/subjects/bible"},
  {query: "Bar Exam Prep", target_path: "/subjects/bar-exam"},
  {query: "Study Real Estate", target_path: "/subjects/real-estate"},
  {query: "NCLEX Prep", target_path: "/subjects/nclex"},
  {query: "Series 66 Exam Prep", target_path: "/subjects/series%2066"},
  {query: "AP Chemistry Flashcards", target_path: "/subjects/chemistry"},
  {query: "AP U.S. History Exam", target_path: "/learn/ap-us-history"},
  {query: "GRE Psychology Prep", target_path: "/learn/gre-psychology"},
  {query: "GRE Vocabulary Flashcards", target_path: "/learn/gre-vocabulary"},
  {query: "MCAT Test Prep", target_path: "/learn/mcat"},
  {query: "SAT Prep", target_path:  "/learn/sat-prep"},
  {query: "Series 7 Exam", target_path: "/learn/series-7-exam"},
  {query: "Learn French", target_path: "/learn/french"},
  {query: "Learn Spanish", target_path:  "/learn/spanish"},
  {query: "Learn Chinese", target_path: "/learn/chinese-(mandarin)"},
  {query: "Bartending Flashcards", target_path: "/learn/bartending"},
  {query: "Vocab Builder", target_path: "/learn/vocab-builder"}
]
TARGET_DOMAIN = "brainscape.com"
DEFAULT_FILE = "./monthly_positions.log"

@debug = true

File.open(DEFAULT_FILE, "w+") do |f|
  SEARCH_PATHS.each do |search_path_hash|
    query = search_path_hash[:query]
    @target_path = search_path_hash[:target_path]
    f.puts "\nSearching for #{query}"
    found = Google::Search::Web.new do |search|
      search.query = query
      search.size = :large
    end.detect do |item|
      if item.visible_uri.end_with?(TARGET_DOMAIN)
        if item.uri.end_with?(@target_path)
          f.puts "\tFound #{item.uri.inspect} at index: #{item.index}\n"
          true
        else
          f.puts "\tOther #{item.uri.inspect} (not: #{@target_path}) at index: #{item.index}\n"
        end
      end
    end

    unless found
      f.puts %Q(\t#Unable to find: #{TARGET_DOMAIN}#{@target_path}. In your terminal, enter:\n\t\topen "http://www.google.com/search?start=0&q=#{query}")
    end
  end
end
`cat #{DEFAULT_FILE}`
