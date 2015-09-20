#require "google-search" # ruby
require "./search_api"


search_type = "web"
if ARGV.length >= 1
  if ARGV.length > 2
    if ARGV.pop == "type"
      search_type = ARGV.pop
    end
    query_string = ARGV.join(" ")
    print SearchApi.unique_slug_for(ARGV)
    SearchApi.new(query_string, search_type).run
    puts "\ndone."
  end
else
  puts "./#{$PROGRAM_NAME} <query string words>"
  puts "e.g. ./#{$PROGRAM_NAME} speaking so kids will listen"
end
