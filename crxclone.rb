require 'sinatra'
require 'dm-core'
require 'builder'

DataMapper.setup(:default, "appengine://auto")

Dir['models/*.rb'].each do |model_file|
  require model_file
end


helpers do
  def send_data(data)
    headers(
      'Content-Length'            => data.size.to_s,
      'Content-Type'              => 'application/x-chrome-extension',
      'Content-Disposition'       => 'attachment; filename="extension.crx"',
      'Content-Transfer-Encoding' => 'binary',
      'Cache-Control'             => 'private, no-cache',
      'Expires'                   => '0')

    data
  end

  def builder_update_result(extension_id, app_status, update_status, download_url = nil, new_version = nil)
    builder do |xml|
      xml.instruct!
      xml.gupdate :xmlns => 'http://www.google.com/update2/response', :protocol => '2.0' do
        xml.app :appid => extension_id, :status => app_status do
          if download_url
            xml.updatecheck :status => update_status, :codebase => download_url,
              :hash => '', :needsadmin => '', :size => '0', :version => new_version
          else
            xml.updatecheck :status => update_status
          end
        end
      end
    end
  end

  def builder_not_found(extension_id)
    app_status = 'error-unknownApplication'
    update_status = 'error-unknownapplication'
    builder_update_result(extension_id, app_status, update_status)
  end

  def builder_dont_update(extension_id)
    app_status = 'ok'
    update_status = 'noupdate'
    builder_update_result(extension_id, app_status, update_status)
  end

  def builder_should_update(extension_id, download_url, new_version)
    app_status = 'ok'
    update_status = 'ok'
    builder_update_result(extension_id, app_status, update_status, download_url, new_version)
  end
end

get '/' do
  @extensions = Extension.all

  erb :index
end

get '/keep_alive' do
  $logger.info 'keep alive'

  ''
end

get '/extension/:id/clone' do
  ext = Extension.first(:extension_id => params[:id])
  unless ext
    ext = Extension.new(:extension_id => params[:id])
  end

  send_data(ext.clone_extension.pack_clone)
end

get '/cloned_extension/request_update' do
  x_params = Rack::Utils.parse_query(params['x'])
  clone = ExtensionClone.first(:generated_id => x_params['id'])

  xml_rsp = if clone.nil?
    builder_not_found(x_params['id'])
  else
    update_info = clone.request_update(x_params['v'])
    if update_info.update?
      builder_should_update(x_params['id'], update_info.download_url, update_info.version)
    else
      builder_dont_update(x_params['id'])
    end
  end
  xml_rsp
end

get '/cloned_extension/:id' do
  clone = ExtensionClone.first(:generated_id => params[:id])
  raise ArgumentError unless clone

  send_data(clone.pack_clone)
end