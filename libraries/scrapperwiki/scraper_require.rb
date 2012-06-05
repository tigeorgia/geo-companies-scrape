require 'net/http'

Kernel.class_eval do
  alias_method :__old_require, :require

  def require(path, *args)
    __old_require(path, *args)
  rescue LoadError
    if matches = path.match( /^scrapers?\/(?<name>.+)/ )
      name = matches[:name]
      code = fetch_code name
      modd = Module.new
      begin
        modd.module_eval code
      rescue SyntaxError
        raise LoadError
      end
      self.class.send :include, modd
    else
      raise
    end
  end
end

def fetch_code(scraper_name)
  uri = URI("https://scraperwiki.com/editor/raw/#{scraper_name}")
  Net::HTTP.start uri.host, uri.port, use_ssl: true,
    verify_mode: OpenSSL::SSL::VERIFY_NONE do |http|
    resp = http.get(uri.request_uri)
    return resp.body
  end
end
