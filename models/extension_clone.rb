require 'dm-core'
require 'WEB-INF/lib/jopenssl.jar'
require 'json'
require 'java'

class ZipEntry
  attr_accessor :name, :data, :is_directory
  def initialize
    @is_directory = false
    @data = ''
  end
  def directory?
    @is_directory
  end
end

class Packer
  # Heavily based on crxmake project: http://github.com/Constellation/crxmake by Constellation. Thx a lot dude.

  # My first wish was using crxmake directly (maybe with a few modifications) but I found out
  # that this was almost impossible without almost completely rewriting it. The main issues were:
  # * As I intend to host this on GAE I won't have access to the filesystem, so everything has
  #   to be done on memory.
  # * crxmake uses zipruby which is a C extension and thus not available on JRuby
  # * There were a lot of issues trying to use jruby-openssl, as a workaround I'm relying
  #   on low level bouncy castle classes, and yes, I know this is very ugly.

  # Constants from crxmake
  MAGIC = 'Cr24'
  EXT_VERSION = [2].pack('L')
  KEY = %w(30 81 9F 30 0D 06 09 2A 86 48 86 F7 0D 01 01 01 05 00 03 81 8D 00).map{|s| s.hex}.pack('C*')
  KEY_SIZE = 1024

  def initialize(old_packed_data)
    @entries = unpack(old_packed_data)
  end

  def set_key(key_str)
    key_factory = org.bouncycastle.jce.provider.JDKKeyFactory::RSA.new

    priv_key_spec = java.security.spec.PKCS8EncodedKeySpec.new(key_str.to_java_bytes)
    @private_key = key_factory.engine_generate_private(priv_key_spec)

    public_key_spec = java.security.spec.RSAPublicKeySpec.new(@private_key.get_modulus, @private_key.get_public_exponent)
    @public_key = key_factory.engine_generate_public(public_key_spec)
    fix_public_key!
  end

  def generate_key
    key_generator = org.bouncycastle.jce.provider.JDKKeyPairGenerator::RSA.new
    key_generator.initialize__method(1024, java.security.SecureRandom.new)
    key_pair = key_generator.generate_key_pair

    @private_key = key_pair.get_private
    @public_key = key_pair.get_public
    fix_public_key!

    [
      String.from_java_bytes(@private_key.get_encoded),
      generate_id(KEY + String.from_java_bytes(@public_key.get_encoded))
    ]
  end

  def pack
    raise ArgumentError unless @entries

    output_stream = java.io.ByteArrayOutputStream.new
    zip_output_stream = java.util.zip.ZipOutputStream.new(output_stream)
    @entries.each do |entry|
      name = entry.name.to_java_string
      if entry.directory?
        zip_output_stream.put_next_entry(java.util.zip.ZipEntry.new(name))
      else
        zip_output_stream.put_next_entry(java.util.zip.ZipEntry.new(name))
        zip_output_stream.write(entry.data.to_java_bytes)
      end
      zip_output_stream.close_entry
    end
    zip_output_stream.close
    zip_buffer = String.from_java_bytes(output_stream.to_byte_array)
    signature = sign_data(zip_buffer)
    public_key = KEY + String.from_java_bytes(@public_key.get_encoded)

    buffer = ""
    buffer << MAGIC
    buffer << EXT_VERSION
    buffer << to_sizet(public_key.size)
    buffer << to_sizet(signature.size)
    buffer << public_key
    buffer << signature
    buffer << zip_buffer
    buffer
  end

  def [](file_name)
    entry = @entries.find { |e| e.name == file_name }
    raise ArgumentError unless entry
    entry.data
  end

  def []=(file_name, file_data)
    entry = @entries.find { |e| e.name == file_name }
    raise ArgumentError unless entry
    entry.data = file_data
  end

  def each
    @entries.each { |e| yield e }
  end

private

  def fix_public_key!
    class << @public_key
      alias_method :get_encoded_old, :get_encoded
      def get_encoded
        # We don't want X.509 extra stuff
        get_encoded_old[22..-1]
      end
    end
  end

  def sign_data(zip_buffer)
    signature = java.security.Signature.get_instance('SHA1withRSA')
    signature.init_sign(@private_key, java.security.SecureRandom.new)
    signature.update(zip_buffer.to_java_bytes)

    String.from_java_bytes(signature.sign)
  end

  def to_sizet num
    return [num].pack('L')
  end

  def unpack(packed_extension_data)
    entries = []
    zipped_data = packed_extension_data[(packed_extension_data =~ /PK/)..-1]
    input_stream = java.io.ByteArrayInputStream.new(zipped_data.to_java_bytes)
    zip_input_stream = nil
    begin
      zip_input_stream = java.util.zip.ZipInputStream.new(input_stream)
    rescue
      # Trying one more time
      zip_input_stream = java.util.zip.ZipInputStream.new(input_stream)
    end
    while (entry = zip_input_stream.next_entry) != nil do
      ruby_entry = ZipEntry.new
      ruby_entry.name = entry.name
      if entry.directory?
        ruby_entry.is_directory = true
      else
        buffer_sz = (entry.size > 0) ? entry.size : 1024
        buffer_byte_array = (' ' * buffer_sz).to_java_bytes

        while (bytes_read = zip_input_stream.read(buffer_byte_array, 0, buffer_sz)) != -1
          ruby_entry.data << String.from_java_bytes(buffer_byte_array)[0...bytes_read]
        end
      end
      entries << ruby_entry
    end
    zip_input_stream.close
    entries
  end

  def generate_id(public_key)
    message_digest = java.security.MessageDigest.get_instance('SHA-256')
    message_digest.update(public_key.to_java_bytes)
    hex_id = String.from_java_bytes(message_digest.digest).unpack('H*')[0]
    hex_id[0...32].split('').map do |char|
      (char.hex + 'a'[0]).chr
    end.join
  end
end

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
  property :generated_key, Blob, :lazy => true
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

    @packer = Packer.new(cached.packed_data)
    if self.generated_key
      @packer.set_key(self.generated_key)
    else
      self.generated_key, self.generated_id = @packer.generate_key
      save
    end
    update_manifest

    data = @packer.pack
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
      if e.name =~ /^_locales.*messages\.json/
        json_data = JSON.parse(e.data)
        if entry_value = json_data[entry]
          json_data[entry]['message'] = new_value.gsub(/{entry}/, entry_value['message'])
          e.data = JSON.generate(json_data)
        end
      end
    end
  end
end