(hacked) google SEO-rank searcher

See where your site's first-page shows-up in search results
DONE:
  A Ruby Nokogiri-based solution
  Switch to Regex's (Chomsky who?)
    Why?  Famous Last Words: "Because we're parsing for simple patterns from pages with a consistent format"

  Generate a binary that anyone (i.e. non-rubyists) can use (the real reason for removing the Nokogiri dependency)

```
crystal build searcher.cr --release
./searcher --debug --max_pages 10 --run --user_agent "Mozilla" --target_site "www.some-company.com" --query="your search terms"

running with: {:debug => true, :action => "run", :user_agent => "Mozilla", :target_site => "www.some-company.com", :query => "your search terms"}
searching for your search terms
curl -A  -XGET "http://www.google.com/search?start=0&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=10&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=20&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=30&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=40&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=50&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=60&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=70&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=80&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=90&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=100&hl=en&q=your%20search%20terms"
not found in 3,630,000,000 total results
```
