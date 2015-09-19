#!/usr/bin/env ruby

require "json"
require "uri"
# require "open-uri"
require "http/client"
# require "nokogiri"

class CardSearchItem
  getter :index, :page, :title, :content, :url
  getter :visible_url, :total_results
  getter :title_no_formatting, :cache_url, :gsearch_result_class, :unescaped_url, :other_options
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
  "##{@index} p#{@page}: #{@title}\n\t#{@content}\n\t#{@url}"
  end
end

class HtmlCardSearchResponse
  include Enumerable(CardSearchItem)

  getter :status
  getter :details
  property :raw
  getter :hash
  getter :items
  getter :estimated_count
  getter :page
  getter :size

  ##
  # Iterate each item with _block_.

  def each_item(&block)
    items.each { |item| yield(item) }
  end
  alias_method :each, :each_item


  # "Page 2 of about 859,000 results"
  #rs: "About 774,000 results"
  STAT_REGEXP = %r{Page (\d+) of [aA]bout ([\d\,\.]+) results}
  # PAGE_1_STAT_REGEXP = %r{About ([\d\,\.]+) results}
  getter :total_results
  def initialize(raw_html, options = {} of Symbol => Int32|String|Symbol|Nil)
    @details = nil
    max_pages = options.delete(:max_pages)
    if max_pages.is_a?(Int32)
      @max_pages = max_pages
    else
      @max_pages = 10
    end
    @page = 0
    @status = options.delete(:status)
    size = options.delete(:size)
    if size.is_a?(Symbol)
      @size = size
    else
      @size = :large
    end
    @items = [] of CardSearchItem|Nil
    @hash = {} of String => String
    if valid?
      @doc = Nokogiri::HTML.parse(raw_html)
      center = @doc.search(%{//div[@id="center_col"]})

      result_stats = center.search(%{//div[@id="resultStats"]}).text
      #puts "rs: #{result_stats.inspect}"
      @page, @total_results = parse(result_stats, STAT_REGEXP, prefix: "Page 1 of ")
      @page = @page.to_i
      #puts "p: #{@page.inspect}, t_r: #{@total_results.inspect}"

      results = center.search(%{//div[@id="search"]/div/ol/li})
      @estimated_count = results.count
      # Ah, ok:
      # invalid size, not large but 10
      # warn("invalid size, not #{@size} but #{@estimated_count}") unless @estimated_count == @size

      results.each_with_index do |r, idx|
        result_hash = {} of String => String|Int32|Nil
        a_tag = r.search("h3/a").first
        unbolded_text = a_tag.children.text
        result_hash["title"] = unbolded_text

        href = a_tag.attributes["href"].value
        uri = URI.parse(href)
        result_hash["url"] = uri.query[2..-2]

        uri = URI.parse(result_hash["url"])
        result_hash["visibleUrl"] = uri.host

        result_hash["content"] =
          if !r.search(%{*[@class="st"]}).first.nil?
            r.search(%{*[@class="st"]}).first.text
          elsif !r.search(%{*[@class="s"]}).first.nil?
            r.search(%{*[@class="s"]}).first.text
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

  def parse(string, regexp, options={} of Symbol => String)
    prefix = options[:prefix]
    matches = string.match(regexp)
    if !matches && prefix
      matches = "#{prefix}#{string}".match(regexp)
    end
    return matches ? matches.to_a[1..-1] : [] of Nil
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

  include Enumerable(HtmlCardSearchResponse)

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

  def self.run(options = {} of Symbol => String|Bool)
    new(options).run
  end

  def self.unique_slug_for(ary)
    str = ary.sort.join(" ")
    slugify(str)
  end

  def self.slugify(str)
    str && str.downcase.strip.tr(" ", "-").gsub(/[^\w-]/, "")
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

  getter :sent
  getter :options, :offset, :size, :language, :api_key, :version, :query
  getter :debug, :user_agent, :max_pages
  def initialize(options = {} of Symbol => Nil|Int32|String|Bool|Float32|Symbol)
    @debug = !!options.delete(:debug)
    @max_pages = options.delete(:max_pages) || 10
    user_agent = options.delete(:user_agent)
    if user_agent.is_a?(String)
      @user_agent = options.delete(:user_agent)
    else
      @user_agent = "Mozilla"
    end
    @version = options.delete(:version) || 1.0
    @type = DEFAULT_SEARCH_TYPE
    offset = options.delete(:offset)
    if offset.is_a?(Int32)
      @offset = offset
    else
      @offset = 0
    end

    @size = options.delete(:size) || :large
    @language = options.delete(:language) || :en
    query = options.delete(:query)
    if !!query && query.is_a?(String)
      @query = @query
    else
      @query = "find biology flashcards"
    end
    @target_site = options.delete(:target_site) || "www.brainscape.com"
    @api_key = options.delete(:api_key) || :notsupplied
    @options = options
    # yield(self) if block_given?
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

    item_list = [] of String
    each_item do |item|
      if item.total_results
        total_results = item.total_results
      end

      # log when we match on:
      if item.visible_url == @target_site
        found = item
      end

      #file.puts "#{item}\n"
      item_list << item.to_s

      "Return a String"
    end
    File.open(full_file_path, WRITE_MODE) { |file| file.puts item_list.join("\n") }

    puts found ? "found: #{found} on page #{found.page} out of #{total_results} total results" : "not found in #{total_results} total results"

    return found
  end

  def each_item(&block : CardSearchItem -> _)
    response = self.next.response
    found = nil
    if response && response.valid?
      response.each { |item| 
        yield(item as CardSearchItem)
        if item.visible_url == @target_site
          found = item
          return item
        end
      }
      each_item(&block) unless found
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
    response = HtmlCardSearchResponse.new(raw.body, { status: raw.status_code, size: size, max_pages: max_pages})
    # @each_response.call response if @each_response
    response
  end
  alias_method :response, :get_response


  # private

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
    if debug # && block_given?
      puts(yield)
    end
  end

  def get_raw
    @sent = true
    uri = get_uri
    log { "GET'ng #{uri.inspect}" }
    #open(uri, {"User-Agent" => @user_agent})
    #HTTP::Client.get(uri, {"User-Agent" => @user_agent})
    headers = HTTP::Headers { "User-Agent": @user_agent.to_s }
    HTTP::Client.get(uri, headers)
  end

  def get_uri
    URI + "?" + (get_search_uri_params + options.to_a).
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
end

if __FILE__ == $PROGRAM_NAME
  # require "optparse"
  require "option_parser"

  options = {action: "usage", debug: false}
  # opt_parser = OptionParser.new do |opts|
  OptionParser.parse! do |opts|
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

    opts.on("-h", "--help", "This help screen" ) do
      puts opts
      puts %{\n    e.g. #{$PROGRAM_NAME} --debug --run --query="find anatomy flashcards"}
      exit
    end
  end
  #opt_parser.parse!

  action = options.delete(:action)
  if "run" == action
    CardSearcher.run(options)
  else
    CardSearcher.usage
  end
end
