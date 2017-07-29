#! /usr/bin/env lua
-- wikitree-apps.lua  © Dirk Laurie 2017  MIT license like that of Lua
-- High-level routines
---   lua -l help=ihelp -l apps=wikitree-apps
--[=[ 
Sample Session 1
  apps:init() -- logs in to WikiTree, exploiting $HOME/.wikitree if any, 
              -- prompts for missing items
  help(apps)  -- shows available apps
  help(apps.getNucleus) -- prints how to use this one
  nucleus = apps:getNucleus("Laurie-478",2) -- get everybody within two 
    -- families of my paternal grandfather directly from the WikiTree database
  nucleus:save"nucleus.luax" -- save 'nucleus' to the specified file.
    -- 'luax' is for "Lua expression". The format is so close to JSON that
       people who know JSON will have no problem reading and even manually
       editing it.
  ged = nucleus:toGEDCOM()  -- convert to GEDCOM
  io.open("nucleus.ged","w"):write(ged):close()  -- save GEDCOM file

Sample Session 2
  nucleus = Crowd.load"nucleus.luax" -- a file previously saved
  me = nucleus.Laurie474 -- retrieve record by simplified WikiTree code
  me --> Dirk Pieter Laurie * 1946-01-05
  mom = me:mother()  -- record of my mother
  mom:father() --> nil; my maternal grandfather is my paternal grandfather's
               -- son's wife's father, i.e. three families away, one too many
  help(mom) -- displays available fields in record
  mom.Father --> 14418966 (WikiTree numerical ID is available)
  inlaws = apps:getNucleus(mom.Father,2,"x+")  
    -- grandpa's descendants with spouses

Sample Session 3
  apps:init()
  ancestors = apps:getAncestors("Laurie-474",5)
  for k=1,#ancestors do print(k,ancestors[k]) end  
    -- there may be holes,
    -- so ipairs will miss out, but there is a __len metamethod 

Not implemented yet

  inlaws:toSAG() --> descendant table in SAG format
  oldnucleus = nucleus:readGEDCOM"nucleus.ged" -- read from local GEDCOM
  nucleus:writeGEDCOM"nucleus.ged"  -- write to local GEDCOM

--]=]
  
local pattern = dofile"jsons.lua"
null = function() end
json = { decode = function(code)
  return pattern:match(code)
  end }

login = require"wikitree-api"
local LL = require"wikitree-lifelines"
Person, Crowd = LL.Person, LL.Crowd
isPerson, isCrowd = LL.isPerson, LL.isCrowd
Indi = Crowd{}

local function message(...) io.write(...); io.write('\n') end

--- resource, wikitreerc = getResources(wikitreerc)
-- read resource file 'wikitreerc" (default: ".wikitreeec" in your
-- home directory
local getResources = function(wikitreerc)
  wikitreerc = wikitreerc or os.getenv"HOME".."/.wikitreerc"
  local rc = io.open(wikitreerc)
  local ok, resource
  if rc then 
    message ("Reading credentials from resource file "..wikitreerc)
    rc.close()
    ok, resource = pcall(dofile,wikitreerc)
    if not ok then return ok, resource 
    else return resource, wikitreerc
    end
  end
end

-- The data structures belonging to a particular session are stored
-- in a table called 'wt' in the comments to the following routines.

--- wt:init(wikitreerc)
-- Front-end to API login that retrieves options frm a resource file.
-- wikitreerc: name of resource file (defaults to "$HOME/.wikitreerc")
local init = function(wt,wikitreerc)
  local resource, wikitreerc = getResources(wikitreerc)
  resource = resource or {}
  wt.resource = resource
  local email = resource.email or prompt("Email Address = ? ")
  if email:match"%S" then 
    for try=1,3 do
      local password = resource.password or prompt("Password = ? ")
      message"Logging in to apps.wt.com"
      local session, data = login(email,password)
      wt.username = data.login.username
      wt.session = session
      if wt.username then        
        message ("You are logged in to apps.wt.com as "..wt.username)
        wt.userid = data.login.userid
        break
      end  
    end 
  end
end  

local relatives = {Spouses='x',Parents='-',Children='+',Siblings='='}

