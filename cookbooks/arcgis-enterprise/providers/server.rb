#
# Cookbook Name:: arcgis-enterprise
# Provider:: server
#
# Copyright 2015-2024 Esri
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
require 'fileutils'
require 'json'

if RUBY_PLATFORM =~ /mswin|mingw32|windows/
  require 'win32/service'
end

use_inline_resources

action :system do
  case node['platform']
  when 'windows'
    # Install .Net Framework
    if node['platform_version'].to_f < 6.3
      node.default['ms_dotnet']['v4']['version'] = '4.5.1'
      @run_context.include_recipe 'ms_dotnet::ms_dotnet4'
    end

    # Configure Windows firewall

    windows_firewall_rule 'ArcGIS Server' do
      description 'Allows connections through all ports used by ArcGIS Server'
      local_port node['arcgis']['server']['ports']
      protocol 'TCP'
      firewall_action :allow
      only_if { node['arcgis']['configure_windows_firewall'] }
    end

    windows_firewall_rule 'ArcGIS GeoAnalytics Server' do
      description 'Allows connections through all ports used by ArcGIS GeoAnalytics Server'
      local_port node['arcgis']['server']['geoanalytics_ports']
      protocol 'TCP'
      firewall_action :allow
      only_if { node['arcgis']['configure_windows_firewall'] }
    end
  end

  new_resource.updated_by_last_action(true)
end

action :unpack do
  if node['platform'] == 'windows'
    cmd = @new_resource.setup_archive
    args = "/s /d \"#{@new_resource.setups_repo}\" #{@new_resource.unpack_options}"
    cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", { :timeout => 3600 })
    cmd.run_command
    cmd.error!
  else
    cmd = 'tar'
    args = "xzvf \"#{@new_resource.setup_archive}\""
    repo = ::File.join(@new_resource.setups_repo, node['arcgis']['version'])
    FileUtils.mkdir_p(repo) unless ::File.directory?(repo)
    cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", { :timeout => 3600, :cwd => repo })
    cmd.run_command
    cmd.error!

    FileUtils.chown_R @new_resource.run_as_user, nil, repo
  end

  new_resource.updated_by_last_action(true)
end

action :install do
  unless ::File.exists?(@new_resource.setup)
    raise "File '#{@new_resource.setup}' not found."
  end

  if node['platform'] == 'windows'
    cmd = @new_resource.setup

    password = if @new_resource.run_as_msa
                 'MSA=\"True\"'
               else
                 "PASSWORD=\"#{@new_resource.run_as_password}\""
               end

    args = "/qn ACCEPTEULA=Yes INSTALLDIR=\"#{@new_resource.install_dir}\" "\
           "INSTALLDIR1=\"#{@new_resource.python_dir}\" "\
           "USER_NAME=\"#{@new_resource.run_as_user}\" "\
           "#{password} "\
           "#{@new_resource.setup_options}"

    cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", { :timeout => 7200, :environment => @new_resource.install_environment })
    cmd.run_command
    Utils.sensitive_command_error(cmd, [ @new_resource.run_as_password ])
  else
    cmd = @new_resource.setup
    args = "-m silent -l yes -d \"#{@new_resource.install_dir}\" #{@new_resource.setup_options}"
    run_as_user = @new_resource.run_as_user

    subdir = @new_resource.install_dir
    node['arcgis']['server']['install_subdir'].split("/").each do |path|
      subdir = ::File.join(subdir, path)
      FileUtils.mkdir_p(subdir) unless ::File.directory?(subdir)
      FileUtils.chmod 0700, subdir
      FileUtils.chown run_as_user, nil, subdir
    end

    if node['arcgis']['run_as_superuser']
      cmd = Mixlib::ShellOut.new("su #{run_as_user} -c \"#{cmd} #{args}\"", { :timeout => 3600, :environment => @new_resource.install_environment })
    else
      cmd = Mixlib::ShellOut.new("#{cmd} #{args}", {:user => run_as_user, :timeout => 3600, :environment => @new_resource.install_environment })
    end
    cmd.run_command
    Utils.sensitive_command_error(cmd)
  end

  new_resource.updated_by_last_action(true)
end

