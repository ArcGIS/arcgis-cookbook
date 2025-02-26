#
# Cookbook Name:: arcgis-enterprise
# Resource:: server
#
# Copyright 2022-2024 Esri
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
        :join_cluster, :configure_https, :register_data_item, :register_database,
        :set_identity_store, :assign_privileges, :set_machine_properties,
        :stop_machine, :unregister_machine, :unregister_machines,
        :unregister_stopped_machines, :block_data_copy, :set_system_properties,
        :configure_security_protocol, :unregister_web_adaptors, :federate 

attribute :setup_archive, :kind_of => String
attribute :setups_repo, :kind_of => String
attribute :setup, :kind_of => String
attribute :product_code, :kind_of => String
attribute :install_dir, :kind_of => String
attribute :install_environment, :kind_of => [Hash, nil], :default => nil
attribute :python_dir, :kind_of => String
attribute :run_as_user, :kind_of => String
attribute :run_as_password, :kind_of => String, :sensitive => true
attribute :run_as_msa, :kind_of => [TrueClass, FalseClass], :default => false
attribute :server_url, :kind_of => String
attribute :server_admin_url, :kind_of => String
attribute :wa_url, :kind_of => String
attribute :primary_server_url, :kind_of => String
attribute :keystore_file, :kind_of => [String, nil]
attribute :keystore_password, :kind_of => [String, nil], :sensitive => true
attribute :cert_alias, :kind_of => String
attribute :root_cert, :kind_of => String
attribute :root_cert_alias, :kind_of => String
attribute :cluster, :kind_of => String
attribute :server_id, :kind_of => String
attribute :secret_key, :kind_of => String, :sensitive => true
attribute :portal_url, :kind_of => String
attribute :portal_username, :kind_of => String
attribute :portal_password, :kind_of => String, :sensitive => true
attribute :username, :kind_of => String
attribute :password, :kind_of => String, :sensitive => true
attribute :server_directories_root, :kind_of => String
attribute :config_store_connection_string, :kind_of => String
attribute :config_store_connection_secret, :kind_of => String
attribute :config_store_type, :kind_of => String, :default => 'FILESYSTEM'
attribute :cloud_config, :kind_of => String, :default => ''
attribute :authorization_file, :kind_of => String
attribute :authorization_file_version, :kind_of => String
attribute :data_item, :kind_of => Hash
attribute :data_item_path, :kind_of => String
attribute :connection_string, :kind_of => String
attribute :is_managed, :kind_of => [TrueClass, FalseClass], :default => false
attribute :system_properties, :kind_of => Hash, :default => {}
attribute :services_dir_enabled, :kind_of => [TrueClass, FalseClass], :default => true
attribute :log_level, :kind_of => String, :default => 'WARNING'
attribute :log_dir, :kind_of => String
attribute :max_log_file_age, :kind_of => Integer, :default => 90
attribute :use_join_site_tool, :kind_of => [TrueClass, FalseClass], :default => false
attribute :pull_license, :kind_of => [TrueClass, FalseClass], :default => false
attribute :user_store_config, :kind_of => Hash, :default => {}
attribute :role_store_config, :kind_of => Hash, :default => {}
attribute :privileges, :kind_of => Hash, :default => {}
attribute :soc_max_heap_size, :kind_of => Integer, :default => 64
attribute :protocol, :kind_of => String, :default => 'HTTPS'
attribute :authentication_mode, :kind_of => String, :default => 'ARCGIS_TOKEN'
attribute :authentication_tier, :kind_of => String, :default => 'GIS_SERVER'
attribute :hsts_enabled, :kind_of => [TrueClass, FalseClass], :default => false
attribute :virtual_dirs_security_enabled, :kind_of => [TrueClass, FalseClass], :default => false
attribute :allow_direct_access, :kind_of => [TrueClass, FalseClass], :default => true
attribute :allowed_admin_access_ips, :kind_of => String, :default => ''
attribute :https_protocols, :kind_of => String, :default => ''
attribute :cipher_suites, :kind_of => String, :default => ''
attribute :setup_options, :kind_of => String, :default => ''
attribute :authorization_options, :kind_of => String, :default => ''
attribute :unpack_options, :kind_of => String, :default => ''
attribute :enable_debug, :kind_of => [TrueClass, FalseClass], :default => false

def initialize(*args)
  super
  @action = :install
end
