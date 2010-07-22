require 'dm-core'
require 'lib/packer'
require 'json'

class CachedExtension
  include DataMapper::Resource
  property :id, Serial
  property :version, String
  property :packed_data, Blob

  property :name, String
  property :description, String
  property :icon, Blob

  belongs_to :extension

  def packer
    @packer ||= Packer.new(self.packed_data)
  end
  
  def update_cached_data(data)
    self.packed_data = data
    manifest = JSON.parse(packer['manifest.json'])
    self.name = get_manifest_entry(manifest, 'name')
    self.description = get_manifest_entry(manifest, 'description')
    
    icons = manifest['icons']
    # getting the biggest icon available
    icon_filename = icons[icons.keys.map { |k| k.to_i }.max.to_s]
    self.icon = packer[icon_filename]
  end
  
private

  def get_manifest_entry(manifest, entry)
    entry_value = manifest[entry]
    return unless entry_value
    if entry_value =~ /^__MSG_(.*)__$/
      get_i18n_entry($1, manifest['default_locale'])
    else
      entry_value
    end
  end
  
  def get_i18n_entry(entry, locale)
    file_entry = packer['_locales/' + locale + '/messages.json']
    json_data = JSON.parse(file_entry)
    if entry_value = json_data[entry]
      entry_value['message']
    end
  end
end