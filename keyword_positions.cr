# crystal build keyword_positions.cr --release
# to encrypt json:
# gpg --encrypt --recipient "Jonathan Thomas" search_config.json
# to decrypt json:
# gpg --decrypt search_config.json.gpg > search_config.json
# ./keyword_positions --target_domain "brainscape.com" --run_from "./search_config.json"

require "json"
require "uri"
require "http/client"

class CardSearchItem
  getter :index, :page, :title, :content, :url
  getter :visible_url, :total_results
  getter :title_no_formatting, :cache_url, :gsearch_result_class, :unescaped_url, :other_options
  def initialize(item_hash, page, index, result_count)
    @index = index #item_hash.delete("index")
    @page = page # item_hash.delete("page")
    @title = item_hash.delete("title")
    @content = item_hash.delete("content")
    @url = item_hash.delete("url") || ""
    @total_results = result_count #item_hash.delete("total_results"

    @visible_url = item_hash.delete("visibleUrl") || ""

    @title_no_formatting = item_hash.delete("titleNoFormatting")
    @cache_url = item_hash.delete("cacheUrl")
    @gsearch_result_class = item_hash.delete("GsearchResultClass")
    @unescaped_url = item_hash.delete("unescapedUrl")
    @other_options =  item_hash
  end

  def to_s
    # "##{@index} page: #{@page}) #{@title}\n\t#{@content}\n\t#{@url}"
    "#{@url} at position: #{@index} on page: #{@page}\n\t\t#{@title}\n\t\t#{@content}"
  end
end

# prompt> curl "http://www.google.com/uds/GwebSearch?start=0&rsz=large&hl=en&key=notsupplied&v=1.0&q=flashcards&filter=1" | json_pp
# {
#   "responseData" : {
#      "results" : [
#         {
#            "cacheUrl" : "http://www.google.com/search?q=cache:FTjQbJiQcA4J:quizlet.com",
#            "content" : "Overview. <b>Flashcards</b>. Get started studying your terms and definitions in our main \n<b>Flashcards</b> mode. You can choose between two motions: Flip or Flow.",
#            "titleNoFormatting" : "Using Flashcards | Quizlet",
#            "GsearchResultClass" : "GwebSearch",
#            "visibleUrl" : "quizlet.com",
#            "unescapedUrl" : "https://quizlet.com/help/how-do-i-study-with-flashcard-mode",
#            "url" : "https://quizlet.com/help/how-do-i-study-with-flashcard-mode",
#            "title" : "Using <b>Flashcards</b> | Quizlet"
#         },
#         ....
#
#      ],
#      "cursor" : {
#         "searchResultTime" : "0.27",
#         "moreResultsUrl" : "http://www.google.com/search?oe=utf8&ie=utf8&source=uds&start=0&filter=1&hl=en&q=flashcards",
#         "estimatedResultCount" : "3940000",
#         "currentPageIndex" : 0,
#         "pages" : [
#            {
#               "label" : 1,
#               "start" : "0"
#            },
#            {
#               "label" : 2,
#               "start" : "8"
#            },
#            # ....
#            {
#               "start" : "56",
#               "label" : 8
#            }
#         ],
#         "resultCount" : "3,940,000"
#      }
#   },
#   "responseStatus" : 200,
#   "responseDetails" : null
#}
class CardSearchResponse
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

  def initialize(hash = {} of String => Int32|String|Symbol|Nil)
    # puts "GOT: #{hash.inspect}"
    @page = 0
    @hash = hash
    @size = :large
    @items = []  of CardSearchItem|Nil
    if hash["responseStatus"] && !hash["responseStatus"].is_a?(Symbol)
      @status = hash["responseStatus"].not_nil!.to_s.to_i
    else
      @status = 200
    end

    @details = hash["responseDetails"]
    if valid?
      response_data = hash["responseData"]
      if response_data && response_data.is_a?(Hash)
        if response_data["cursor"]
          cursor = response_data["cursor"]
          if cursor && cursor.is_a?(Hash)
            if cursor["estimatedResultCount"]
              @estimated_count = cursor["estimatedResultCount"].to_s.to_i
            end

            if cursor["resultCount"]
              @result_count = cursor["resultCount"].to_s
            end

            if cursor["currentPageIndex"]
              @page = cursor["currentPageIndex"].to_s.to_i
            end
          end
        end
        if response_data["results"]
          results = response_data["results"]
          if results && results.is_a?(Array)
            results.each_with_index do |result, i|
            if result && result.is_a?(Hash)
              index = 1 + i + CardSearcher.size_for(@size) * @page
              items << CardSearchItem.new(result, @page + 1, index, @result_count)
            end
          end
        end
        end
      end
    end
  end

  ##
  # Check if the response is valid.

  def valid?
    hash["responseStatus"] == 200
  end
end

class QueryAndPath
  json_mapping({
    target_path: String,
    query: String,
  })
  def to_h
   {target_path: target_path, query: query}
  end
end

