require 'dm-core'
require 'json'

class NoCacheDataFoundError < StandardError
end

class UpdateInfo
  attr_accessor :update, :download_url, :version
  def update?
    update
  end
end

class ExtensionClone
  include DataMapper::Resource
  property :id, Serial
  property :generated_key, Blob
  property :generated_id, String
  property :last_update_request, DateTime
  property :created_at, DateTime

  belongs_to :extension

  REQUEST_UPDATE_URL = 'http://crxclone.appspot.com/cloned_extension/request_update'
  DOWNLOAD_URL = 'http://crxclone.appspot.com/cloned_extension/'

  #REQUEST_UPDATE_URL = 'http://localhost:8080/cloned_extension/request_update'
  #DOWNLOAD_URL = 'http://localhost:8080/cloned_extension/'

  def pack_clone
    cached = extension.cached_extension
    raise NoCacheDataFoundError if cached.nil?

    data = nil

    retry_count = 4
    while retry_count > 0
      # Let's try more then once due to some
      # weird JRuby reflection errors.
      begin
        @packer = cached.packer
        if self.generated_key
          @packer.set_key(self.generated_key)
        else
          self.generated_key, self.generated_id = @packer.generate_key
          save
        end
        update_manifest

        data = @packer.pack
        break
      rescue
        retry_count -= 1
      end
    end

    data
  end

  def request_update(received_version)
    self.last_update_request = DateTime.now
    save

    most_recent_version = extension.check_and_update!

    update_info = UpdateInfo.new
    update_info.update = received_version != most_recent_version
    update_info.download_url = DOWNLOAD_URL + self.generated_id
    update_info.version = most_recent_version
    update_info
  end

private

  def update_manifest
    manifest = JSON.parse(@packer['manifest.json'])

    replace_manifest_entry(manifest, 'name', '{entry} (Clone)')
    replace_manifest_entry(manifest, 'description', "{entry} (Cloned from https://chrome.google.com/extensions/detail/#{extension.extension_id})")
    replace_manifest_entry(manifest, 'update_url', REQUEST_UPDATE_URL)

    @packer['manifest.json'] = JSON.generate(manifest)
  end
  
  def replace_manifest_entry(manifest, entry, new_value)
    entry_value = manifest[entry]
    return unless entry_value
    if entry_value =~ /^__MSG_(.*)__$/
      update_i18n_files($1, new_value)
    else
      manifest[entry] = new_value.gsub(/{entry}/, entry_value)
    end
  end

  def update_i18n_files(entry, new_value)
    @packer.each do |e|
      if e.name =~ /^_locales.*messages\.json$/
        json_data = JSON.parse(e.data)
        if entry_value = json_data[entry]
          json_data[entry]['message'] = new_value.gsub(/{entry}/, entry_value['message'])
          e.data = JSON.generate(json_data)
        end
      end
    end
  end
end