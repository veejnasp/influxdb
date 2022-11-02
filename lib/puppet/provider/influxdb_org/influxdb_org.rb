# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'
require_relative '../../../puppet_x/puppetlabs/influxdb/influxdb'

# Implementation for performing initial setup of InfluxDB using the Resource API.
class Puppet::Provider::InfluxdbOrg::InfluxdbOrg < Puppet::ResourceApi::SimpleProvider
  include PuppetX::Puppetlabs::PuppetlabsInfluxdb
  def initialize
    @canonicalized_resources = []
    super
  end

  def canonicalize(_context, resources)
    init_attrs(resources)
    resources
  end

  def get(_context)
    init_auth
    get_org_info
    get_user_info

    response = influx_get('/api/v2/orgs', params: {})
    if response['orgs']
      response['orgs'].reduce([]) do |memo, value|
        org_members = @org_hash.find { |org| org['name'] == value['name'] }.dig('members', 'users')
        memo + [
          {
            name: value['name'],
            use_ssl: @use_ssl,
            host: @host,
            port: @port,
            token: @token,
            token_file: @token_file,
            ensure: 'present',
            members: org_members ? org_members.map { |member| member['name'] } : [],
            description: value['description']
          },
        ]
      end
    else
      [
        {
          influxdb_host: @influxdb_host,
          org: nil,
          ensure: 'absent',
          description: nil,
        },
      ]
    end
  end

  def create(context, name, should)
    context.debug("Creating '#{name}' with #{should.inspect}")
    body = {
      name: name,
      description: should[:description],
    }
    influx_post('/api/v2/orgs', JSON.dump(body))
  end

  # TODO: make this less ugly
  def update(context, name, should)
    context.debug("Updating '#{name}' with #{should.inspect}")
    org_id = id_from_name(@org_hash, name)
    org_members = @org_hash.find { |org| org['name'] == name }.dig('members', 'users')
    cur_members = org_members ? org_members : []
    should_members = should[:members] ? should[:members] : []

    to_remove = cur_members.map { |member| member['name'] } - should_members
    to_add = should_members - cur_members.map { |member| member['name'] }

    to_remove.each do |user|
      next if user == 'admin'

      user_id = id_from_name(@user_map, user)
      if user_id
        influx_delete("/api/v2/orgs/#{org_id}/members/#{user_id}")
      else
        context.warning("Could not find user #{user}")
      end
    end

    to_add.each do |user|
      user_id = id_from_name(@user_map, user)
      if user_id
        body = { name: user, id: user_id }
        influx_post("/api/v2/orgs/#{org_id}/members", JSON.dump(body))
      else
        context.warning("Could not find user #{user}")
      end
    end

    body = { description: should[:description], }
    influx_patch("/api/v2/orgs/#{org_id}", JSON.dump(body))
  end

  def delete(context, name)
    context.debug("Deleting '#{name}'")

    id = id_from_name(@org_hash, name)
    influx_delete("/api/v2/orgs/#{id}")
  end
end
