## What?
(hacked) google SEO-rank searcher

## Why?
You have a website
It has pages
You want those pages to show-up in search results (preferrably the first
page)

And you realize the only way to improve something is to first measure
it.

This program simply helps you see where your site's first-page shows-up in the results for whatever search you specify

## Woah...
IANAL, but proceed with caution: use this software at your own risk. Just assume
it's as likely to melt your machine as it is to do whatever I say below.

# Setup

#### [Option 1] Build the binary (i.e. from this source)
```
crystal build searcher.cr --release
```

#### [Option 2] Download the binary & chmod it...
```
visit: https://github.com/JayTeeSF/google_search/blob/master/searcher?raw=true

In your terminal (after holding-down cmd-spacebar and entering: "terminal")
cd ~/Downloads      # navigate to where you downloaded it
chmod +x ./searcher # make it executable
```

#### [Option 3] Use the Ruby version of the searcher
Instead of `./searcher`, as per below, you'll use `ruby ./searcher.rb`
[setting-up ruby is an exercise for the reader]

### Action

#### Without any options it fails due to any missing required-param(s):
```
↪ ./searcher
Missing hash key: :query (KeyError)
[4341694773] *Hash(Symbol, String | Int32 | Bool)@Hash(K, V)#[]<Hash(Symbol, String | Int32 | Bool), Symbol>:(String | Int32 | Bool) +773
[4341637680] __crystal_main +10112
[4341672635] main +43
```

#### Check the Help to figure it out:
```
↪ ./searcher --help
Usage: searcher.cr [OPTIONS]...
    -r, --run                                  Run
    -u [USER_AGENT], --user_agent [USER_AGENT] User Agent
    -m [MAX_PAGES],  --max_pages [MAX_PAGES]   Max Pages
    -t [TARGET],     --target_site [TARGET]    Target Site
    -q [QUERY],      --query [QUERY]           Query
    -d,              --debug                   Debug Mode
    -h,              --help                    This help screen

    e.g. searcher.cr -d -m 10 -r -u "Mozilla" -t "www.mycompany.com" --query="find anatomy flashcards"
```

#### Run it:
```
↪ ./searcher --debug --max_pages 10 --run --user_agent "Mozilla" --target_site "www.outofnowhere.net" --query="your search terms"
searching for your search terms
curl -A  -XGET "http://www.google.com/search?start=0&hl=en&q=your%20search%20terms"
	unknown content on page 1

curl -A  -XGET "http://www.google.com/search?start=10&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=20&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=30&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=40&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=50&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=60&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=70&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=80&hl=en&q=your%20search%20terms"
curl -A  -XGET "http://www.google.com/search?start=90&hl=en&q=your%20search%20terms"

Out of 3,450,000,000 total results, found #100 page: 10) Out of Nowhere | SELECTING <b>SEARCH TERMS</b>
	Aside from popularity, having a site FULL of rich text is the MOST IMPORTANT <br>
thing you can do to ensure the best natural ranking in the <b>search</b> engines for <b>your</b><br>
&nbsp;...
	http://www.outofnowhere.net/planning-your-website-selecting-search-terms/&amp;sa=U&amp;ved=0CEcQFjAJOFpqFQoTCKiH9OWthsgCFZYpiAodwJkP6A&amp;usg=AFQjCNHWjRh_YiPEi_hE912MNNGtWUkveQ
```

#### Review the results:
At this point you'll also have a file on your filesystem with a log of the results, e.g.:
```
↪ more your-search-terms_web.html
#1 page: 1) Understanding the <b>Search terms</b> report - AdWords Help
        Use the <b>Search terms</b> report to see how <b>your</b> ads performed when triggered by <br>
actual <b>searches</b> within the <b>Search</b> Network. Identify new <b>search terms</b> with high&nbsp;...
        https://support.google.com/adwords/answer/2472708%3Fhl%3Den&amp;sa=U&amp;ved=0CBQQFjAAahUKEwj_qOOjmobIAhVWNogKHeQNAdE&amp;usg=AFQjCNFHR_hKoraCdnZSUcv1YXg49Fhimw

#2 page: 1) <b>Search terms</b> report - AdWords Help - the Google Help Center
        A list of <b>search terms</b> that people have used before seeing <b>your</b> ad and clicking it. <br>
....
```

### TO-DONE:
  A Ruby Nokogiri-based solution
  Switch to Regex's (Chomsky who?)
    Why?  Famous Last Words: "Because we're parsing for simple patterns from pages with a consistent format"

  Generate a binary that anyone (i.e. non-rubyists) can use (the real reason for removing the Nokogiri dependency)
