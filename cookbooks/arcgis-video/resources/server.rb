#
# Cookbook Name:: arcgis-video
# Resource:: server
#
# Copyright 2024 Esri
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

unified_mode true

actions :system, :unpack, :install, :uninstall, :update_account, :stop, :start,
        :configure_autostart, :authorize, :create_site, :join_site,
        :unregister_machine, :unregister_web_adaptors, :set_system_properties

attribute :setup_archive, :kind_of => String
attribute :setups_repo, :kind_of => String
attribute :setup, :kind_of => String
attribute :install_dir, :kind_of => String
attribute :run_as_user, :kind_of => String
attribute :run_as_password, :kind_of => String, :sensitive => true
attribute :run_as_msa, :kind_of => [TrueClass, FalseClass], :default => false
attribute :authorization_file, :kind_of => String
attribute :authorization_file_version, :kind_of => String
attribute :authorization_options, :kind_of => String, :default => ''
attribute :product_code, :kind_of => String
attribute :username, :kind_of => String
attribute :password, :kind_of => String, :sensitive => true
attribute :server_directories_root, :kind_of => String
attribute :config_store_type, :kind_of => String
attribute :config_store_connection_string, :kind_of => String
attribute :config_store_class_name, :kind_of => String
attribute :server_url, :kind_of => String
attribute :primary_server_url, :kind_of => String
attribute :system_properties, :kind_of => Hash, :default => {}
attribute :log_level, :kind_of => String, :default => 'WARNING'
attribute :log_dir, :kind_of => String
attribute :max_log_file_age, :kind_of => Integer, :default => 90
attribute :hostname, :kind_of => String

def initialize(*args)
  super
  @action = :install
end

use_inline_resources if defined?(use_inline_resources)

action :system do
  case node['platform']
  when 'windows'
    # Configure Windows firewall
    windows_firewall_rule 'ArcGIS Video Server' do
      description 'Allows connections through all ports used by ArcGIS Video Server'
      local_port node['arcgis']['video_server']['ports']
      protocol 'TCP'
      firewall_action :allow
      only_if { node['arcgis']['configure_windows_firewall'] }
    end
  end
end

action :unpack do
  if node['platform'] == 'windows'
    cmd = @new_resource.setup_archive
    args = "/s /d \"#{@new_resource.setups_repo}\""
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

    args = "/qn ACCEPTEULA=Yes INSTALLDIR=\"#{@new_resource.install_dir}\" USER_NAME=\"#{@new_resource.run_as_user}\" #{password}"

    cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", { :timeout => 3600 })
    cmd.run_command
    Utils.sensitive_command_error(cmd, [ @new_resource.run_as_password ])
  else
    cmd = @new_resource.setup
    args = "-m silent -l yes -d \"#{@new_resource.install_dir}\""
    run_as_user = @new_resource.run_as_user

    # Grant the run as user read-write access to the installation directory
    subdir = @new_resource.install_dir
    node['arcgis']['video_server']['install_subdir'].split("/").each do |path|
      subdir = ::File.join(subdir, path)
      FileUtils.mkdir_p(subdir) unless ::File.directory?(subdir)
      FileUtils.chmod 0700, subdir
      FileUtils.chown run_as_user, nil, subdir
    end

    if node['arcgis']['run_as_superuser']
      cmd = Mixlib::ShellOut.new("su - #{run_as_user} -c \"#{cmd} #{args}\"", { :timeout => 3600 })
    else
      cmd = Mixlib::ShellOut.new("#{cmd} #{args}", { :user => run_as_user, :timeout => 3600 })
    end

    cmd.run_command
    cmd.error!
  end
end

action :uninstall do
  if node['platform'] == 'windows'
    cmd = 'msiexec'
    args = "/qn /x #{@new_resource.product_code}"

    cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", { :timeout => 3600 })
    cmd.run_command
    cmd.error!
  else
    install_subdir = ::File.join(@new_resource.install_dir,
                                 node['arcgis']['video_server']['install_subdir'])
    cmd = ::File.join(install_subdir, 'uninstall_ArcGISVideoServer')
    args = '-s'

    cmd = Mixlib::ShellOut.new("su - #{@new_resource.run_as_user} -c \"#{cmd} #{args}\"",
                               { :timeout => 3600 })
    cmd.run_command
    cmd.error!
  end