action :uninstall do
  if node['platform'] == 'windows'
    cmd = 'msiexec'
    args = "/qn /x #{@new_resource.product_code}"

    cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", {:timeout => 3600})
    cmd.run_command
    cmd.error!
  else
    install_subdir = ::File.join(@new_resource.install_dir,
                                 node['arcgis']['server']['install_subdir'])
    cmd = ::File.join(install_subdir, 'uninstall_ArcGISServer')
    args = '-s'
    run_as_user = @new_resource.run_as_user

    if node['arcgis']['run_as_superuser']
      cmd = Mixlib::ShellOut.new("su #{run_as_user} -c \"#{cmd} #{args}\"", { :timeout => 3600 })
    else
      cmd = Mixlib::ShellOut.new("#{cmd} #{args}", {:user => run_as_user, :timeout => 3600})
    end
    cmd.run_command
    cmd.error!
  end

  new_resource.updated_by_last_action(true)
end

action :update_account do
  if node['platform'] == 'windows'
    if Utils.sc_logon_account('ArcGIS Server') != @new_resource.run_as_user
      configureserviceaccount = node['arcgis']['server']['configuration_utility']
      run_as_password = @new_resource.run_as_password.gsub("&", "^&")
      args = "/username \"#{@new_resource.run_as_user}\""\
             " /password \"#{run_as_password}\" "
      
      unless @new_resource.server_directories_root.nil?
        args += " /rsdir \"#{@new_resource.server_directories_root}\"" 
      end

      unless @new_resource.log_dir.nil?
        args += " /logsdir \"#{@new_resource.log_dir}\" " 
      end
      
      unless @new_resource.config_store_connection_string.nil? || 
             @new_resource.config_store_type != 'FILESYSTEM'
        args += " /csdir \"#{@new_resource.config_store_connection_string}\"" 
      end

      cmd = Mixlib::ShellOut.new("\"#{configureserviceaccount}\" #{args}",
                                {:timeout => 3600})
      cmd.run_command
      Utils.sensitive_command_error(cmd, [ run_as_password ])
    end

    # Update logon account of the windows service directly in addition to running ServerConfigurationUtility.exe
    Utils.sc_config('ArcGIS Server', @new_resource.run_as_user, @new_resource.run_as_password)

    new_resource.updated_by_last_action(true)
  end
end

action :authorize do
  unless ::File.exists?(@new_resource.authorization_file)
    raise "File '#{@new_resource.authorization_file}' not found."
  end

  cmd = node['arcgis']['server']['authorization_tool']
  if node['platform'] == 'windows'
    args = "/VER #{@new_resource.authorization_file_version} /LIF \"#{@new_resource.authorization_file}\" /S #{@new_resource.authorization_options}"
    sa_cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", {:timeout => 600})
    sleep(rand(0..120)) # Use random delay top reduce probability of multiple machines authorization at the same time
    sa_cmd.run_command

    # Retry authorization five times with random intervals between 120 and 300 seconds.
    # Check if 'keycodes' file exists after each retry.
    # This is required to get around the problem with simultaneous authorization from
    # multiple machines using the same license.
    node['arcgis']['server']['authorization_retries'].times do
      if sa_cmd.error?
        Chef::Log.error sa_cmd.format_for_exception + ' Retrying software authorization.'
        sleep(rand(120..300))
      else
        sleep(30)
        break if ::File.exists?(node['arcgis']['server']['keycodes'])
        Chef::Log.error "'#{node['arcgis']['server']['keycodes']}' file not found. Retrying software authorization."
        sleep(rand(90..270))
      end
      sa_cmd.run_command
    end

    sa_cmd.error!
  else
    sa_cmd = Mixlib::ShellOut.new("\"#{cmd}\" -f \"#{@new_resource.authorization_file}\" #{@new_resource.authorization_options}",
          { :user => node['arcgis']['run_as_user'], :timeout => 600 })
    sleep(rand(0..120)) # Use random delay top reduce probability of multiple machines authorization at the same time
    sa_cmd.run_command

    # Retry authorization five times with random intervals between 120 and 300 seconds.
    # Check if softwareAuthorization stdout does not contain 'Not Authorized' after each retry.
    # This is required to get around the problem with simultaneous authorization from
    # multiple machines using the same license.
    sa_status_cmd = Mixlib::ShellOut.new("\"#{cmd}\" -s",
          { :user => node['arcgis']['run_as_user'], :timeout => 600 })

    node['arcgis']['server']['authorization_retries'].times do
      if sa_cmd.error?
        Chef::Log.error sa_cmd.format_for_exception + '  Retrying software authorization...'
        sleep(rand(120..300))
      else
        sleep(30)
        sa_status_cmd.run_command
        break if !sa_status_cmd.error? && !sa_status_cmd.stdout.include?('Not Authorized')
        Chef::Log.error sa_status_cmd.stdout
        Chef::Log.error "ArcGIS Server is not authorized. Retrying software authorization..."
        sleep(rand(90..270))
      end
      sa_cmd.run_command
    end

    sa_cmd.error!
  end

  new_resource.updated_by_last_action(true)
