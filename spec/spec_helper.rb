require 'dm-core'
require 'appengine-apis/logger'

DataMapper.setup(:default, "appengine://auto")

$logger = AppEngine::Logger.new

Dir['models/*.rb'].each do |model_file|
  require model_file
end