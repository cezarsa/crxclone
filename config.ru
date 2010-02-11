require 'appengine-rack'
AppEngine::Rack.configure_app(
  :application => 'chromedbird',
  :version => 1)

require 'dupext'

run Sinatra::Application