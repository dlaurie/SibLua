#! /usr/bin/env lua
-- wikitree-api.lua  © Dirk Laurie 2017  MIT license like that of Lua
-- Lua module for accessing the WikiTree database via the API as
-- described in https://www.wikitree.com/wiki/API_Documentation.

---    Module 'wikitree-api'
-- The module returns a single function, to be used as follows:
--   login = require"wikitree-api"
--   session, data = login(email,password)
-- If anonymous login is good enough for your purpose, then this is enough:
--   session, data = login()
-- You can have more than one session active at the same time.
-- 'session' is a CURL session, with metatable enriched to accept the
-- following commands:
--   data = session:wt_json(action,params)
--   tbl = session:wt_decode(action,params)
-- Here, 'action' is one of the commands recognized by the WikiTree API,
-- and 'params' is a table of parameters, e.g.
--   wl = session:wt_decode("getWatchlist",{fields="Id,Name,Touched"})
-- The return value 'data' is JSON code, and 'tbl' is a Lua table into which
-- the JSON object or array has been decoded.

local server = "https://apps.wikitree.com/api.php"

-- Preassign a global "message" if you don't like "print".

local message = message or print

--- Required module: curl
-- You can either preload your favourite module (it must have 'curl.easy') 
-- and assign it to the global variable 'curl', or you can install one that
-- provides 'lcurl' via LuaRocks:   luarocks install "lua-curl"

local curl = curl or require"lcurl"

if curl and type(curl)=='table' and type(curl.easy)=='function' then 
else
  message "No 'curl.easy' found. Bailing out.\n"
  return
end

--- Required module: json
-- You can either preload your favourite module (it must have 'json.decode') 
-- and assign it to the global variable 'json', or you can install one that
-- provides 'rapidjson' via LuaRocks:   luarocks install "rapidjson"

json = json or require"rapidjson"

if json and type(json)=='table' and type(json.decode)=='function' then 
else
  message "No 'json.decode' found. Bailing out.\n"
  return
end
  
-- forward declaration of upvalues for 'login'

local logins = {}
local API, logout, decode

--- session, data = login(email,password)
-- Attempts to log you in to apps.wikitree.com. Returns a 'session' even if 
-- unsuccessful (in that case, you will be treated as anonymous). 'data' is
-- the decoded output returned by the login attempt.
local login = function(email,password)
  local session = curl.easy()
  local cookies
  if curl.OPT_COOKIEFILE and curl.OPT_COOKIEJAR then
    cookies = os.tmpname()
    session:setopt(curl.OPT_COOKIEFILE,cookies)
    session:setopt(curl.OPT_COOKIEJAR,cookies)
    logins[session] = cookies
  else
    message("Your 'curl' does not support cookies. You will be anonymous.")
  end
  local mt = getmetatable(session)
  mt.wt_json = API
  mt.wt_decode = decode
  mt.logout = logout
  local param = {email=email,password=password}
  return session, session:wt_decode('login',param)
end

--- API(command,param)
-- Performs the API command and returns everything it sends back as a string.
API = function(session,command,param)
  local data = {}
  local function writefunction(x)
    table.insert(data,x)
    return true
  end
  local url = {"action="..command}
  for k,v in pairs(param) do
    url[#url+1] = ("%s=%s"):format(k,v)
  end
  command = ("%s?%s"):format(server,table.concat(url,"&"))
  session:setopt{url=command,writefunction=writefunction}:perform()
  last_data = data
  return table.concat(data)
end

--- decode(command,param)
--  Performs the API command, and returns a decoded version of its output.
decode = function(session,command,param)
  return json.decode(API(session,command,param))
end 

logout = function(session)
  message"Once logged in, you can't logout from that session except by quitting.\nWork in a new anonymous session instead."
end
  
return login