end

action :update_account do
  if node['platform'] == 'windows'
    Utils.sc_config('ArcGIS Video Server', @new_resource.run_as_user, @new_resource.run_as_password)
  end
end

action :stop do
  if node['platform'] == 'windows'
    service "ArcGIS Video Server" do
      supports :status => true, :restart => true, :reload => true
      action :stop
    end
  else
    if node['arcgis']['video_server']['configure_autostart']
      service "agsvideo" do
        supports :status => true, :restart => true, :reload => true
        action :stop
      end
    else
      cmd = ::File.join(@new_resource.install_dir,
                        node['arcgis']['video_server']['install_subdir'],
                        'stopvideoserver.sh')

      if node['arcgis']['run_as_superuser']
        cmd = Mixlib::ShellOut.new("su #{node['arcgis']['run_as_user']} -c \"#{cmd}\"", {:timeout => 60})
      else
        cmd = Mixlib::ShellOut.new(cmd, {:timeout => 60})
      end
      cmd.run_command
      cmd.error!
    end
  end

  new_resource.updated_by_last_action(true)
end

action :start do
  if node['platform'] == 'windows'
    service "ArcGIS Video Server" do
      supports :status => true, :restart => true, :reload => true
      timeout 180
      action [:enable, :start]
    end
  else
    if node['arcgis']['video_server']['configure_autostart']
      service "agsvideo" do
        supports :status => true, :restart => true, :reload => true
        action [:enable, :start]
      end
    else
      cmd = ::File.join(@new_resource.install_dir,
                        node['arcgis']['video_server']['install_subdir'],
                        'startvideoserver.sh')

      if node['arcgis']['run_as_superuser']
        cmd = Mixlib::ShellOut.new("su #{node['arcgis']['run_as_user']} -c \"#{cmd}\"", {:timeout => 60})
      else
        cmd = Mixlib::ShellOut.new(cmd, {:timeout => 60})
      end
      cmd.run_command
      cmd.error!
    end
  end
end

action :configure_autostart do
  if node['platform'] == 'windows'
    service "ArcGIS Video Server" do
      supports :status => true, :restart => true, :reload => true
      action :enable
    end
  else
    Chef::Log.info('Configure ArcGIS Video Server to be started with the operating system.')

    agsuser = node['arcgis']['run_as_user']
    agsvideohome = ::File.join(@new_resource.install_dir,
                                  node['arcgis']['video_server']['install_subdir'])

    if node['init_package'] == 'init' # SysV
      Chef::Log.warn('SysV not supported.')
    else # node['init_package'] == 'systemd'
      agsvideo_path = '/etc/systemd/system/agsvideo.service'
      agsvideo_service_file = 'agsvideo.service.erb'
      agsvideo_template_variables = ({ :agsvideohome => agsvideohome, :agsuser => agsuser })
    end

    template agsvideo_path do
      source agsvideo_service_file
      cookbook 'arcgis-video'
      variables agsvideo_template_variables
      owner 'root'
      group 'root'
      mode '0600'
      notifies :run, 'execute[Load agsvideo systemd unit file]', :immediately
    end

    execute 'Load agsvideo systemd unit file' do
      command 'systemctl daemon-reload'
      action :nothing
      only_if {( node['init_package'] == 'systemd' )}
      notifies :restart, 'service[agsvideo]', :immediately
    end

    service 'agsvideo' do
      supports :status => true, :restart => true, :reload => true
      action :enable
    end
  end
end

