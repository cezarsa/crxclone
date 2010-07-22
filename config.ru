require 'appengine-apis/logger'
$logger = AppEngine::Logger.new

require 'crxclone'

=begin
configure :development do
  class Sinatra::Reloader < ::Rack::Reloader
    def safe_load(file, mtime, stderr)
      if File.expand_path(file) == File.expand_path(::Sinatra::Application.app_file)
        ::Sinatra::Application.reset!
        stderr.puts "#{self.class}: reseting routes"
      end
      super
    end
  end
  use Sinatra::Reloader
end
=end


run Sinatra::Application