end

action :create_site do
  begin
    admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                 @new_resource.username,
                                                 @new_resource.password)

    admin_client.wait_until_available

    if admin_client.upgrade_required?
      Chef::Log.info('Completing ArcGIS Server site upgrade...')
      
      # Async upgrades are supported starting from ArcGIS Server 11.4
      if ['10.9.1', '11.0', '11.1', '11.2', '11.3'].include?(node['arcgis']['version'])
        admin_client.complete_upgrade       
      else
        admin_client.complete_upgrade_async(@new_resource.enable_debug)
      end

      Chef::Log.info('ArcGIS Server site upgrade is complete.')
      
      new_resource.updated_by_last_action(true)
    else
      if admin_client.site_exist?
        Chef::Log.info('ArcGIS Server site already exists.')
      else
        Chef::Log.info('Creating ArcGIS Server site...')

        if @new_resource.cloud_config.empty?
          admin_client.create_site(@new_resource.server_directories_root,
                                   @new_resource.config_store_type,
                                   @new_resource.config_store_connection_string,
                                   @new_resource.config_store_connection_secret,
                                   @new_resource.log_level,
                                   @new_resource.log_dir,
                                   @new_resource.max_log_file_age)
        else
          admin_client.create_site_cloud(@new_resource.cloud_config,
                                         @new_resource.log_level,
                                         @new_resource.log_dir,
                                         @new_resource.max_log_file_age)
        end

        new_resource.updated_by_last_action(true)
      end
    end
  rescue Exception => e
    Chef::Log.error "Failed to create or upgrade ArcGIS Server site. " + e.message
    raise e
  end
end

action :join_site do
  begin
    admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                 @new_resource.username,
                                                 @new_resource.password)

    admin_client.wait_until_available

    if admin_client.upgrade_required?
      Chef::Log.info('Completing ArcGIS Server site upgrade...')

      if ['10.9.1', '11.0', '11.1', '11.2', '11.3'].include?(node['arcgis']['version'])
        admin_client.complete_upgrade       
      else
        admin_client.complete_upgrade_async(@new_resource.enable_debug)
      end

      Chef::Log.info('ArcGIS Server site upgrade is complete.')

      new_resource.updated_by_last_action(true)
    else  
      if admin_client.site_exist?
        Chef::Log.info('Machine is already connected to an ArcGIS Server site.')
      else
        if @new_resource.use_join_site_tool
          config_store_connection = {
            'type' => @new_resource.config_store_type,
            'connectionString' => @new_resource.config_store_connection_string,
            'connectionSecret' => @new_resource.config_store_connection_secret
          }

          if node['platform'] == 'windows'
            config_store_connection_file = ::File.join(@new_resource.install_dir, 'framework','etc','config-store-connection.json')
            ::File.open(config_store_connection_file, 'w') { |f| f.write(config_store_connection.to_json) }

            join_site_tool_cmd = [
              '"' + ::File.join(@new_resource.install_dir, 'tools', 'JoinSite', 'join-site.bat') + '"',
              '-f', '"' + config_store_connection_file + '"', '-c', 'default'
            ].join(' ')

            # Mixlib::ShellOut does not load user profile of the impersonated user account,
            # so the user's environment variables such as USERNAME, USERPROFILE, TEMP, TMP,
            # APPDATA, and LOCALAPPDATA still point to the parent process user name and directories.
            # See https://github.com/chef/mixlib-shellout/issues/168
            # set the environment variables to get around this problem

            homedrive = ENV['HOMEDRIVE'].nil? ? 'C:' : ENV['HOMEDRIVE']

            run_as_user = node['arcgis']['run_as_user']

            if run_as_user.include? "\\"
              tokens = run_as_user.split(/\\/)
              userdomain = tokens[0]
              username = tokens[1]
            else
              userdomain = node['hostname']
              username = run_as_user
            end

            userprofile = homedrive + '\\Users\\' + username
            env = { 'AGSSERVER' => @new_resource.install_dir + '\\',
                    'USERNAME' => username,
                    'USERDOMAIN' => userdomain,
                    'HOME' => homedrive + '/Users/' + username,
                    'HOMEPATH' => '\\Users\\' + username,
                    'USERPROFILE' => userprofile,
                    'APPDATA' => userprofile + '\\AppData\\Roaming',
                    'LOCALAPPDATA' => userprofile + '\\AppData\\Local',
                    'TEMP' => userprofile + '\\AppData\\Local\\Temp',
                    'TMP' => userprofile + '\\AppData\\Local\\Temp' }

            cmd = Mixlib::ShellOut.new(join_site_tool_cmd,
              { :user => username,
                :domain => userdomain,
                :password => node['arcgis']['run_as_password'],
                :timeout => 1800,
                :environment => env })
            cmd.run_command
            cmd.error!
          else
            install_dir = ::File.join(@new_resource.install_dir, node['arcgis']['server']['install_subdir'])

            config_store_connection_file = ::File.join(install_dir, 'framework','etc','config-store-connection.json')
            ::File.open(config_store_connection_file, 'w') { |f| f.write(config_store_connection.to_json) }

            join_site_tool_cmd = [
              ::File.join(install_dir, 'tools','joinsite','join-site.sh'),
                          '-f', config_store_connection_file, '-c', 'default'
            ].join(' ')

            cmd = Mixlib::ShellOut.new(join_site_tool_cmd,
                  { :user => node['arcgis']['run_as_user'],
                    :timeout => 1800 })
            cmd.run_command
            cmd.error!
          end
        else
          primary_admin_client = ArcGIS::ServerAdminClient.new(
            @new_resource.primary_server_url,
            @new_resource.username,
            @new_resource.password)

          primary_admin_client.wait_until_site_exist

          admin_client.join_site(@new_resource.primary_server_url,
                                @new_resource.pull_license)
        end

        new_resource.updated_by_last_action(true)
      end
    end
  rescue Exception => e
    Chef::Log.error "Failed to join or upgrade ArcGIS Server site. " + e.message
    raise e
  end
