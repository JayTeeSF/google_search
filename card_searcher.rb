#!/usr/bin/env ruby

require "json"
require "open-uri"

class CardSearchItem
  attr_reader :index, :page, :title, :content, :url
  attr_reader :visible_url
  attr_reader :title_no_formatting, :cache_url, :gsearch_result_class, :unescaped_url, :other_options
  def initialize(item_hash)
    @index = item_hash.delete('index')
    @page = item_hash.delete('page')
    @title = item_hash.delete('title')
    @content = item_hash.delete('content')
    @url = item_hash.delete('url')
    @visible_url = item_hash.delete('visibleUrl')

    @title_no_formatting = item_hash.delete('titleNoFormatting')
    @cache_url = item_hash.delete('cacheUrl')
    @gsearch_result_class = item_hash.delete('GsearchResultClass')
    @unescaped_url = item_hash.delete('unescapedUrl')
    @other_options =  item_hash
  end

  def to_s
  "##{@index} p#{@page}: #{@title}\n\t#{@content}\n\t#{@url}"
  end
end

class CardSearchResponse
  include Enumerable
  attr_reader :status
  attr_reader :details
  attr_accessor :raw
  attr_reader :hash
  attr_reader :items
  attr_reader :estimated_count
  attr_reader :page
  attr_reader :size

  def initialize hash
    @page = 0
    @hash = hash
    @size = (hash["responseSize"] || :large).to_sym
    @items = []
    @status = hash["responseStatus"]
    @details = hash["responseDetails"]
    if valid?
      if hash["responseData"].include? "cursor"
        @estimated_count = hash["responseData"]["cursor"]["estimatedResultCount"].to_i
        @page = hash["responseData"]["cursor"]["currentPageIndex"].to_i
      end
      @hash["responseData"]["results"].each_with_index do |result, i|
        # item_class = Google::Search::Item.class_for result["GsearchResultClass"]
        # "GsearchResultClass"=>"GwebSearch"
        result["page"] = page
        result["index"] = 1 + i + CardSearcher.size_for(size) * page
        # items << result #item_class.new(result)
        items << CardSearchItem.new(result)
      end
    end
  end

  ##
  # Iterate each item with _block_.

  def each_item &block
    items.each { |item| yield item }
  end
  alias_method :each, :each_item

  ##
  # Check if the response is valid.

  def valid?
    hash["responseStatus"] == 200
  end
end

class CardSearcher
  # URI = "https://www.google.com/search"
  URI = "http://www.google.com/uds"
  FILE_SEPARATOR = "/"
  DEFAULT_FILE_PATH = "."
  DEFAULT_FILE_EXT = "html"
  FILE_PATTERN = "%s.%s"
  FULL_FILE_PATH_PATTERN = "%s%s%s"
  WRITE_MODE = "w+"
  DEFAULT_SEARCH_TYPE = "web"

  include Enumerable

  def self.usage(_ignore)
    puts <<-END
