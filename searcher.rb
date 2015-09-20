#!/usr/bin/env ruby

require "json"
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


  # Page 1 says: "About 774,000 results"
  # Page 2 says: "Page 2 of about 859,000 results"
  STAT_REGEXP = %r{Page (\d+) of [aA]bout ([\d\,\.]+) results}
  attr_reader :total_results
  def initialize(raw_html, options={})
    raw_html = raw_html.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    @details = nil
    @max_pages = options.delete(:max_pages) || 10
    @page = 0
    @status = options.delete(:status)
    @size = (options.delete(:size) || :large).to_sym
    @items = []
    @hash = {}
    if valid?
      center = raw_html
      if center_match = raw_html.match(%r{<div[^>]+id="center_col"[^>]*>(.+)}m)
        center = center_match[1]
      end

      result_stats = center
      if result_stats_match = center.match(%r{<div[^>]+id="resultStats"[^>]*>([^<]+)<})
        result_stats = result_stats_match[1]
      end

      @page = -1
      @total_results = "unknown"

      matches = result_stats.match(STAT_REGEXP)
      if !matches
        matches = "Page 1 of #{result_stats}".match(STAT_REGEXP)
      end

      if matches && (3 >= matches.size)
        @page = matches[1].to_i
        @total_results = matches[2]
      end

      results_string = center
      if results_string_match = center.match(%r{<div[^>]+id="search"[^>]*>\s*<div[^>]+id="ires"[^>]*>\s*<ol[^>]*>(.+)</ol}m)
        results_string = results_string_match[1]
      end

      results = results_string.split(%r{<li[^>]+class="g"[^>]*>}).reject { |entry| entry.nil? || entry.empty? }
      _estimated_count = results.size
      if _estimated_count.is_a?(Numeric)
        @estimated_count = _estimated_count
      else
        @estimated_count = 10
      end

      results.each_with_index do |r, idx|
        result_hash = {} #of String => String|Int32|Nil
        href = ""
        title = "unknown title"
        href_title_match = r.match(%r{<h3[^>]+class="r"><a\s+href="([^"]+)"[^>]*>(.+?)</a></h3}m)
        if href_title_match && (3 >= href_title_match.size)
          href = href_title_match[1]
          title = href_title_match[2]
        end
        result_hash["title"] = title

        query = URI.parse(href).query
        if query && (query.size > 2)
          url = query[2..-1]
          result_hash["url"] = url
          new_uri_host = URI.parse(url).host
          result_hash["visibleUrl"] = new_uri_host
        end

        if st_matches = st_matches(r)
          result_hash["content"] = st_matches[2]
        elsif s_matches = s_matches(r)
          result_hash["content"] = s_matches[2]
        else
          puts %{\tunknown content\n\n}
          result_hash["content"] = "-"
        end

        result_hash["total_results"] = @total_results
        if @page
          result_hash["page"] = @page
          adjusted_page = @page.to_i - 1
          adjusted_idx = idx + 1
          previous_page_count = (@estimated_count || 10) * adjusted_page
          result_hash["index"] = adjusted_idx + previous_page_count
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

    if matches && (3 >= matches.size)
      return matches[1..2]
    else
      ["-1", "-1"]
    end
  end

  def valid?
    @page <= @max_pages && @status == 200
  end

  private

  def st_matches(regx)
    regx.match(%r{<([^>\s]+)[^\S>]+class="st"[^>]*>(.+)</\1}m)
  end
  def s_matches(regx)
    regx.match(%r{<([^>\s]+)[^\S>]+class="s"[^>]*>(.+)</\1}m)
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

  def self.run(options={})
    new(options).run
  end

  def self.full_file_path(slug)
    file_path = DEFAULT_FILE_PATH
    file_ext = DEFAULT_FILE_EXT
    file_name = FILE_PATTERN % [slug, file_ext]
    FULL_FILE_PATH_PATTERN % [file_path, FILE_SEPARATOR, file_name]
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
    # CGI.escape(string.to_s)
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
    @user_agent = options.delete(:user_agent)
    @version = options.delete(:version) || 1.0
    @type = DEFAULT_SEARCH_TYPE
    @offset = options.delete(:offset) || 0
    @size = options.delete(:size) || :large
    @language = options.delete(:language) || :en
    @query = options.delete(:query)
    @target_site = options.delete(:target_site)
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
    total_results = "0"

    item_list = [] #of String
    each_item do |item|
      if item.total_results
        total_results = item.total_results
      end

      if @target_site && item.visible_url == @target_site
        found = item
      end

      item_list << item.to_s

      "Return a String"
    end
    File.open(full_file_path, WRITE_MODE) { |file| file.puts item_list.join("\n\n") }

    puts found ? "\nOut of #{total_results} total results, found #{found.to_s}" : "\nNot found in the first #{@max_pages} pages of the #{total_results} total results"
    return found
  end

  def each_item &block
    response = self.next.response
    found = nil
    if response && response.valid?
      response.each { |item|
        yield(item)
        if @target_site && item.visible_url == @target_site
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
    response = HtmlCardSearchResponse.new(raw.read, status: raw.status.first.to_i, size: size, max_pages: max_pages)
    # @each_response.call response if @each_response
    response
  end
  alias_method :response, :get_response


  private

  def full_file_path
    unless @full_file_path
      @full_file_path = CardSearcher.full_file_path(slug)
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
    log { "curl -A #{@user_agent} -XGET #{uri.inspect}" }
    @user_agent.nil? ? open(uri) : open(uri, "User-Agent" => @user_agent)
  end

  def get_uri
    URI + "?" + (get_search_uri_params + options.to_a).
      map { |key, value| "#{key}=#{CardSearcher.url_encode(value)}" unless value.nil? }.compact.join("&")
  end

  # curl -A Mozilla 
  # https://www.google.com/search
  # ?q=find+biology+flashcards&
  # hl=en&
  # biw=1318&
  # bih=600&
  # ei=fJn8VePkGsesogSowLioBg&
  # start=10
  # &sa=N
  private def get_search_uri_params
    [[:start, offset.to_s],
     [:hl, language],
     [:q, query]]
  end
end

if __FILE__ == $PROGRAM_NAME
  require "optparse"
  program_name = File.basename(__FILE__, ".*")


  options = {debug: false}
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{program_name}.rb [OPTIONS]..."

    opts.on("-r", "--run", "Run") do
      options[:action] = "run"
    end

    opts.on("-u [USER_AGENT]", "--user_agent [USER_AGENT]", "User Agent") do |u|
      options[:user_agent] = u
    end

    opts.on("-m [MAX_PAGES]", "--max_pages [MAX_PAGES]", "Max Pages") do |m|
      options[:max_pages] = m.to_i
    end


    opts.on("-t [TARGET]", "--target_site [TARGET]", "Target Site") do |t|
      options[:target_site] = t
    end

    opts.on("-q [QUERY]", "--query [QUERY]", "Query") do |q|
      options[:query] = q
    end

    opts.on("-d", "--debug", "Debug Mode") do
      options[:debug] = true
    end

    opts.on_tail("-h", "--help", "This help screen" ) do
      puts opts
      puts %Q(\n    e.g. ruby #{program_name}.rb -d -r -u "Mozilla" -t "www.mycompany.com" --query="find anatomy flashcards")
      exit
    end
  end

  begin
    opt_parser.parse!
    mandatory = [:query, {action: "run"}]
    missing = mandatory.select{ |param|
      if param.respond_to?(:keys)
        param.keys.any? { |key| options[key] != param[key] }
      else
        options[param].nil?
      end
    }

    if missing.empty?
      options.delete(:action)
      CardSearcher.run(options)
    else
      warn %{Missing options: #{missing.join(", ")}}
      warn opt_parser
      exit
    end
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument
    warn $!.to_s
    warn opt_parser
    exit
  end
end
