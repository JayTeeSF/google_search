class SearchApi
  FILE_SEPARATOR = "/"
  DEFAULT_FILE_PATH = "."
  DEFAULT_FILE_EXT = "html"
  FILE_PATTERN = "%s.%s"
  FULL_FILE_PATH_PATTERN = "%s%s%s"
  WRITE_MODE = "w+"
  IMAGE_LINK_FORMAT = "<img src=\"%s\" />"
  URL_LINK_FORMAT = "<a href=\"%s\">%s</a>"

  DEFAULT_SEARCH_TYPE = "web"

  SEARCH_CLASS_FOR = {
    "web" => Google::Search::Web,
    "video" => Google::Search::Video,
    "image" => Google::Search::Image,
    "news" => Google::Search::News,
    "blog" => Google::Search::Blog,
    "book" => Google::Search::Book,
    "local" => Google::Search::Local,
    "patent" => Google::Search::Patent
  }

  def self.unique_slug_for(ary)
    str = ary.sort.join(" ")
    slugify(str)
  end

  def self.slugify(str)
    str.downcase.strip.tr(" ", "-").gsub(/[^\w-]/, "")
  end

  def initialize(query_string, search_type = nil)
    @query_string = query_string
    @search_type = !!search_type ? search_type.downcase : DEFAULT_SEARCH_TYPE
  end

  def run
    #File.open("some_file.html", WRITE_MODE) do |file|
    File.open(full_file_path, WRITE_MODE) do |file|
      file.puts "<ul>"
      search.each do |item|
        file.puts "<li> #{item.index}) #{link_for(item.uri, item.title)} </li>"
      end
      file.puts "total: #{search.count} <br />"
      file.puts "</ul>"
    end
  end

  def searcher_class
    unless @searcher_class
      @searcher_class = SEARCH_CLASS_FOR[@search_type]
    end
    @searcher_class
  end

  def search
    unless @search
      @search = searcher_class.new(query: @query_string)
    end
    @search
  end

  # one day this should be a user-suppiled option
  def slug
    unless @slug
      @slug = "#{SearchApi.slugify(@query_string)}_#{@search_type}"
    end
    @slug
  end

  def constantize(class_name)
    class_name.classify
  end

  # => #<Google::Search::Image:0x007fafbe052ba0 @color=nil, @image_size=nil, @image_type=nil, @file_type=nil, @safety_level=nil, @type=:image, @version=1.0, @offset=0, @size=:large, @language=:en, @query="examples of checkmate", @api_key=:notsupplied, @options={}>
  def full_file_path
    unless @full_file_path
      file_path = DEFAULT_FILE_PATH
      file_ext = DEFAULT_FILE_EXT
      file_name = FILE_PATTERN % [slug, file_ext]
      @full_file_path = FULL_FILE_PATH_PATTERN % [file_path, FILE_SEPARATOR, file_name]
    end

    return @full_file_path || "./some_file.html"
  end

  def link_for(item, title)
    case @search_type
    when item
      IMAGE_LINK_FORMAT % [item, title]
    else
      URL_LINK_FORMAT % [item, title]
    end
  end
end