Usage: #{$PROGRAM_NAME} [OPTIONS]...
    -r, --run                        Run
    -u, --user_agent [USER_AGENT]    User Agent
    -q, --query [QUERY]              Query
    -d, --debug                      Debug Mode
    -h, --help                       This help screen
    END
  end

  def self.run(options={})
    new(options).run
  end

  def self.unique_slug_for(ary)
    str = ary.sort.join(" ")
    slugify(str)
  end

  def self.slugify(str)
    str.downcase.strip.tr(" ", "-").gsub(/[^\w-]/, "")
  end

  def self.size_for sym
    # { small: 4, large: 10}[sym]
    { small: 4, large: 8, normal: 10}[sym]
  end

  def self.json_decode string
    JSON.parse string
  end

  def self.url_encode string
    string.to_s.gsub(/([^ a-zA-Z0-9_.-]+)/) {
      "%" + $1.unpack("H2" * $1.bytesize).join("%").upcase
    }.tr(" ", "+")
  end

  attr_reader :sent
  attr_reader :options, :offset, :size, :language, :api_key, :version, :query
  attr_reader :debug, :user_agent
  def initialize options = {}, &block
    @debug = !!options.delete(:debug)
    @user_agent = options.delete(:user_agent) || 'Mozilla'
    @version = options.delete(:version) || 1.0
    @type = DEFAULT_SEARCH_TYPE
    @offset = options.delete(:offset) || 0
    @size = options.delete(:size) || :large
    @language = options.delete(:language) || :en
    @query = options.delete(:query) || "find biology flashcards"
    @target_site = options.delete(:target_site) || "www.brainscape.com"
    @api_key = options.delete(:api_key) || :notsupplied
    @options = options
    yield self if block
  end

  def slug
    unless @slug
      @slug = "#{CardSearcher.slugify(@query)}_#{@type}"
    end
    @slug
  end

  def run
    log { "searching for #{@query}" }
    found = false

    File.open(full_file_path, WRITE_MODE) do |file|
      each do |item|
        # puts "#{item.inspect}\n"
        # stop & log when we match on:
        if item.visible_url == @target_site
          found = item
        end
        file.puts "#{item}\n"
      end
    end

    puts found ? "found: #{item}" : "not found"
    return found
  end

  def try_upto(max_tries, check_method=:valid?, rest_time=1, &block)
    return nil unless block_given?
    tries = max_tries

    result = block.call
    tries -= 1
    if tries > 0 && !result.send(check_method)
      sleep(rest_time)
      result = try_upto(tries, check_method, rest_time, &block)
    end
    result
  end

  def each_item &block
    response = self.next.response #try_upto(3) { self.next.response }
    if response && response.valid?
      response.each { |item| yield item }
      each_item(&block)
    end
  end
  alias_method :each, :each_item


  def all_items
    select { true }
  end
  alias_method :all, :all_items

  def get_hash(raw=nil)
    raw ||= get_raw
    CardSearcher.json_decode raw
  end

  def next
    @offset += CardSearcher.size_for(size) if sent
    self
  end

  def get_response
    raw = get_raw
    hash = get_hash(raw)
    hash["responseSize"] = size
    response = CardSearchResponse.new hash
    response.raw = raw
    # @each_response.call response if @each_response
    response
  end
  alias_method :response, :get_response


  private

  def full_file_path
    unless @full_file_path
      file_path = DEFAULT_FILE_PATH
      file_ext = DEFAULT_FILE_EXT
      file_name = FILE_PATTERN % [slug, file_ext]
      @full_file_path = FULL_FILE_PATH_PATTERN % [file_path, FILE_SEPARATOR, file_name]
    end

    return @full_file_path || "./some_file.html"
  end

  def log
    if debug && block_given?
      puts(yield)
    end
  end

  def get_raw
    @sent = true
    uri = get_uri
    log { "GET'ng #{uri.inspect}" }
    open(uri, "User-Agent" => @user_agent).read
  end

  def get_uri
    URI + "/G#{@type}Search?" +
       (get_uri_params + options.to_a).
    #URI + "?" + (get_search_uri_params + options.to_a).
      map { |key, value| "#{key}=#{CardSearcher.url_encode(value)}" unless value.nil? }.compact.join("&")
  end

  # curl -A Mozilla 
  # "https://www.google.com/search
  # ?q=find+biology+flashcards
  # &hl=en
  # &start=10 # page 2
  # 
  # https://www.google.com/search
  # ?q=find+biology+flashcards&
  # hl=en&
  # biw=1318&
  # bih=600&
  # ei=fJn8VePkGsesogSowLioBg&
  # start=10
  # &sa=N
  def get_search_uri_params
    [[:start, offset],
     [:hl, language],
     [:q, query]]
  end

  def get_uri_params
    [[:start, offset],
     [:rsz, size],
     [:hl, language],
     [:key, api_key],
     [:v, version],
     [:q, query]]
  end
end

if __FILE__ == $PROGRAM_NAME
  require "optparse"

  options = {action: "usage", debug: false }
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [OPTIONS]..."

    opts.on("-r", "--run", "Run") do
      options[:action] = "run"
    end

    opts.on("-u [USER_AGENT]", "--user_agent [USER_AGENT]", "User Agent") do |u|
      options[:user_agent] = u
    end

    opts.on("-q [QUERY]", "--query [QUERY]", "Query") do |q|
      options[:query] = q
    end

    opts.on("-d", "--debug", "Debug Mode") do
      options[:debug] = true
    end

    opts.on_tail("-h", "--help", "This help screen" ) do
      puts opts
      exit
    end
  end
  opt_parser.parse!

  action = options.delete(:action)
  if action
    CardSearcher.send(action, options)
  else
    CardSearcher.usage
  end
end
