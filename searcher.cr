# crystal build searcher.cr --release
# ./searcher -d -m 10 -r -u "Mozilla" --target_domain "www.brainscape.com" --query="biology flashcards"
# ./searcher --user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/601.1.56 (KHTML, like Gecko) Version/9.0 Safari/601.1.56" --run_all --debug

require "json"
require "uri"
require "http/client"

class CardSearchItem
  getter :index, :page, :title, :content, :url
  getter :visible_url, :total_results
  getter :title_no_formatting, :cache_url, :gsearch_result_class, :unescaped_url, :other_options
  def initialize(item_hash)
    @index = item_hash.delete("index")
    @page = item_hash.delete("page")
    @title = item_hash.delete("title")
    @content = item_hash.delete("content")
    @url = item_hash.delete("url") || ""
    @total_results = item_hash.delete("total_results")

    @visible_url = item_hash.delete("visibleUrl") || ""

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

  def each_item(&block : CardSearchItem -> _)
    items.each { |item| item && block.call(item) }
  end
  def each(&block : CardSearchItem -> _)
    each_item(&block)
  end


  # Page 1 says: "About 774,000 results"
  # Page 2 says: "Page 2 of about 859,000 results"
  STAT_REGEXP = %r{Page (\d+) of [aA]bout ([\d\,\.]+) results}
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
      if _estimated_count.is_a?(Int32)
        @estimated_count = _estimated_count
      else
        @estimated_count = 10
      end

      results.each_with_index do |r, idx|
        result_hash = {} of String => String|Int32|Nil
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
          puts %{\tunknown content on page #{@page.inspect}\n\n}
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
          puts "missing page: result_hash: #{result_hash}"
        end
        items << CardSearchItem.new(result_hash)
      end
    end
  end

  def parse(string, regexp, options={} of Symbol => String)
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

  # private

  private def st_matches(regx)
    regx.match(%r{<([^>\s]+)[^\S>]+class="st"[^>]*>(.+)</\1}m)
  end
  private def s_matches(regx)
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
  SEARCH_PATHS = [
    {target_domain: "brainscape.com", query: "flashcards", target_path: "/"},
    {target_domain: "brainscape.com", query: "Spanish flashcards", target_path: "/learn/spanish"},
    {target_domain: "brainscape.com", query: "Learn Anatomy", target_path: "/subjects/anatomy"},
    {target_domain: "brainscape.com", query: "Learn Biology", target_path: "/subjects/biology"},
    {target_domain: "brainscape.com", query: "CPA Exam Prep", target_path: "/subjects/cpa"},
    {target_domain: "brainscape.com", query: "Learn to Speak German", target_path: "/subjects/german"},
    {target_domain: "brainscape.com", query: "Bible Study", target_path: "/subjects/bible"},
    {target_domain: "brainscape.com", query: "Bar Exam Prep", target_path: "/subjects/bar-exam"},
    {target_domain: "brainscape.com", query: "Study Real Estate", target_path: "/subjects/real-estate"},
    {target_domain: "brainscape.com", query: "NCLEX Prep", target_path: "/subjects/nclex"},
    {target_domain: "brainscape.com", query: "Series 66 Exam Prep", target_path: "/subjects/series%2066"},
    {target_domain: "brainscape.com", query: "AP Chemistry Flashcards", target_path: "/subjects/chemistry"},
    {target_domain: "brainscape.com", query: "AP U.S. History Exam", target_path: "/learn/ap-us-history"},
    {target_domain: "brainscape.com", query: "GRE Psychology Prep", target_path: "/learn/gre-psychology"},
    {target_domain: "brainscape.com", query: "GRE Vocabulary Flashcards", target_path: "/learn/gre-vocabulary"},
    {target_domain: "brainscape.com", query: "MCAT Test Prep", target_path: "/learn/mcat"},
    {target_domain: "brainscape.com", query: "SAT Prep", target_path:  "/learn/sat-prep"},
    {target_domain: "brainscape.com", query: "Series 7 Exam", target_path: "/learn/series-7-exam"},
    {target_domain: "brainscape.com", query: "Learn French", target_path: "/learn/french"},
    {target_domain: "brainscape.com", query: "Learn Spanish", target_path:  "/learn/spanish"},
    {target_domain: "brainscape.com", query: "Learn Chinese", target_path: "/learn/chinese-(mandarin)"},
    {target_domain: "brainscape.com", query: "Bartending Flashcards", target_path: "/learn/bartending"},
    {target_domain: "brainscape.com", query: "Vocab Builder", target_path: "/learn/vocab-builder"}
  ]

  include Enumerable(HtmlCardSearchResponse)

  def self.log
    puts yield
  end

  def self.run_all(options = {} of Symbol => String|Bool)
    SEARCH_PATHS.each do |search_path_hash|
      params = options.merge(search_path_hash)
      # log { "params: #{params.inspect}" }
      run(params)
    end
  end

  def self.run(options = {} of Symbol => String|Bool)
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
    CGI.escape(string.to_s)
  end

  getter :sent
  getter :options, :offset, :size, :language, :api_key, :version, :query
  getter :debug, :user_agent, :max_pages
  def initialize(options = {} of Symbol => Nil|Int32|String|Bool|Float32|Symbol)
    @debug = !!options.delete(:debug)

    max_pages = options.delete(:max_pages)
    if max_pages.is_a?(Int32)
      @max_pages = max_pages
    else
      @max_pages = 10
    end

    user_agent = options.delete(:user_agent)
    if user_agent.is_a?(String)
      @user_agent = user_agent
    end
    @type = DEFAULT_SEARCH_TYPE

    version = options.delete(:version)
    if version.is_a?(Float32)
      @version = version
    else
      @version = 1.0
    end

    offset = options.delete(:offset)
    if offset.is_a?(Int32)
      @offset = offset
    else
      @offset = 0
    end

    size = options.delete(:size)
    if size.is_a?(Symbol)
      @size = size
    else
      @size = :large
    end

    language = options.delete(:language)
    if language.is_a?(Symbol)
      @language = language
    else
      @language = :en
    end

    query = options.delete(:query)
    if query.is_a?(String)
      @query = query
    end

    target_url = options.delete(:target_url)
    if target_url.is_a?(String)
      @target_url = target_url
    end

    target_path = options.delete(:target_path)
    if target_path.is_a?(String)
      @target_path = target_path
    end

    target_domain = options.delete(:target_domain)
    if target_domain.is_a?(String)
      @target_domain = target_domain
    end

    api_key = options.delete(:api_key)
    if api_key.is_a?(String)
      @api_key = api_key
    else
      @api_key = :notsupplied
    end
    @options = options
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

    item_list = [] of String
    each_item do |item|
      if item.total_results
        total_results = item.total_results
      end

      log { "\trun) visible_url vs target_domain (#{item.visible_url.inspect} <=> #{@target_domain.inspect})" }
      log { "\trun) url vs target_path (#{item.url.inspect} <=> #{@target_path.inspect})" }
      if (@target_url && item.url == @target_url) || ((item.visible_url.is_a?(String) && @target_domain.is_a?(String) && item.visible_url.to_s.ends_with?(@target_domain.to_s)) && (item.url.is_a?(String) && @target_path.is_a?(String) && item.url.to_s.ends_with?(@target_path.to_s)))
        found = item
      end

      item_list << item.to_s

      "Return a String"
    end
    File.open(full_file_path, WRITE_MODE) { |file| file.puts item_list.join("\n\n") }

    puts found ? "\nOut of #{total_results} total results, found #{found.to_s}" : "\nNot found in the first #{@max_pages} pages of the #{total_results} total results"
    return found
  end

  def each_item(&block : CardSearchItem -> _)
    response = self.next.response
    found = nil
    if response && response.valid?
      response.each { |item|
        block.call(item as CardSearchItem)
        log { "\tei) visible_url vs target_domain (#{item.visible_url.inspect} <=> #{@target_domain.inspect})" }
        log { "\tei) url vs target_path (#{item.url.inspect} <=> #{@target_path.inspect})" }
        if (@target_url && item.url == @target_url) || ((item.visible_url.is_a?(String) && @target_domain.is_a?(String) && item.visible_url.to_s.ends_with?(@target_domain.to_s)) && (item.url.is_a?(String) && @target_path.is_a?(String) && item.url.to_s.ends_with?(@target_path.to_s)))
          found = item
          return item
        end
      }
      each_item(&block) unless found
    end
  end
  def each(&block : CardSearchItem -> _)
    each_item(&block)
  end


  def all_items
    select { true }
  end
  def all
    all_items
  end

  def next
    @offset += CardSearcher.size_for(size) if sent
    self
  end

  def get_response
    raw = get_raw
    response = HtmlCardSearchResponse.new(raw.body, { status: raw.status_code, size: size, max_pages: max_pages})
    response
  end
  def response
    get_response
  end

  # private

  private def full_file_path
    unless @full_file_path
      @full_file_path = CardSearcher.full_file_path(slug)
    end

    return @full_file_path || "./some_file.html"
  end

  private def log
    if debug
      puts yield
    end
  end

  private def get_raw
    @sent = true
    uri = get_uri
    log { "curl -A #{@user_agent.inspect} -XGET #{uri.inspect}" }
    headers = HTTP::Headers { "User-Agent": @user_agent.to_s }
    @user_agent.nil? ? HTTP::Client.get(uri) : HTTP::Client.get(uri, headers)
  end

  private def get_uri
    URI + "?" + (get_search_uri_params + options.to_a).map do |key_and_value|
      key = key_and_value.first
    value = key_and_value.last
    "#{key}=#{CardSearcher.url_encode(value)}" unless value.nil?
    end.compact.join("&")
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
     #[:hl, language],
     [:q, query]]
  end
