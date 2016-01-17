#
# Cookbook Name:: cens-ohmage
# Recipe:: default
#
# Author: Steve Nolen <technolengy@gmail.com>
#
# Copyright (c) 2014.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# require chef-vault
chef_gem 'chef-vault'
require 'chef-vault'

# install/enable nginx
node.set['nginx']['default_site_enabled'] = false
node.set['nginx']['install_method'] = 'package'
include_recipe 'nginx::repo'
include_recipe 'nginx'

# install jre-headless
# install/enable tomcat
package 'tomcat7'
service 'tomcat7' do
  supports status: true, restart: true, reload: false
  action [:enable, :start]
end

# install/enable mysql
# currently no-op since a server or two are already running mariadb and that might be weird.

# set log level attribute
case node['fqdn']
when 'test.mobilizingcs.org'
  node.set['ohmage']['log_level'] = 'INFO'
else
  node.set['ohmage']['log_level'] = 'WARN'
end

# /etc/ohmage.conf
ohmage_db_password = ChefVault::Item.load('passwords', 'ohmage_db')
fqdn = node['fqdn']

template '/etc/ohmage.conf' do
  source 'ohmage.conf.erb'
  mode '0755'
  variables(
    ohmage_db_password: ohmage_db_password[fqdn]
  )
  action :create
end

# install flyway, configure conf file for ohmage
flyway 'ohmage' do
  url 'jdbc:mysql://127.0.0.1:3306/ohmage'
  user 'ohmage'
  password ohmage_db_password[fqdn]
  additional_options(
    'placeholders.fqdn' => fqdn,
    'placeholders.base_dir' => '/var/lib/ohmage'
  )
  action :create
end

file '/opt/flyway-ohmage/flyway' do
  mode '0755'
end

# SSL
case node['fqdn']
when 'pilots.mobilizelabs.org'
  ssl_name = 'pilots.mobilizelabs.org'
else
  ssl_name = node['domain']
end
item = ChefVault::Item.load('ssl', ssl_name)
file "/etc/ssl/certs/#{ssl_name}.crt" do
  owner 'root'
  group 'root'
  mode '0777'
  content item['cert']
  notifies :reload, 'service[nginx]', :delayed
end
file "/etc/ssl/private/#{ssl_name}.key" do
  owner 'root'
  group 'root'
  mode '0600'
  content item['key']
  notifies :reload, 'service[nginx]', :delayed
end

# nginx conf
directory '/etc/nginx/includes' do
  mode 0755
  action :create
end
template '/etc/nginx/includes/ro-ohmage' do
  source 'ohmage-nginx-ro.conf.erb'
  mode '0755'
  action :create
end
case node['fqdn']
when 'test.mobilizingcs.org'
  ocpu = 'dev.opencpu.org'
else
  ocpu = 'ocpu.ohmage.org'
end

template '/etc/nginx/sites-available/ohmage' do
  source 'ohmage-nginx.conf.erb'
  mode '0775'
  action :create
  variables(
    ssl_name: ssl_name,
    ocpu: ocpu
  )
  notifies :reload, 'service[nginx]', :delayed
end
nginx_site 'ohmage' do
  action :enable
end



# system.properties content (do this after ohmage is certainly exploded..)
# match the correct app deploy in the ohmage conf, restart tomcat if change occurs.
case node['domain']
when 'mobilizingcs.org'
  deploy = 'mobilize'
else
  deploy = 'ohmage'
end

ruby_block 'set application.name' do
  block do
    file = Chef::Util::FileEdit.new('/var/lib/tomcat7/webapps/app/WEB-INF/properties/system.properties')
    file.search_file_replace_line('application.name=', "application.name=#{deploy}")
    file.write_file
  end
  not_if "grep -q \'application.name=#{deploy}\' /var/lib/tomcat7/webapps/app/WEB-INF/properties/system.properties"
  notifies :restart, 'service[tomcat7]', :delayed
end

directory '/var/log/ohmage' do
  mode 0755
  owner 'tomcat7'
  group 'tomcat7'
  action :create
end

directory '/var/lib/ohmage' do
  mode 0755
  owner 'tomcat7'
  group 'tomcat7'
  action :create
end

%w(audits audio images documents videos).each do |dir|
 directory "/var/lib/ohmage/#{dir}" do
  mode 0755
  owner 'tomcat7'
  group 'tomcat7'
  action :create
 end
end