end

action :join_cluster do
  begin
    admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                 @new_resource.username,
                                                 @new_resource.password)

    admin_client.wait_until_available

    machine_name = admin_client.local_machine_name

    admin_client.add_machine_to_cluster(machine_name, @new_resource.cluster)

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to join ArcGIS Server cluster. " + e.message
    raise e
  end
end

action :set_system_properties do
  begin
    admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                 @new_resource.username,
                                                 @new_resource.password)
    admin_client.wait_until_available

    if admin_client.system_properties != @new_resource.system_properties
      Chef::Log.info('Updating ArcGIS Server system properties...')
      admin_client.update_system_properties(@new_resource.system_properties)
      Chef::Log.info 'ArcGIS Server system properties were updated.'
      new_resource.updated_by_last_action(true)
    else
      Chef::Log.info 'ArcGIS Server system properties were not changed.'
      new_resource.updated_by_last_action(false)
    end

    Chef::Log.info('Updating ArcGIS Server services directory properties...')
    admin_client.update_services_directory_properties(@new_resource.services_dir_enabled)
    Chef::Log.info 'ArcGIS Server services directory properties were updated.'
  rescue Exception => e
    Chef::Log.error 'Failed to update ArcGIS Server system properties. ' + e.message
    raise e
  end
end

action :configure_https do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    machine_name = admin_client.local_machine_name

    # Import root certificate if it does not exist
    unless @new_resource.root_cert.empty? || 
           admin_client.ssl_certificate_exist?(machine_name,
                                               @new_resource.root_cert_alias,
                                               'trustedCertEntry')
      admin_client.import_root_ssl_certificate(machine_name,
                                               @new_resource.root_cert,
                                               @new_resource.root_cert_alias)
    end

    cert_alias = admin_client.get_server_ssl_certificate(machine_name)

    unless @new_resource.keystore_file.empty? || cert_alias == @new_resource.cert_alias
      unless admin_client.ssl_certificate_exist?(machine_name, @new_resource.cert_alias)
        admin_client.import_server_ssl_certificate(machine_name,
                                                   @new_resource.keystore_file,
                                                   @new_resource.keystore_password,
                                                   @new_resource.cert_alias)
      end

      admin_client.set_server_admin_url(machine_name, @new_resource.server_admin_url)
      admin_client.set_server_ssl_certificate(machine_name, @new_resource.cert_alias)

      # Editing the machine configuration causes the machine to be restarted.
      admin_client.wait_until_available
      sleep(60.0)
      admin_client.wait_until_available

      new_resource.updated_by_last_action(true)
    end
  rescue Exception => e
    Chef::Log.error "Failed to configure SSL certificates in ArcGIS Server. " + e.message
    raise e
  end
