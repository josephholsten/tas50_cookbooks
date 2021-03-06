#
# Author:: Tim Smith <tim.smith@webtrends.com>, Peter Crossley <peter.crossley@webtrends.com>
# Cookbook Name:: ad-auth
# Recipe:: default
#
# Based on the ad-likewise cookbook: Copyright 2010, Bryan McLellan
# Copyright 2012, Tim Smith and Peter Crossly
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

[ "dcerpcd", "netlogond", "eventlogd", "lwregd", "lwiod", "lsassd" ].each do |svc|
  service svc do
    action :nothing
    only_if { File.exists?("/etc/init.d/${svc}") }
  end
end

package "psmisc"
package "likewise-open"

# Pull the necessary creds from the appropriate authorization databag depending on the ad_network attribute
ad_config = data_bag_item('authorization', node[:authorization][:ad_auth][:ad_network])

# Join the primary_domain if we aren't a member already
execute "initialize-likewise" do
  command "/usr/bin/domainjoin-cli join #{ad_config['primary_domain']} #{ad_config['auth_domain_user']} \"#{ad_config['auth_domain_password']}\""
  only_if "/opt/likewise/bin/lw-get-status |grep -q Status.*Unknown"
end

#ad_config['linux_admins'].each do |admin_group|
#    sudoers "linux-admins" do
#    group admin_group
#  end
#end

# Load the registry file that provides all likewise configuration options
execute "load-reg" do
  command "/opt/likewise/bin/lwregshell import /etc/likewise/lsassd.reg"
  action :nothing
end

# Reload the config to pull in any changes we've made
execute "likewise-config-reload" do
  command "/opt/likewise/bin/lw-refresh-configuration"
  action :nothing
  subscribes :run, resources(:execute => "load-reg"), :immediately
end

# Clear any auth caches
execute "clear-cache" do
  command "/opt/likewise/bin/lw-ad-cache --delete-all"
  ignore_failure true
  action :nothing
  subscribes :run, resources(:execute => "likewise-config-reload"), :immediately
end

# Make sure likewise is started and if it's not then clear the caches, and reload the config
service "likewise" do
  supports :restart => true, :status => true
  action [ :enable, :start ]
  notifies :run, resources(:execute => "clear-cache"), :immediately
end

# Make sure eventlogd lwiod lwregd netlogond are enabled and started
for lwservice in [ "eventlogd", "lwiod", "lwregd", "netlogond"  ] do
  service lwservice do
    supports :restart => true, :status => true
    action [ :enable, :start ]
  end
end

# Build the registry file that contains likewise config options
template "/etc/likewise/lsassd.reg" do
  source "lsassd.reg.erb"
  mode "0644"
  variables(
    :ad_membership_required => ad_config['membership_required']
  )
  notifies :run, resources(:execute => "load-reg"), :immediately
end

# Create a new nsswitch that doesn't include zeroconf settings
cookbook_file "nsswitch.conf" do
  source "nsswitch.conf"
  path "/etc/nsswitch.conf"
  owner "root"
  group "root"
  mode 0644
end