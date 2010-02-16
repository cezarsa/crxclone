require 'dm-core'

class CachedExtension
  include DataMapper::Resource
  property :id, Serial
  property :version, String
  property :packed_data, Blob, :lazy => true

  belongs_to :extension
end