end

# Update server security config
action :configure_security_protocol do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    admin_client.wait_until_available

    admin_client.update_security_configuration(@new_resource.protocol,
                                               @new_resource.authentication_mode,
                                               @new_resource.authentication_tier,
                                               @new_resource.hsts_enabled,
                                               @new_resource.virtual_dirs_security_enabled,
                                               @new_resource.allow_direct_access,
                                               @new_resource.allowed_admin_access_ips,
                                               @new_resource.https_protocols,
                                               @new_resource.cipher_suites)

    # Security configuration update causes the SOAP and REST service endpoints 
    # to be redeployed with the new configuration on every server machine in the site.                                           
    admin_client.wait_until_available
    sleep(60.0)
    admin_client.wait_until_available

    new_resource.updated_by_last_action(true)

  rescue Exception => e
    Chef::Log.warn e.message
    # Updating security configuration may fail when other machinesin the site are not accessible.
    # raise e
  end
end

action :register_data_item do
  admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                               @new_resource.username,
                                               @new_resource.password)

  admin_client.register_data_item(@new_resource.data_item)

  new_resource.updated_by_last_action(true)
end

action :register_database do
  admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                               @new_resource.username,
                                               @new_resource.password)

  admin_client.register_database(@new_resource.data_item_path,
                                 @new_resource.connection_string,
                                 @new_resource.is_managed)

  new_resource.updated_by_last_action(true)
end

action :federate do
  server_id = @new_resource.server_id
  secret_key = @new_resource.secret_key

  server_id = node['arcgis']['server']['server_id'] if server_id.nil?

  secret_key = node['arcgis']['server']['secret_key'] if secret_key.nil?

  if !server_id.nil? && !secret_key.nil?
    portal_admin_client = ArcGIS::PortalAdminClient.new(
      @new_resource.portal_url,
      @new_resource.portal_username,
      @new_resource.portal_password)

    portal_admin_client.wait_until_available

    portal_token = portal_admin_client.generate_token(
      @new_resource.portal_url + '/sharing/generateToken')

    server_admin_client = ArcGIS::ServerAdminClient.new(
      @new_resource.server_url,
      @new_resource.username,
      @new_resource.password)

    server_admin_client.wait_until_available

    server_admin_client.federate(@new_resource.portal_url,
                                 portal_token,
                                 server_id,
                                 secret_key)

    new_resource.updated_by_last_action(true)
  end
end

action :stop do
  # Stoppig of ArcGIS Server while it's being started may corrupt configuration files.
  # Wait for 15 seconds to let ArcGIS Server start complete before stopping it.
  sleep(15.0)
 
  if node['platform'] == 'windows'
    if Utils.service_started?('ArcGIS Server')
      #Stop ArcGIS Server windows service and dependent services.
      Utils.retry_ShellOut("net stop \"ArcGIS Server\" /yes",
                           5, 60, {:timeout => 3600})
      new_resource.updated_by_last_action(true)
    end
  else
    if node['arcgis']['server']['configure_autostart']
      service 'arcgisserver' do
        supports :status => true, :restart => true, :reload => true
        action :stop
      end
    else
      cmd = node['arcgis']['server']['stop_tool']

      if node['arcgis']['run_as_superuser']
        cmd = Mixlib::ShellOut.new("su #{node['arcgis']['run_as_user']} -c \"#{cmd}\"", {:timeout => 30})
      else
        cmd = Mixlib::ShellOut.new(cmd, {:timeout => 30})
      end
      cmd.run_command
      cmd.error!
      new_resource.updated_by_last_action(true)
    end
  end
end

