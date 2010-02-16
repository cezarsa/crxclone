require 'spec/spec_helper'

describe "Extension" do
  context "#clone_extension" do
    it "raises ExtensionNotFoundError if extension id doesn't exist in Chrome's gallery" do
      e = Extension.new
      e.extension_id = '12345'
      lambda { e.clone_extension }.should raise_error(ExtensionNotFoundError)
    end

    context " for a valid extension" do
      it "should return an ExtensionClone and a CachedExtension" do
        e = Extension.new
        e.extension_id = 'gphdmnilpmjaioploikmbpgkjfbagidf'

        clone = e.clone_extension

        clone.should be_a_kind_of(ExtensionClone)
        clone.extension.should == e

        cached = e.cached_extension
        cached.should be_a_kind_of(CachedExtension)
        cached.extension.should == e
      end
    end
  end

  context "#check_most_recent_version" do
    it "raises ExtensionNotFoundError if extension id doesn't exist in Chrome's gallery" do
      e = Extension.new
      e.extension_id = '12345'

      lambda { e.check_most_recent_version }.should raise_error(ExtensionNotFoundError)
    end

    context " for a valid extension" do
      before :each do
        @ext = Extension.new
        @ext.extension_id = 'encaiiljifbdbjlphpgpiimidegddhic'
      end

      it "returns a 3 elements array" do
        version_info = @ext.check_most_recent_version

        version_info.size.should == 3
        version_info.all? { |ret| !ret.nil? }
      end

      it "sets the first return value to a boolean describing if an update is needed or current_version is nil" do
        current_version = nil
        version_info = @ext.check_most_recent_version(current_version)
        version_info[0].should be_true

        current_version = version_info[1]
        version_info = @ext.check_most_recent_version(current_version)
        version_info[0].should be_false
      end

      it "sets the second return value to most recent extension version" do
        version_info = @ext.check_most_recent_version
        version_info[1].should match(/^(\d*\.)*\d+$/)
      end

      it "sets the third return value to extension's download URL" do
        version_info = @ext.check_most_recent_version

        require 'appengine-apis/urlfetch'
        response = nil
        uri = URI(version_info[2])
        AppEngine::URLFetch::HTTP.start(uri.host) do |http|
          response = http.head(uri.path)
        end
        response.code.should == "200"
      end
    end
  end
end