class CardSearcher
  # URI = "http://www.google.com/search"
  URI = "http://www.google.com/uds/GwebSearch"
  WRITE_MODE = "w+"

  include Enumerable(CardSearchResponse)

  def self.log
    puts yield
  end

  def self.log_path
    time = Time.now
    year = sprintf("%02d", time.year).to_s
    month = sprintf("%02d", time.month).to_s
    day = sprintf("%02d", time.day).to_s

    "./keyword_positions_%s_%s_%s.log" % [year, month, day]
  end

  def self.search_paths(config_path)
    # SEARCH_PATHS
    text = File.read(config_path.to_s)
    ary = json_decode(text)
    if ary.is_a?(Array)
      return ary.map do |entry|
        QueryAndPath.from_json(entry.to_json).to_h
      end
    else
      Array(Hash(String, String)).new
    end
  end

  def self.run_from(options = {} of Symbol => String|Bool)
    config_path = options[:config] || "./search_config.json"
    messages = [] of String
    search_paths(config_path).each do |search_path_hash|
      #params = options.merge(search_path_hash)
      params = options.dup
      params[:query] = search_path_hash[:query]
      params[:target_path] = search_path_hash[:target_path]
      messages += run(params)
    end

    File.open(log_path, WRITE_MODE) do |file|
      messages.each do |message|
        file.puts message
      end
      messages.clear
    end
  end

  def self.run(options = {} of Symbol => String|Bool)
    new(options).run
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
    @messages = [] of String

    max_pages = options.delete(:max_pages)
    if max_pages.is_a?(String)
      @max_pages = max_pages
    else
      @max_pages = "few"
    end

    user_agent = options.delete(:user_agent)
    if user_agent.is_a?(String)
      @user_agent = user_agent
    end

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

  def run
    if @query.nil? || @query.not_nil!.empty?
      puts "FAIL"
      return ["no query"]
    end

    tee "\nSearching for #{@query}"
    found = false
    total_results = "0"

    item_list = [] of String
    each_item do |item|
      if item.total_results
        total_results = item.total_results
      end

      # log { "\trun) visible_url vs target_domain (#{item.visible_url.inspect} <=> #{@target_domain.inspect})" }
      # log { "\trun) url vs target_path (#{item.url.inspect} <=> #{@target_path.inspect})" }
      # if (@target_url && item.url == @target_url) || ((item.visible_url.is_a?(String) && @target_domain.is_a?(String) && item.visible_url.to_s.ends_with?(@target_domain.to_s)) && (item.url.is_a?(String) && @target_path.is_a?(String) && item.url.to_s.ends_with?(@target_path.to_s)))
      if (item.visible_url.is_a?(String) && @target_domain.is_a?(String) && item.visible_url.to_s.ends_with?(@target_domain.to_s))
        if (item.url.is_a?(String) && @target_path.is_a?(String) && item.url.to_s.ends_with?(@target_path.to_s))
          found = item
        else
          tee "\tOther #{item.url.inspect} (not: #{@target_path}) at index: #{item.index.inspect}\n"
        end
      end

      item_list << item.to_s

      "Return a String"
    end
    # File.open(full_file_path, WRITE_MODE) { |file| file.puts item_list.join("\n\n") }

    tee found ? "\tFound #{found.to_s} in #{total_results} total results" : %(\tUnable to find: #{@target_domain}#{@target_path} in #{total_results} total results.\n\tIn your terminal, enter:\n\t\topen "http://www.google.com/search?start=0&q=#{@query}")

    #return found
    return @messages
  end

  def each_item(&block : CardSearchItem -> _)
    response = self.next.response
    found = nil
    if response && response.valid?
      response.each { |item|
        block.call(item as CardSearchItem)
        # log { "\tei) visible_url vs target_domain (#{item.visible_url.inspect} <=> #{@target_domain.inspect})" }
        # log { "\tei) url vs target_path (#{item.url.inspect} <=> #{@target_path.inspect})" }
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
    json_hash = CardSearcher.json_decode(raw.body) # || {} of Symbol => Int32|String|Symbol|Nil
    if json_hash.is_a?(Hash) # of Symbol => Int32|String|Symbol|Nil)
      #options = json_hash.merge({ status: raw.status_code, size: size, max_pages: max_pages})
      response = CardSearchResponse.new(json_hash)
    end
    response
  end
  def response
    get_response
  end

  # private

  private def tee(message="")
    puts message
    @messages << message
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

"http://www.google.com/uds/GwebSearch?start=0&rsz=large&hl=en&key=notsupplied&v=1.0&q=flashcards&filter=1"
    # URI + "?" + (get_search_uri_params + options.to_a).map do |key_and_value|
  private def get_uri
    URI + "?" + (get_search_uri_params).map do |key_and_value|
      key = key_and_value.first
    value = key_and_value.last
    if value
      if :v == key
        "#{key}=1.0"
      else
        "#{key}=#{CardSearcher.url_encode(value)}"
      end
    end
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
     [:key, @api_key],
     [:hl, @language],
     [:filter, 1],
     [:rsz, @size],
     [:v, @version.to_s],
     [:q, query]]
  end
end

program_name = File.basename(__FILE__, ".*")
require "option_parser"


options = {debug: false} of Symbol => String|Bool|Int32

opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{program_name} [OPTIONS]..."

  opts.on("--run_from [CONFIG]", "Run From") do |c|
    options[:action] = "run_from"
    options[:config] = c
    options[:query] = ""
  end

  opts.on("-r", "--run", "Run") do
    options[:action] = "run"
  end

  opts.on("-u [USER_AGENT]", "--user_agent [USER_AGENT]", "User Agent") do |u|
    options[:user_agent] = u
  end

  opts.on("-m [MAX_PAGES]", "--max_pages [MAX_PAGES]", "Max Pages") do |m|
    options[:max_pages] = m.to_s #to_i
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
  elsif "run_from" == action
    CardSearcher.run_from(options)
  end
else
  puts %{Missing options: #{missing.join(", ")}}
  puts opt_parser
  exit
end