action :start do
  if node['platform'] == 'windows'
      if node['arcgis']['configure_cloud_settings']
        if node['arcgis']['cloud']['provider'] == 'ec2'
          env 'arcgis_cloud_platform' do
            value 'aws'
          end
        end
      end

    if !Utils.service_started?('ArcGIS Server')
      #Start ArcGIS Server windows service and dependent services.
      Utils.retry_ShellOut("net start \"ArcGIS Server\" /yes", 5, 60, {:timeout => 600})
      new_resource.updated_by_last_action(true)
    end
  else
    if node['arcgis']['server']['configure_autostart']
      service 'arcgisserver' do
        supports :status => true, :restart => true, :reload => true
        action [:enable, :start]
      end
    else
      cmd = node['arcgis']['server']['start_tool']

      if node['arcgis']['configure_cloud_settings']
        if node['arcgis']['cloud']['provider'] == 'ec2'
          cmd = 'arcgis_cloud_platform=aws ' + cmd
        end
      end

      if node['arcgis']['run_as_superuser']
        cmd = Mixlib::ShellOut.new("su #{node['arcgis']['run_as_user']} -c \"#{cmd}\"", {:timeout => 120})
      else
        cmd = Mixlib::ShellOut.new(cmd, {:timeout => 120})
      end
      cmd.run_command
      cmd.error!
    end
    new_resource.updated_by_last_action(true)
  end
end

action :configure_autostart do
  if node['platform'] == 'windows'
    service 'ArcGIS Server' do
      action :enable
    end
  else
    Chef::Log.info('Configure ArcGIS Server to be started with the operating system.')

    agsuser = node['arcgis']['run_as_user']
    agshome = ::File.join(@new_resource.install_dir,
                          node['arcgis']['server']['install_subdir'])

    # SysV
    if node['init_package'] == 'init'
      arcgisserver_path = '/etc/init.d/arcgisserver'
      service_file = 'arcgisserver.erb'

      if node['arcgis']['version'].start_with? '10.4'
        properties_file = 'arcgis-server-framework.properties'
      else
        properties_file = 'arcgis-framework.properties'
      end

      template_variables = ({ :agshome => agshome, :agsproperties => properties_file })
    # Systemd
    else node['init_package'] == 'systemd'
      arcgisserver_path = '/etc/systemd/system/arcgisserver.service'
      service_file = 'arcgisserver.service.erb'
      template_variables = ({ :agshome => agshome, :agsuser => agsuser })
      if node['arcgis']['configure_cloud_settings']
        if node['arcgis']['cloud']['provider'] == 'ec2'
          cloudenvironment = { :cloudenvironment => 'Environment="arcgis_cloud_platform=aws"' }
          template_variables = template_variables.merge(cloudenvironment)
        end
      end
    end

    template arcgisserver_path do
      source service_file
      cookbook 'arcgis-enterprise'
      variables template_variables
      owner 'root'
      group 'root'
      mode '0600'
      notifies :run, 'execute[Load systemd unit file]', :immediately
    end

    execute 'Load systemd unit file' do
      command 'systemctl daemon-reload'
      action :nothing
      only_if {( node['init_package'] == 'systemd' )}
      notifies :restart, 'service[arcgisserver]', :immediately
    end

    service 'arcgisserver' do
      supports :status => true, :restart => true, :reload => true
      action :enable
      retries 5
      retry_delay 60
    end

    new_resource.updated_by_last_action(true)
  end
end

action :set_identity_store do
  begin
    admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                 @new_resource.username,
                                                 @new_resource.password)

    admin_client.wait_until_available

    Chef::Log.info('Setting ArcGIS Server identity stores...')

    admin_client.set_identity_store(@new_resource.user_store_config,
                                     @new_resource.role_store_config)

    admin_client.wait_until_available

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to configure ArcGIS Server identity stores. " + e.message
    raise e
  end
end

action :assign_privileges do
  begin
    admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                 @new_resource.username,
                                                 @new_resource.password)

    admin_client.wait_until_available

    Chef::Log.info('Assigning privileges to user roles...')

    @new_resource.privileges.keys.each do |privilege|
      @new_resource.privileges[privilege].each do |role|
        admin_client.assign_privileges(role, privilege)
      end
    end

    admin_client.wait_until_available

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to assign privilege to user role. " + e.message
    raise e
  end
end

action :set_machine_properties do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    admin_client.wait_until_available

    Chef::Log.info('Setting server machine properties...')

    machine_name = admin_client.local_machine_name

    updated = admin_client.set_machine_properties(machine_name, @new_resource.soc_max_heap_size)

    admin_client.wait_until_available

    new_resource.updated_by_last_action(updated)
  rescue Exception => e
    Chef::Log.error "Failed to set server machine properties. " + e.message
    raise e
  end
