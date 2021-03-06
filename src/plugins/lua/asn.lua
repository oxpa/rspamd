--[[
Copyright (c) 2011-2016, Vsevolod Stakhov <vsevolod@highsecure.ru>
Copyright (c) 2016, Andrew Lewis <nerf@judo.za.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
]]--

local rspamd_logger = require "rspamd_logger"
local rspamd_regexp = require "rspamd_regexp"
local lua_util = require "lua_util"
local N = "asn"

if confighelp then
  return
end

local options = {
  provider_type = 'rspamd',
  provider_info = {
    ip4 = 'asn.rspamd.com',
    ip6 = 'asn6.rspamd.com',
  },
  symbol = 'ASN',
  expire = 86400, -- 1 day by default
  key_prefix = 'rasn',
  check_local = false,
}

local rspamd_re = rspamd_regexp.create_cached("[\\|\\s]")

local function asn_check(task)

  local function asn_set(asn, ipnet, country)
    local descr_t = {}
    if asn then
      task:get_mempool():set_variable("asn", asn)
      table.insert(descr_t, "asn:" .. asn)
    end
    if ipnet then
      task:get_mempool():set_variable("ipnet", ipnet)
      table.insert(descr_t, "ipnet:" .. ipnet)
    end
    if country then
      task:get_mempool():set_variable("country", country)
      table.insert(descr_t, "country:" .. country)
    end
    if options['symbol'] then
      task:insert_result(options['symbol'], 0.0, table.concat(descr_t, ', '))
    end
  end

  local asn_check_func = {}
  function asn_check_func.rspamd(ip)
    local dnsbl = options['provider_info']['ip' .. ip:get_version()]
    local req_name = rspamd_logger.slog("%1.%2",
        table.concat(ip:inversed_str_octets(), '.'), dnsbl)
    local function rspamd_dns_cb(_, _, results, dns_err)
      if dns_err and (dns_err ~= 'requested record is not found' and dns_err ~= 'no records with this name') then
        rspamd_logger.errx(task, 'error querying dns (%s): %s', req_name, dns_err)
      end
      if not (results and results[1]) then return end
      local parts = rspamd_re:split(results[1])
      -- "15169 | 8.8.8.0/24 | US | arin |" for 8.8.8.8
      asn_set(parts[1], parts[2], parts[3])
    end

    task:get_resolver():resolve_txt(task:get_session(), task:get_mempool(),
        req_name, rspamd_dns_cb)
  end

  local ip = task:get_from_ip()
  if not (ip and ip:is_valid()) or (not options.check_local and ip:is_local()) then return end
  asn_check_func[options['provider_type']](ip)
end

-- Configuration options
local configure_asn_module = function()
  local opts =  rspamd_config:get_all_opt('asn')
  if opts then
    for k,v in pairs(opts) do
      options[k] = v
    end
  end
  if options['provider_type'] == 'rspamd' then
    if not options['provider_info'] and options['provider_info']['ip4'] and
        options['provider_info']['ip6'] then
      rspamd_logger.errx("Missing required provider_info for rspamd")
      return false
    end
  else
    rspamd_logger.errx("Unknown provider_type: %s", options['provider_type'])
    return false
  end
  return true
end

if configure_asn_module() then
  local id = rspamd_config:register_symbol({
    name = 'ASN_CHECK',
    type = 'prefilter,nostat',
    callback = asn_check,
    priority = 5,
    flags = 'empty',
  })
  if options['symbol'] then
    rspamd_config:register_symbol({
      name = options['symbol'],
      parent = id,
      type = 'virtual',
      flags = 'empty',
    })
  end
else
  lua_util.disable_module(N, 'config')
end