--- crowd = wt:getNucleus(keys,radius,code)
-- Collect all Persons not more than 'radius' steps away from the Persons
-- with the specified keys into a single Crowd keyed by their WikiTree Id
-- numbers. 'code' determines what counts as a relative; default "+-=x".
--    '-'  Parents
--    '+'  Children
--    '='  Siblings
--    'x'  Spouses
-- code = '' is a perfectly reasonable thing to do: it gives you only
-- the Persons themselves, but with all available fields, including some
-- not listed in the WikiTree API documentation.
local getNucleus = function(wt,key,radius,code)
  local new     
  local crowd = Crowd{}
  local function include(list)
    if type(list)~='table' then return end
    for key,value in pairs(list) do
      assert(key==tostring(value.Id),"key and value.Id do not match")
      crowd:cache(value)
      new[key] = true
      list[key] = crowd[key]     
    end 
  end
--- 
  radius = radius or 1
  code = code or "+-=x"
  local keys = tostring(key)
  local start = {}
  for s in keys:gmatch"[^,%s]+" do start[#start+1] = s end
  local done = {}
  for iter=1,radius do
    local data = wt.session:wt_decode('getRelatives',{keys=keys,
      getParents=code:match"-" and 1 or 0,
      getChildren=code:match"+" and 1 or 0,
      getSiblings=code:match"=" and 1 or 0,
      getSpouses=code:match"x" and 1 or 0})
    new={}
    for k,item in ipairs(data[1].items) do
      local id = tostring(item.user_id)
      assert(not done[id],"item "..id.." has already been done")
      local person = item.person
-- If the person is Unlisted, there is no Name, but we can get it
      person.Name = person.Name or item.user_name
      crowd:cache(person)
      done[id] = true
      include(person.Spouses)
      include(person.Parents)
      include(person.Siblings)
      include(person.Children)
    end
    keys = {}
    for key in pairs(new) do if not done[key] then
      keys[#keys+1] = key
    end end
    if #keys==0 then break end
    keys = table.concat(keys,",")
  end
-- replace person lists by key lists in Parents etc
  for person in all(crowd) do
    for k in pairs(relatives) do
      local p = person[k]
      local list = {}
      if p then for id in pairs(p) do
        list[#list+1] = id
      end end
      person[k] = list
    end
  end          
  crowd._start = start
  return crowd
end

--- crowd = wt:getWatchlist(options)
-- Gets the user's Watchlist as a Crowd indexed by their WikiTree Id 
-- numbers as strings. 'options' defaults to
-- {getSpace=0,fields="Id,Name,FirstName,BirthDate,DeathDate,Touched"}
local getWatchlist = function(wt,options)
  local data = wt.session:wt_decode('getWatchlist',options or
    {getSpace=0,fields="Id,Name,FirstName,BirthDate,DeathDate,Touched"})
  local crowd = Crowd{}
  for _,v in ipairs(data[1].watchlist) do
    crowd:cache(v)
  end
  return crowd
end

--- crowd = wt:getAncestors(key,depth)
-- Gets the ancestors of the Person with the specified key to the specified
-- depth as an array keyed by the Ahnentafel codes.
local getAncestors = function(wt,key,depth)
  local data = wt.session:wt_decode('getAncestors',{key=key,depth=depth})
  local crowd = {}
  for k,v in pairs(data[1].ancestors) do 
    crowd[tostring(v.Id)] = Person(v)
  end
  local ahnentafel = {data[1].ancestors[1],last=1}
  local done
  local function append(index,record)
    if not record then return end
    ahnentafel[index] = record
    ahnentafel.last = index
    done = false
  end
  local n=1
  local last
  repeat
    done=true
    for m=n,2*n-1 do
      local person = ahnentafel[m]
      if person then
        local father = crowd[tostring(person.Father)]
        local mother = crowd[tostring(person.Mother)]
        append(2*m,father)
        if father then last=2*m end
        append(2*m+1,mother)
        if mother then last=2*m+1 end
      end
    end
    n=2*n
  until done
  return setmetatable(ahnentafel,{__len=function() return last end})
end

return {init=init, getNucleus=getNucleus, getWatchlist=getWatchlist,
  getAncestors=getAncestors, }