end

action :stop_machine do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    admin_client.wait_until_available

    Chef::Log.info('Stopping server machine...')

    machine_name = admin_client.local_machine_name

    admin_client.stop_machine(machine_name)

    admin_client.remove_machine_from_cluster(machine_name)

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to stop server machine. " + e.message
    raise e
  end
end

action :unregister_machine do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    admin_client.wait_until_available

    if admin_client.site_exist?
      Chef::Log.info('Unregistering ArcGIS Web Adaptors referencing the machine...')
      
      web_adaptors = admin_client.web_adaptors

      web_adaptors.each do |web_adaptor|
        if web_adaptor['machineIP'] == node['ipaddress']
          admin_client.unregister_web_adaptor(web_adaptor['id'])
        end
      end

      Chef::Log.info('Unregistering server machine...')

      machine_name = admin_client.local_machine_name

      admin_client.unregister_machine(machine_name)

      new_resource.updated_by_last_action(true)
    end
  rescue Exception => e
    Chef::Log.error "Failed to unregister server machine. " + e.message
    raise e
  end
end

action :unregister_stopped_machines do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    admin_client.wait_until_available

    Chef::Log.info('Unregistering stopped server machines...')

    admin_client.unregister_stopped_machines(@new_resource.cluster)

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to unregister stopped server machines. " + e.message
    raise e
  end
end

action :unregister_machines do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    admin_client.wait_until_available

    Chef::Log.info('Unregistering all server machines except the local machine...')

    machines = admin_client.machines
    local_machine_name = admin_client.local_machine_name

    machines.each do |machine|
      if machine['machineName'] != local_machine_name
        admin_client.unregister_machine(machine['machineName'])
      end
    end

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to unregister server machines. " + e.message
    raise e
  end
end

action :block_data_copy do
  begin
    admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                 @new_resource.username,
                                                 @new_resource.password)

    admin_client.wait_until_available

    Chef::Log.info('Block automatic copying of data to the server at publishing.')

    admin_client.block_data_copy()

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to block automatic copying of data. " + e.message
    raise e
  end
end

action :unregister_web_adaptors do
  begin
    if @new_resource.use_join_site_tool
      token = generate_admin_token(@new_resource.install_dir, 5)

      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   nil, nil, token)
    else
      admin_client = ArcGIS::ServerAdminClient.new(@new_resource.server_url,
                                                   @new_resource.username,
                                                   @new_resource.password)
    end

    admin_client.wait_until_available

    Chef::Log.info('Unregistering ArcGIS Server Web Adaptors...')

    admin_client.unregister_web_adaptors

    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error "Failed to unregister ArcGIS Server Web Adaptors. " + e.message
    raise e
  end
end

private

def generate_admin_token(install_dir, expiration)
  if node['platform'] == 'windows'
    run_as_user = node['arcgis']['run_as_user']

    if run_as_user.include? "\\"
      tokens = run_as_user.split(/\\/)
      userdomain = tokens[0]
      username = tokens[1]
    else
      userdomain = node['hostname']
      username = run_as_user
    end

    env = { 'AGSSERVER' => @new_resource.install_dir + '\\' }

    generate_admin_token_cmd = [
      '"' + ::File.join(install_dir, 'tools', 'GenerateAdminToken', 'generate-admin-token.bat') + '"',
      '-e', expiration.to_s].join(' ')

    cmd = Mixlib::ShellOut.new(generate_admin_token_cmd,
      { :user => username,
        :domain => userdomain,
        :password => node['arcgis']['run_as_password'],
        :timeout => 1800,
        :environment => env })
    cmd.run_command
    cmd.error!

    JSON.parse(cmd.stdout)['token']
  else
    install_dir = ::File.join(install_dir, node['arcgis']['server']['install_subdir'])

    generate_admin_token_cmd = [
      ::File.join(install_dir, 'tools','generateadmintoken','generate-admin-token.sh'),
      '-e', expiration.to_s].join(' ')

    cmd = Mixlib::ShellOut.new(generate_admin_token_cmd,
          { :user => node['arcgis']['run_as_user'],
            :timeout => 1800 })
    cmd.run_command
    cmd.error!

    JSON.parse(cmd.stdout)['token']
  end
end

