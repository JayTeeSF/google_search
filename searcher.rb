#!/usr/bin/env ruby

require "json"
require "nokogiri"
require "uri"
require "open-uri"

class CardSearchItem
  attr_reader :index, :page, :title, :content, :url
  attr_reader :visible_url, :total_results
  attr_reader :title_no_formatting, :cache_url, :gsearch_result_class, :unescaped_url, :other_options
  def initialize(item_hash)
    @index = item_hash.delete("index")
    @page = item_hash.delete("page")
    @title = item_hash.delete("title")
    @content = item_hash.delete("content")
    @url = item_hash.delete("url")
    @total_results = item_hash.delete("total_results")

    @visible_url = item_hash.delete("visibleUrl")

    @title_no_formatting = item_hash.delete("titleNoFormatting")
    @cache_url = item_hash.delete("cacheUrl")
    @gsearch_result_class = item_hash.delete("GsearchResultClass")
    @unescaped_url = item_hash.delete("unescapedUrl")
    @other_options =  item_hash
  end

  def to_s
  "##{@index} page: #{@page}) #{@title}\n\t#{@content}\n\t#{@url}"
  end
end

class HtmlCardSearchResponse
  include Enumerable
  attr_reader :status
  attr_reader :details
  attr_accessor :raw
  attr_reader :hash
  attr_reader :items
  attr_reader :estimated_count
  attr_reader :page
  attr_reader :size

  def each_item &block
    items.each { |item| yield item }
  end
  alias_method :each, :each_item


  # "Page 2 of about 859,000 results"
  #rs: "About 774,000 results"
  STAT_REGEXP = %r{Page (\d+) of [aA]bout ([\d\,\.]+) results}
  attr_reader :total_results
  def initialize(raw_html, options={})
    @details = nil
    @max_pages = options.delete(:max_pages) || 10
    @page = 0
    @status = options.delete(:status)
    @size = (options.delete(:size) || :large).to_sym
    @items = []
    @hash = {}
    if valid?
      @doc = Nokogiri::HTML(raw_html)
      center = @doc.search(%Q{//div[@id="center_col"]})

      result_stats = center.search(%Q{//div[@id="resultStats"]}).text
      @page, @total_results = parse(result_stats, STAT_REGEXP, prepend: "Page 1 of ")
      @page = @page.to_i

      results = center.search(%Q{//div[@id="search"]/div/ol/li})
      @estimated_count = results.count

      results.each_with_index do |r, idx|
        result_hash = {}
        a_tag = r.search("h3/a").first
        unbolded_text = a_tag.children.text
        result_hash["title"] = unbolded_text

        href = a_tag.attributes["href"].value
        uri = URI.parse(href)
        result_hash["url"] = uri.query[2..-2]

        uri = URI.parse(result_hash["url"])
        result_hash["visibleUrl"] = uri.host

        result_hash["content"] =
          if !r.search(%Q{*[@class="st"]}).first.nil?
            r.search(%Q{*[@class="st"]}).first.text
          elsif !r.search(%Q{*[@class="s"]}).first.nil?
            r.search(%Q{*[@class="s"]}).first.text
          else
            warn "unknown content in 'r':\n#{r.to_html}\n\n"
            "-"
          end

        result_hash["total_results"] = @total_results
        if @page
          result_hash["page"] = @page
          result_hash["index"] = 1 + idx + @estimated_count * @page
        else
          warn "missing page: result_hash: #{result_hash}"
        end
        items << CardSearchItem.new(result_hash)
      end
    end
  end

  def parse(string, regexp, options={})
    prepend = options[:prepend]
    matches = string.match(regexp)
    if !matches && prepend
      matches = "#{prepend}#{string}".match(regexp)
    end
    return matches ? matches.to_a[1..-1] : []
  end

  def valid?
    @page <= @max_pages && @status == 200
  end
end

class CardSearcher
  URI = "http://www.google.com/search"
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

    e.g. #{$PROGRAM_NAME} --debug --run --query="find anatomy flashcards"
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
    { small: 4, large: 10}[sym]
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
  attr_reader :debug, :user_agent, :max_pages
  def initialize options = {}, &block
    @debug = !!options.delete(:debug)
    @max_pages = options.delete(:max_pages) || 10
    @user_agent = options.delete(:user_agent) || "Mozilla"
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
    total_results = 0

    # This file is not a cache.
    # It is simply a log of the current search results
    # for analysis
    # It will be overwritten
    File.open(full_file_path, WRITE_MODE) do |file|
      each do |item|
        if item.total_results
          total_results = item.total_results
        end
        file.puts "#{item}\n"
        # stop & log when we match on:
        if item.visible_url == @target_site
          found = item
          break
        end
      end
    end

    puts found ? "page #{found.page} out of #{total_results} total results found #{found}" : "not found in #{total_results} total results"
    return found
  end

  def each_item &block
    response = self.next.response
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

  def next
    @offset += CardSearcher.size_for(size) if sent
    self
  end

  def get_response
    raw = get_raw
    response = HtmlCardSearchResponse.new(raw.read, status: raw.status.first.to_i, size: size, max_pages: max_pages)
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
    open(uri, "User-Agent" => @user_agent)
  end

  def get_uri
    URI + "?" + (get_search_uri_params + options.to_a).
      map { |key, value| "#{key}=#{CardSearcher.url_encode(value)}" unless value.nil? }.compact.join("&")
  end

  def get_search_uri_params
    [[:start, offset],
     [:hl, language],
     [:q, query]]
  end
end

if __FILE__ == $PROGRAM_NAME
  require "optparse"

  options = {action: "usage", debug: false}
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
      puts %Q(\n    e.g. #{$PROGRAM_NAME} --debug --run --query="find anatomy flashcards")
      exit
    end
  end
  opt_parser.parse!

  action = options.delete(:action)
  if "run" == action
    CardSearcher.run(options)
  else
    CardSearcher.usage
  end
end