action :authorize do
  if !@new_resource.authorization_file.nil? && !@new_resource.authorization_file.empty?
    unless ::File.exists?(@new_resource.authorization_file)
      raise "File '#{@new_resource.authorization_file}' not found."
    end

    cmd = node['arcgis']['video_server']['authorization_tool']

    if node['platform'] == 'windows'
      args = "/VER #{@new_resource.authorization_file_version} /LIF \"#{@new_resource.authorization_file}\" /S #{@new_resource.authorization_options}"
      sa_cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}", { :timeout => 600 })

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
          break if ::File.exists?(node['arcgis']['video_server']['keycodes'])
          Chef::Log.error "'#{node['arcgis']['video_server']['keycodes']}' file not found. Retrying software authorization."
          sleep(rand(90..270))
        end
        sa_cmd.run_command
      end

      sa_cmd.error!
    else
      args = "-f \"#{@new_resource.authorization_file}\" #{@new_resource.authorization_options}"
      sa_cmd = Mixlib::ShellOut.new("\"#{cmd}\" #{args}",
            { :timeout => 600, :user => node['arcgis']['run_as_user'] })
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
          Chef::Log.error sa_cmd.format_for_exception + ' Retrying software authorization...'
          sleep(rand(120..300))
        else
          sleep(30)
          sa_status_cmd.run_command
          break if !sa_status_cmd.error? && !sa_status_cmd.stdout.include?('Not Authorized')
          Chef::Log.error sa_status_cmd.stdout
          Chef::Log.error "ArcGIS Video Server is not authorized. Retrying software authorization..."
          sleep(rand(90..270))
        end
        sa_cmd.run_command
      end

      sa_cmd.error!
    end
  end
end

action :create_site do
  admin_client = ArcGIS::VideoServerAdminClient.new(@new_resource.server_url,
                                                    @new_resource.username,
                                                    @new_resource.password)

  admin_client.wait_until_available

  if admin_client.upgrade_required?
    Chef::Log.info('Completing ArcGIS Video Server upgrade...')
    admin_client.complete_upgrade
  elsif admin_client.site_exist?
    Chef::Log.warn('ArcGIS Video Server site already exists.')
  else
    Chef::Log.info('Creating ArcGIS Video Server site...')

    admin_client.create_site(@new_resource.server_directories_root,
                             @new_resource.config_store_type,
                             @new_resource.config_store_connection_string,
                             @new_resource.config_store_class_name,
                             @new_resource.log_level,
                             @new_resource.log_dir,
                             @new_resource.max_log_file_age)
  end
end

action :join_site do
  admin_client = ArcGIS::VideoServerAdminClient.new(@new_resource.server_url,
                                                    @new_resource.username,
                                                    @new_resource.password)

  admin_client.wait_until_available

  if admin_client.upgrade_required?
    Chef::Log.info('Completing ArcGIS Video Server upgrade...')
    admin_client.complete_upgrade
  elsif admin_client.site_exist?
    Chef::Log.warn('The machine has already joined an ArcGIS Video Server site.')
  else
    admin_client.join_site(@new_resource.primary_server_url)
  end
end

action :unregister_machine do
  admin_client = ArcGIS::VideoServerAdminClient.new(@new_resource.server_url,
                                                    @new_resource.username,
                                                    @new_resource.password)

  admin_client.wait_until_available

  Chef::Log.info('Unregistering server machine...')

  machine_name = @new_resource.hostname
  machine_name = node['fqdn'] if machine_name.empty?

  admin_client.unregister_machine(machine_name)
end

action :unregister_web_adaptors do
  admin_client = ArcGIS::VideoServerAdminClient.new(@new_resource.server_url,
                                                      @new_resource.username,
                                                      @new_resource.password)

  admin_client.wait_until_available

  Chef::Log.info('Unregistering ArcGIS Video Server Web Adaptors...')

  admin_client.unregister_web_adaptors
end


action :set_system_properties do
  admin_client = ArcGIS::VideoServerAdminClient.new(@new_resource.server_url,
                                                      @new_resource.username,
                                                      @new_resource.password)
  
  admin_client.wait_until_available

  admin_client.update_system_properties(@new_resource.system_properties)
end