end

program_name = File.basename(__FILE__, ".*")
require "option_parser"


options = {debug: false} of Symbol => String|Bool|Int32

opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{program_name} [OPTIONS]..."

  opts.on("--run_all", "Run All") do
    options[:action] = "run_all"
    options[:query] = ""
  end

  opts.on("-r", "--run", "Run") do
    options[:action] = "run"
  end

  opts.on("-u [USER_AGENT]", "--user_agent [USER_AGENT]", "User Agent") do |u|
    options[:user_agent] = u
  end

  opts.on("-m [MAX_PAGES]", "--max_pages [MAX_PAGES]", "Max Pages") do |m|
    options[:max_pages] = m.to_i
  end

  opts.on("--target_url [TARGET]", "Target Url") do |u|
    options[:target_url] = u
  end

  opts.on("--target_path [TARGET]", "Target Path") do |p|
    options[:target_path] = p
  end

  opts.on("--target_domain [TARGET]", "Target Domain") do |d|
    options[:target_domain] = d
  end

  opts.on("-q [QUERY]", "--query [QUERY]", "Query") do |q|
    options[:query] = q
  end

  opts.on("-d", "--debug", "Debug Mode") do
    options[:debug] = true
  end

  opts.on("-h", "--help", "This help screen" ) do
    puts opts
    puts %{\n    e.g. #{program_name} -d -m 10 -r -u "Mozilla" -t "www.mycompany.com" --query="find anatomy flashcards"}
    exit
  end
end
opt_parser.parse!

# mandatory = [:query, {action: "run"}]
mandatory = [:query, :action]
missing = mandatory.select{ |param|
  if param.is_a?(Hash)
    param.keys.any? { |key| options[key] != param[key] }
  else
    options[param].nil?
  end
}

if missing.empty?
  action = options.delete(:action)
  if "run" == action
    CardSearcher.run(options)
  elsif "run_all" == action
    CardSearcher.run_all(options)
  end
else
  puts %{Missing options: #{missing.join(", ")}}
  puts opt_parser
  exit
end
