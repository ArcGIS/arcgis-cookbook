#
# Cookbook Name:: arcgis-geoevent
# Resource:: geoevent
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

actions :system, :unpack, :install, :uninstall, :update_account,
        :stop, :start, :configure_autostart, :authorize

attribute :setup_archive, :kind_of => String
attribute :setups_repo, :kind_of => String
attribute :setup, :kind_of => String
attribute :setup_options, :kind_of => String, :default => ''
attribute :install_dir, :kind_of => String
attribute :run_as_user, :kind_of => String
attribute :run_as_password, :kind_of => String, :sensitive => true
attribute :run_as_msa, :kind_of => [TrueClass, FalseClass], :default => false
attribute :authorization_file, :kind_of => String
attribute :authorization_file_version, :kind_of => String
attribute :authorization_options, :kind_of => String, :default => ''
attribute :product_code, :kind_of => String

def initialize(*args)
  super
  @action = :install
end
