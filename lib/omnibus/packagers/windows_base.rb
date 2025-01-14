#
# Copyright 2016 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Omnibus
  class Packager::WindowsBase < Packager::Base
    # Only use timestamp servers from Microsoft-approved authenticode providers
    # See https://docs.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures
    DEFAULT_TIMESTAMP_SERVERS = ["http://timestamp.digicert.com",
                                 "http://timestamp.globalsign.com/scripts/timstamp.dll",
                                 "http://timestamp.comodoca.com/authenticode",
                                 "http://www.startssl.com/timestamp",
                                 "http://timestamp.sectigo.com"]

    #
    # Set the signing certificate name
    #
    # @example
    #   signing_identity 'FooCert'
    #   signing_identity 'FooCert', store: 'BarStore'
    #
    # @param [String] thumbprint
    #   the thumbprint of the certificate in the certificate store
    # @param [Hash<Symbol, String>] params
    #   an optional hash that defines the parameters for the singing identity
    #
    # @option params [String] :store (My)
    #   The name of the certificate store which contains the certificate
    # @option params [Array<String>, String] :timestamp_servers
    #   A trusted timestamp server or a list of truested timestamp servers to
    #   be tried. They are tried in the order provided.
    # @option params [TrueClass, FalseClass] :machine_store (false)
    #   If set to true, the local machine store will be searched for a valid
    #   certificate. Otherwise, the current user store is used
    #
    #   Setting nothing will default to trying ['http://timestamp.digicert.com',
    #   'http://timestamp.verisign.com/scripts/timestamp.dll']
    #
    # @return [Hash{:thumbprint => String, :store => String, :timestamp_servers => Array[String]}]
    #
    def signing_identity(thumbprint = NULL, params = NULL)
      unless null?(thumbprint)
        if signing_identity_file
          raise Error, "You cannot specify signing_identity and signing_identity_file"
        end

        @signing_identity = {}
        unless thumbprint.is_a?(String)
          raise InvalidValue.new(:signing_identity, "be a String")
        end

        @signing_identity[:thumbprint] = thumbprint

        if !null?(params)
          unless params.is_a?(Hash)
            raise InvalidValue.new(:params, "be a Hash")
          end

          valid_keys = [:store, :timestamp_servers, :machine_store, :algorithm]
          invalid_keys = params.keys - valid_keys
          unless invalid_keys.empty?
            raise InvalidValue.new(:params, "contain keys from [#{valid_keys.join(', ')}]. "\
                                   "Found invalid keys [#{invalid_keys.join(', ')}]")
          end

          if !params[:machine_store].nil? && !(
             params[:machine_store].is_a?(TrueClass) ||
             params[:machine_store].is_a?(FalseClass))
            raise InvalidValue.new(:params, "contain key :machine_store of type TrueClass or FalseClass")
          end
        else
          params = {}
        end

        @signing_identity[:store] = params[:store] || "My"
        @signing_identity[:algorithm] = params[:algorithm] || "SHA1"
        servers = params[:timestamp_servers] || DEFAULT_TIMESTAMP_SERVERS
        @signing_identity[:timestamp_servers] = [servers].flatten
        @signing_identity[:machine_store] = params[:machine_store] || false
      end

      @signing_identity
    end
    expose :signing_identity

    def thumbprint
      signing_identity[:thumbprint]
    end

    def cert_store_name
      signing_identity[:store]
    end

    def machine_store?
      signing_identity[:machine_store]
    end

    def signing_identity_file(pfxfile = NULL, params = NULL)
      unless null?(pfxfile)
        if signing_identity
          raise Error, "You cannot specify signing_identity and signing_identity_file"
        end

        @signing_identity_file = {}
        unless pfxfile.is_a?(String)
          raise InvalidValue.new(:pfxfile, "be a String")
        end

        @signing_identity_file[:pfxfile] = pfxfile

        if !null?(params)
          unless params.is_a?(Hash)
            raise InvalidValue.new(:params, "be a Hash")
          end

          valid_keys = [:password, :timestamp_servers, :algorithm]
          invalid_keys = params.keys - valid_keys
          unless invalid_keys.empty?
            raise InvalidValue.new(:params, "contain keys from [#{valid_keys.join(', ')}]. "\
                                   "Found invalid keys [#{invalid_keys.join(', ')}]")
          end

          if params[:password].nil?
            raise InvalidValue.new(:params, "Must supply password for PFX file")
          end
        else
          params = {}
        end

        @signing_identity_file[:algorithm] = params[:algorithm] || "SHA1"
        servers = params[:timestamp_servers] || DEFAULT_TIMESTAMP_SERVERS
        @signing_identity_file[:timestamp_servers] = [servers].flatten
        @signing_identity_file[:password] = params[:password] || false
      end

      @signing_identity_file
    end
    expose :signing_identity_file

    def pfx_algorithm
      signing_identity_file[:algorithm]
    end

    def pfx_password
      signing_identity_file[:password]
    end

    def pfx_file
      signing_identity_file[:pfxfile]
    end

    def timestamp_servers
      if signing_identity
        signing_identity[:timestamp_servers]
      elsif signing_identity_file
        signing_identity_file[:timestamp_servers]
      else
        nil
      end
    end

    def algorithm
      if signing_identity
        signing_identity[:algorithm]
      elsif signing_identity_file
        signing_identity_file[:algorithm]
      else
        nil
      end
    end

    def dd_wcssign(enabled = false)
      if enabled
        if signing_identity
          raise Error, "You cannot specify signing_identity with dd_wcssign"
        end
        if signing_identity_file
          raise Error, "You cannot specify signing_identity_file with dd_wcssign"
        end

        @dd_wcssign = enabled
      end

      @dd_wcssign
    end
    expose :dd_wcssign

    #
    # Iterates through available timestamp servers and tries to sign
    # the file with with each server, stopping after the first to succeed.
    # If none succeed, an exception is raised.
    #
    def sign_package(package_file, is_bundle: false)
      success = false
      safe_package_file = "#{windows_safe_path(package_file)}"
      if is_bundle
        cmd = Array.new.tap do |arr|
          arr << "insignia.exe"
          arr << "-ib \"#{safe_package_file}\""
          arr << "-o engine.exe"
        end.join(" ")
        shellout(cmd)
        sign_package("engine.exe", is_bundle: false)
        cmd = Array.new.tap do |arr|
          arr << "insignia.exe"
          arr << "-ab engine.exe \"#{safe_package_file}\""
          arr << "-o \"#{safe_package_file}\""
        end.join(" ")
        shellout(cmd)
      end

      retry_block("signing with timestamp servers", [FailedToSignWindowsPackage], retries = 5, delay = 5) do
        success = false
        if dd_wcssign
          success = try_sign(safe_package_file, NULL)
        else
          timestamp_servers.each do |ts|
            puts "signing with timestamp server: #{ts}"
            success = try_sign(safe_package_file, ts)
            puts "signed with timestamp server: #{ts}" if success
            break if success
          end
        end
        raise FailedToSignWindowsPackage.new if !success
      end
    end

    def try_sign(package_file, url)
      if dd_wcssign
        puts "signing with dd-wcs"
        cmd = Array.new.tap do |arr|
          arr << "dd-wcs"
          arr << "sign"
          arr << "\"#{package_file}\""
        end.join(" ")
      elsif signing_identity
        puts "signing with signtool (machine store)"
        cmd = Array.new.tap do |arr|
          arr << "signtool.exe"
          arr << "sign /v"
          arr << "/t #{url}"
          arr << "/fd #{algorithm}"
          arr << "/sm" if machine_store?
          arr << "/s #{cert_store_name}"
          arr << "/sha1 #{thumbprint}"
          arr << "/d #{project.package_name}"
          arr << "\"#{package_file}\""
        end.join(" ")
      elsif signing_identity_file
        puts "signing with signtool (pfx file)"
        cmd = Array.new.tap do |arr|
          arr << "signtool.exe"
          arr << "sign /v"
          arr << "/t #{url}"
          arr << "/f #{pfx_file}"
          arr << "/fd #{algorithm}"
          arr << "/p #{pfx_password}"
          arr << "/d #{project.package_name}"
          arr << "\"#{package_file}\""
        end.join(" ")
      end

      status = shellout(cmd)
      if status.exitstatus != 0
        log.warn(log_key) do
          <<-EOH.strip
                Failed to add timestamp with timeserver #{url}

                STDOUT
                ------
                #{status.stdout}

                STDERR
                ------
                #{status.stderr}
          EOH
        end
      end
      status.exitstatus == 0
    end

    #
    # Get the certificate subject of the signing identity
    #
    # @return [String]
    #
    def certificate_subject
      return "CN=#{project.package_name}" unless signing_identity

      store = machine_store? ? "LocalMachine" : "CurrentUser"
      cmd = Array.new.tap do |arr|
        arr << "powershell.exe"
        arr << "-ExecutionPolicy Bypass"
        arr << "-NoProfile"
        arr << "-Command (Get-Item Cert:/#{store}/#{cert_store_name}/#{thumbprint}).Subject"
      end.join(" ")

      shellout!(cmd).stdout.strip
    end

    #
    # Parse and return the version from the {Project#build_version}.
    #
    # A project's +build_version+ looks something like:
    #
    #     dev builds => 11.14.0-alpha.1+20140501194641.git.94.561b564
    #                => 0.0.0+20140506165802.1
    #
    #     rel builds => 11.14.0.alpha.1 || 11.14.0
    #
    # The appx and msi version specs expects a version that looks like X.Y.Z.W where
    # X, Y, Z & W are all 32 bit integers.
    #
    # @return [String]
    #
    def windows_package_version
      major, minor, patch = project.build_version.split(/[.+-]/)
      [major, minor, patch, project.build_iteration].join(".")
    end
  end
end
