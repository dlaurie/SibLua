#! /usr/bin/env lua
--- wikitree-lifelines.lua  © Dirk Laurie 2017  MIT license like that of Lua
-- Provides Person and Crowd classes with WikiTree field names and 
-- LifeLines-like methods.

-- Person
-- The typical object is just the Lua table representing a Person object.
-- The nested lists returned by getRelatives, getAncestors etc are not 
-- allowed. A front-end should be written that replaces them by lists
-- of Id's. 
-- LifeLines functions that take an INDI as first argument are implemented 
---as member functions of Person, e.g.
--    birth(INDI)    becomes   Person:birth()
--    father(INDI)   becomes   Person:father()

-- Crowd
-- A table of Persons. Keys depend on context, but would mostly be
-- the string version of the WikiTree 'Id', e.g. ["12345678"]. A
-- simplified version of the WikiTree 'Name' stored as 'person.simple'
-- is generated when the Person is created, e.g. 'Laurie-474' becomes 
-- 'Laurie474'. These are used as keys in 'crowd._simple', and thanks to 
-- some metatable magic, can be used to index 'crowd', but should not 
-- be used as an actual index in 'crowd' itself.

-- A Family is a table with children numbered 1,2,...  It has no metatable. 

--[=[ LifeLines emulation

* LifeLines Person and Family functions have Lua counterparts that can be 
called using object notation.

* LifeLines iterators become Lua generic 'for' statements in a fairly
obvious way.

    LifeLines
    :   `children(family,person,cnt) { commands }`
    Lua
    :   `for person,cnt in family:children() do commands end`

* The LifeLines feature that the value of an expression is automatically
written to the output file is not possible in Lua: explicit writes are
required.

1. Global tables

  Indi: A Crowd of all Persons, indexed by string-valued WikiTree Id.
  Indi._Fam:  A table of all Families, indexed by the WikiTree Id of father 
    and mother, formatted as a table literal, e.g. "{1234567,2345678}".
    This table is not updated continually and must be regenerated when
    there is doubt as to its freshness by 'crowd:makeFamilies()'.
 
-- Apart from being accessible by Crowd methods, Indi is also exploited 
-- by some LifeLines functions that need to look up an Id.

2. Iterators on global tables

   forindi, forfam

   These must be called using Lua syntax, i.e.
 
     for indi,int in forindi() do
     for fam,int in forfam() do
        
3. Basic objects
 
Lua types represent the following LifeLines value types:

    null: VOID
    boolean: BOOL
    string: STRING
    number: INT, FLOAT, NUMBER   
    table: EVENT, FAM, INDI, LIST, NODE, SET, TABLE

 [[]=]

local function message(...) 
  io.write(...); io.write('\n') 
end

-- GEDCOM interface

local MONTH = {"JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP",
  "OCT","NOV","DEC"}
local Month = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep",
  "Oct","Nov","Dec"}

local gedcomDate = function(date,status)
-- status not yet available from WikiTree Apps
  local year,month,day
  if type(date) == 'table' then  -- as returned by os.date"*t"
    year,month,day = date.year,date.month,date.day
  elseif type(date)=='string' then   -- as provided by WikiTree API
    year,month,day = date:match"(%d%d%d%d)%-(%d%d)%-(%d%d)"
  else 
    return 
  end
  local D = {}
  local d = tonumber(day)
  local m = tonumber(month) 
  local y = tonumber(year) 
  assert(d and m and y and (y>0 or m==0 and d==0),date)
  assert(m>0 or d==0,date)
  if d>0 then D[#D+1] = day end
  if m>0 then D[#D+1] = Month[m] end
  if y>0 then D[#D+1] = year end
  if #D>0 then return table.concat(D,' ') end
end

local gedcomBirthName = function(person)
  return person.BirthName or person.BirthNamePrivate
end  

local gedcomFamilies = function(person)
  local fams = {}
  for _,spouse in ipairs(person.Spouses) do 
    local dad, mom = person.Id, spouse
    if person.Gender:match"F" then dad, mom = mom, dad end
    fams[#fams+1] = '@' .. familyKey(dad,mom) .. '@'
  end
  return fams   
end 

local gedcomChildren = function(family)
  local children = {}
  for _,child in ipairs(family) do 
    children[#children+1] = '@' .. child.Id .. '@'
  end
  return children
end 
 

local function gedcomAssemble(gedcom,tag,indent)
  if not gedcom then return end
  indent = indent or ''
  local buffer = {indent..gedcom.level}
  buffer[#buffer+1] = gedcom.code
  buffer[#buffer+1] = tag 
  buffer[#buffer+1] = gedcom.data
  buffer = {table.concat(buffer,' ')}
  for k,v in pairs(gedcom) do if k==k:upper() then
    if type(v) == 'table' then
      if #v>0 then -- list
        for _,item in ipairs(v) do
          buffer[#buffer+1] = indent.." "..
            table.concat({gedcom.level+1,k,item},' ')
        end
      elseif next(v) then  -- not empty
        buffer[#buffer+1] = gedcomAssemble(v,k,indent.." ")
      end
    else 
      buffer[#buffer+1] = indent.." "..table.concat({gedcom.level+1,k,v},' ')
    end
  end end
  return table.concat(buffer,'\n')
end

local use = "%s"

--- toGEDCOM(tbl,template)
-- Create a Lua table corresponding to a Level 0 GEDCOM record by 
-- inserting data from 'tbl' into a clone of 'template'. The predefined 
-- templates are in 'gedcomTemplate'; see the comments there for template
-- semantics.
toGEDCOM = function(tbl,template,level)
  level = level or 0
  if type(template)=='string' then return template
  elseif type(template)=='function' then return template(tbl)
  else assert(type(template=='table'),"Illegal type '"..type(template)
    .."' in template at level "..level)
  end
  local key,value = next(template)
  if not key then return end
  local data = tbl[key]
  if not next(template,key) then  -- one-entry table
    if data then
      if type(value)=='string' then 
        if not data or data=='' then return end
        return value:format(data)
      elseif type(value)=='function' then return value(data)
      end
    else return
    end
  end
  local clone={}
  for tag,value in pairs(template) do
    clone[tag] = toGEDCOM(tbl,value,level+1)
  end
  if next(clone) then
    clone.level = level
    return clone
  end
end

--    TEMPLATE ENCODING
-- Suppose the template is used to generate GEDCOM encoding for 'person',
-- and 'key,value' is a pair in the template.
-- * If 'key' is all CAPS, it is the GEDCOM tag. A 'code' field if any
--   comes before the tag, a 'data' field if any, after. E.g.
--   'INDI = { code = {Id="@%s@"},' becomes
--   '0 '..("@%s@"}:format(person.Id).." INDI"
-- * If 'value' is a string, that is the data. E.g.
--   '    TYPE = "wikitree.user_id"' becomes the GEDCOM line
--   '2 TYPE wikitree.user_id'. 
-- * If 'value' is a list of strings, one such line is generated
--   for each string in the list.
-- * If 'value' is a function, that function is applied to 'person' and
--   the result is treated as 'value' is above.
-- * If 'value' is a non-list with more than one pair, toGEDCOM is called
--   recursively. The GEDCOM level number is the depth of nesting in the 
--   template.
-- * If 'value' is a table with only one pair '(wt,action)' and 'person[wt]'
--   does not exist, there is no data. Otherwise:
--   - If 'action' is a string, the data is 'action:format(person[wt])'.
--     Since by far the most common format is "%s", a string named 'use' 
--     is predefined to mean just that.
--   - If 'action' is a function, the data is 'action(person[wt])'.
gedcomTemplate = {
      HEAD = { 
  SOUR = "Lua WikiTree Apps", 
  CHAR = "UTF-8", 
  DATE = { date=gedcomDate }
      };     
      INDI = { code = {Id="@%s@"},
NAME = { data = gedcomBirthName,
  GIVN = {FirstName=use},
  _MIDN = {MiddleName=use},
  NICK = {Nicknames=use},
  SURN = {LastNameAtBirth=use},
  _MARN = {LastNameCurrent=use},  -- also used for current name of men
  };
SEX = {Gender=function(n) return type(n)=='string' and n:sub(1,1) end},
BIRT = {
  DATE = {BirthDate=gedcomDate},
  PLAC = {BirthLocation=use},
  };
DEAT = {
  DATE = {DeathDate=gedcomDate},
  PLAC = {DeathLocation=use},
  };
WWW = {Name="https://www.WikiTree.com/wiki/%s"};
REFN = { data = {Id=use},
  TYPE = "wikitree.user_id",
  };
FAMS = gedcomFamilies,
FAMC = {_FAMC="@%s@"};
      };
      FAM = {  code = {Id="@%s@"},
HUSB = {Husband="@%s@"};
WIFE = {Wife="@%s@"};
CHIL = gedcomChildren,
MARR = { 
  DATE = {MarriageDate=gedcomDate},
  PLAC = {MarriagePlace=use}
  };
      } 
}

local exportGEDCOM = function(tbl,tag)
  return gedcomAssemble(toGEDCOM(tbl,gedcomTemplate[tag]),tag)
end

-------- end of GEDCOM interface --------

-- Custom global function 'all'
-- To be used instead of 'pairs' when the key is irrelevant.
--   for value[,num] in all(tbl) do ... end
-- Omits keys with underscores
-- Optional return value 'num' is incremented at each call.
function all(tbl)
  local key=nil
  local num=0
  return function()
    local val
    repeat 
      key, val = next(tbl,key)
    until key==nil or not (type(key)=='string' and key:match"^_")
    num = key and num+1
    return val,num
  end
end

-- create empty classes
local metaPerson, metaCrowd = {}, {}
local Person = setmetatable({},metaPerson)
local Crowd = setmetatable({},metaCrowd)
Person.__index = Person
-- Crowd.__index will be provided later

local utf8_transliteration = { ["é"]="EE", ["ê"]="ES", ["ä"]="AE", ["ō"]="OE", 
  ["ü"]="UE", ["ß"]="SS", ["ñ"]="NI" }

--- count keys, except those starting with an underscore
local countKeys = function(crowd)
  local n=0
  for v in all(crowd) do n=n+1 end
  return n
end

-- return fields as an array
local function fields(tbl)
  local f = {}
  for k in pairs(tbl) do if type(k)=="string" and not k:match"^_" then
    f[#f+1] = k
  end end
  table.sort(f)
  return(f)
end

--- serialize list only, not general table
local function serialize(tbl)
  if type(tbl)~='table' then return tostring(tbl) end
  local t={}
  local sep = ","
  for k,v in ipairs(tbl) do 
    if type(v)=='table' then sep=";" end
    t[k]=serialize(v) 
  end
  return "{"..table.concat(t,sep).."}"
end

--- nonblank(s) is s if s is a non-blank string, otherwise false
local function nonblank(s)
  return type(s)=='string' and s:match"%S" and s
end

--- nonblank(s) is s if s is a string containing [1-9], otherwise false
local function nonzero(s)
  return type(s)=='string' and s:match"[1-9]" and s
end

--- 'by': sorting function to sort tables by specified key
-- e.g. table.sort(tbl,by'name')
local function by(key)
  return function(a,b)
    local ak, bk = a[key], b[key]
    if type(ak)==type(bk) and ak<bk then return true end
  end
end

--- simplify(Name,list)
-- Convert Name to a legal Lua name if possible, otherwise return it unchanged.
-- "Possible" means that all non-ASCII UTF-8 codepoints have been provided for.
-- Examples: 
--   "van der Merwe-25"  --> van_der_Merwe25
--   "Cronjé-10"         --> CronjEE10
-- If Name already occurs in 'list', a non-false second value is also returned
local simplify = function(Name,list)
  if not Name then return false end
  local simplest = Name:gsub(" ","_"):gsub("-","")
  local simple = simplest
  for k,v in pairs(utf8_transliteration) do
    simple = simple:gsub(k,v)
  end
  if simple:match"^[%a%w_]+$" then 
    Name=simple 
    if simple~=simplest then
      message("'"..simplest.."' referred to as '"..simple.."'")
    end
  end   
  return Name, (type(list)=='table' and list[Name])
end

-- WikiTree API sometimes returns numbers as strings. This matters in 
-- JSON and also matters in Lua, so we make sure integers are numbers.
local function convert_integers(tbl)
  for k,v in pairs(tbl) do
    v = tonumber(v)
    if math.type(v)=='integer' then tbl[k]=v end
  end
end

--- 

local isPerson = function(tbl)
  return getmetatable(tbl)==Person
end

local isCrowd = function(tbl)
  return getmetatable(tbl)==Crowd
end

--- import/export to Lua

-- crowd:toLua() Generate a Lua table literal for a list of Persons in a Crowd
Crowd.toLua = function(crowd)
  local lua = {}
  for person in all(crowd) do
    lua[#lua+1] = person:toLua()
  end
  return "{\n"..table.concat(lua,";\n").."\n}"
end

-- crowd:fromLua() Generate a Crowd from a Lua table literal.
-- Loses field _start.
Crowd.fromLua = function(lua)
  local data = load("return "..lua)
  assert(data,"failed to load Crowd code")
  data = data()
  local crowd = {}
  for _,person in ipairs(data) do
    local key = tostring(person.Id)
    assert(key~='nil',"Person with no Id")
    crowd[key] = Person(person)
  end
  return Crowd(crowd)
end

Crowd.save = function(crowd,filename)
  local lua=crowd:toLua()
  local file=io.open(filename,"w")
  file:write(lua):close()
end

Crowd.load = function(filename)
  local file=io.open(filename)
  return Crowd.fromLua(file:read"a")
end

local bool = {[true]='true',[false]='false'}

-- person:toLua() Generate a Lua table literal for a Person
Person.toLua = function(person)
  local lua = {}
  for k,v in pairs(person) do
    assert(type(k)=='string' and k:match"^%a",
           "bad key '"..tostring(k).."' in Person")
    if type(v) == 'table' then
      v = '{'..table.concat(v,",")..'}'
    elseif type(v) == 'string' then
      v = '"' .. v ..'"'
    elseif type(v) == 'boolean' then
      v = bool[v]
    elseif type(v) ~= 'number' then
      error("Can't handle field '"..k.."' of type "..type(v).." in a Person")
    end
    lua[#lua+1] = k .. '=' .. v
  end
  return "  { "..table.concat(lua,";\n    ").."\n  }"
end

-- person:toLua() Generate Person from a Lua table literal
Person.fromLua = function(lua)
  local person = load("return "..lua)
  assert(person,"failed to load Person code: "..person)
  return Person(person())
end

--- export to GEDCOM

Crowd.toGEDCOM = function(crowd)
  crowd:makeFamilies()
  local buffer = { exportGEDCOM( {date=os.date"*t"}, "HEAD") }
  for person in all(crowd) do
    buffer[#buffer+1] = person:toGEDCOM()  
  end
  for id,family in pairs(crowd._Fams) do
    buffer[#buffer+1] = exportGEDCOM(family,"FAM")
  end
  buffer[#buffer+1]="0 TRLR"
  return table.concat(buffer,"\n")
end
  
Crowd.readGEDCOM = function(crowd,filename)
  message"not implemented:  Crowd.readGEDCOM"
end

Crowd.writeGEDCOM = function(crowd,filename)
  local ged = crowd:toGEDCOM()
  io.open(filename,"w"):write(tostring(ged)):close()
  message("Wrote "..filename)
end

Person.toGEDCOM = function(person)
  return exportGEDCOM(person,"INDI")
end


--- Crowd methods

Crowd.__len=countKeys

--- Crowd:init(tbl) or Crowd(tbl)
-- Turn a table of Persons into a Crowd (numeric keys and those starting
-- with an underscore are ignored)
Crowd.init = function(class,crowd)
  for v in all(crowd) do
    if not isPerson(v) then
      error("at key "..k..": non-person found in array")
    end
  end
  crowd._simple = {}
  for v in all(crowd) do crowd._simple[v.simple] = v end
  return setmetatable(crowd,class)
end
metaCrowd.__call=Crowd.init

Crowd.__newindex = function(crowd,key,value)
  key = tostring(key)
  if not key:match"^_" then  -- skip hidden keys
    if not isPerson(value) then
      error("Attempt to assign non-person to key"..key)
    end
    crowd._simple[value.simple] = value
  end
  rawset(crowd,key,value)
end

--- crowd:find(target[,targets])
-- Return a sublist containing only entries whose refname matched 'target', 
-- further filtered on whether selected fields match the patterns supplied 
-- in 'targets'. NB: If you need equality, anchor the pattern, i.e. "^John$".
--   crowd:find("Laurie",{Name="Dirk"})
Crowd.find = function(crowd,target,targets)
  targets = targets or {}
  local found = setmetatable({},{__len=countKeys})
  for v in crowd:indi() do 
    local matches = v:refname():match(target) 
    if matches then
      for j,u in pairs(targets) do
        if not (v[j] and v[j]:match(u)) then
          matches = false
          break
        end
      end
    end  
    if matches then found[v.simple] = v end
  end
  return found
end

--- crowd:cache(person)
-- Store or merge person into crowd by Id
Crowd.cache = function(crowd,person)
  assert(type(person)=='table' and person.Id,
    "Can't cache something with no Id")
  local Id = tostring(person.Id)
  local old = crowd[Id]
  if not old then crowd[Id] = Person(person)
  else old:merge(person)
  end
end

familyKey = function(father,mother)
  local parents = {}
  parents[#parents+1] = (father ~= null) and father
  parents[#parents+1] = 'x'
  parents[#parents+1]= (mother ~= null) and mother
  if #parents>1 then return table.concat{father,'x',mother} end
end

--- crowd:makeFamilies(childless)
-- Creates a table 'crowd._Fams' of families involving persons in 'crowd'.
-- If 'childless' is true, families are also created for married couples
-- that have no children recorded in 'crowd'.
Crowd.makeFamilies = function(crowd,childless)
  if crowd._Fams then return end
  local Fam = {}
  crowd._Fams = Fam
  for person in all(crowd) do
    local father, mother = person.Father, person.Mother
    local key = familyKey(father,mother)
    if key then
      local fam = Fam[key] or {Husband=father,Wife=mother,Id=key}
      Fam[key] = fam
      fam[#fam+1] = person
      person._FAMC = key
    end
  end
  for _,v in pairs(Fam) do
    table.sort(v,by"BirthDate")
  end
  if not childless then return end
  for person in all(crowd) do
    local father = person.Id
    local spouses = person.Spouses
    if spouses then for _,mother in pairs(spouses) do
      local father = father
      spouse = crowd[mother]
      if spouse then
        if person.Gender=='Female' and spouse.Gender=='Male' then
          father, mother = mother, father
        end
        local key = familyKey(father,mother)
-- TODO: the print statement below is not reached with the current test data
if not Fam[key] then print("Creating childless family "..key) end
        Fam[key] = Fam[key] or {Husband=father,Wife=mother,Id=key}
      end
    end end 
  end
end

Crowd.toSAG = function(crowd)
  message"not implemented: Crowd.toSAG"
end

--- functions modelled on LifeLines that need a Crowd as context

--- for v,n in crowd:indi() do
--  iterates through a Crowd
Crowd.indi = function(crowd)
  return all(crowd)
end


--- Person methods

--- Person:init(tbl) or Person(tbl)
-- Turn a table into a Person
Person.init = function(class,person)
  if isPerson(person) then return person end
  assert(type(person)=='table',"Can't make a Person from a "..type(person))
  assert(person.Id,"Trying to make a Person without field Id; has " ..
    table.concat(fields(person),","))
  local Id = tostring(person.Id)
  person.simple = simplify(person.Name) or Id
  setmetatable(person,class)
  if isCrowd(Indi) then Indi:cache(person) end
  return person
end
metaPerson.__call=Person.init

Person.refname = function(person)
  return(person:name(false,false,false,true,true))
end
Person.__tostring=Person.refname

local merge_decision = {}
--- person:merge(new)
-- Store fields from 'new' in 'person' if they seem to be better.
Person.merge = function(person,new)
  local mustReplace = function(key,old,new)
    if new == null or new==old then return false end
    if old == nil or old == null then return true end
    if merge_decision[key]~=nil then return merge_decision[key] end
    if type(old)=='table' and type(new)=='table' then
      -- tables are already known to be different if we get here
      if #old==0 then return true
      elseif #new==0 then return false
      end
      old, new = serialize(old), serialize(new)
      if old==new then return false end
    end
    print(person.Name..": Merge values for key "..key.." differ: ",old,new)
    print"Should the second value replace the first [Yes,No,Always,neVer])?"
    local reply = io.read():sub(1,1):upper()
    if reply=="A" then merge_decision[key]=true; reply="Y" 
    elseif reply=="V" then merge_decision[key]=false; reply="N"
    end
    return reply=="Y"
  end 
----
  if new==nil then return person end
  assert (isPerson(person) and type(new)=='table', 
    "merge called with invalid arguments")
  assert (new.Id, "No Id for 'new', fields are "..table.concat(fields(new)))
  assert (person.Id == new.Id, 
    ("in 'merge', person.Id is %s but new.Id is %s of type %s"):format(
     person.Id,new.Id,type(new.Id)))
  for k,v in pairs(new) do 
    if mustReplace(k,person[k],v) then person[k]=v end 
  end
  return person
end

--- functions modelled on LifeLines that need a Person as context.

--- returns {date=,place=,decade=}. 'decade' only if 'date' is omitted.
Person.birth = function(person)
  return {date=person.BirthDate, place=person.BirthLocation,
          decade=person.BirthDecade}
end

Person.father = function(person)
  return Indi[person.Father]
end

Person.mother = function(person)
  return Indi[person.Mother]
end

--- person:name(surnameupper,surnamefirst,trimto,withdates,bothnames)
-- Approximately LifeLines 'name' and 'fullname', except that
-- *  "/.../" (second parameter of LifeLines 'name') is not supported 
-- *  'trimto' is not implemented yet
-- *  'withdates' adds birth and death dates if available
-- *  'bothnames' gives LNC in parentheses
Person.name = function(p,surnameupper,surnamefirst,trimto,withdates,bothnames)
  local parts={}
  local function insert(item, format)
    if not nonblank(item) then return end
    if type(format)=="string" then item = format:format(item) end
    parts[#parts+1] = item
  end
  local function insertsurname()
    insert(p:surname(surnameupper,bothnames),surnamefirst and "%s,") 
  end
  ------
  if surnamefirst then insertsurname() end
  insert(p.Prefix)
  insert(p.FirstName)
  insert(p.MiddleName)
  if not surnamefirst then insertsurname() end
  insert(p.Suffix)
  if withdates then
    insert(nonzero(p.BirthDate),"* %s")
    insert(nonzero(p.DeathDate),"+ %s")
  end
  return table.concat(parts," ")
end


local child_of = {
  Afr = {Male="s.v.",Female="d.v.",Child="k.v.",AND="en"};
  Eng = {Male="s.o.",Female="d.o.",Child="c.o.",AND="and"};
}
--- person:toSAG(options)
-- SAG representation of person as a string
-- 'options' is a table in which the following are recognized
--   withSurname=false  Omit surname (must be exactly the boolean `false`)
--   withparents=1      Any Lua true value will do
--   lang='Any'         Default is 'Afrikaans'. Specifying an unsupported
--                      language is tantamount to 'English'.
Person.toSAG = function(p,options)
  options = options or {}
  local parts={}
  local function insert(item, format)
    if not nonblank(item) then return end
    if type(format)=="string" then item = format:format(item) end
    parts[#parts+1] = item
  end
  local insertEvent = function(code,place,date)
    date = nonzero(date)    
    place = nonblank(place)
    if not (place or date) then return end
    insert(place or date,code.." %s")
    if place and date then insert(date) end
  end
---
  insert(p.FirstName)
  insert(p.MiddleName)
  if not (options.withSurname == false) then
    insert(p:surname(true))  -- uppercase
  end
  insertEvent("*",p.BirthLocation,p.BirthDate)
  insertEvent("~",p.BaptismLocation,p.BaptismDate)
  insertEvent("+",p.DeathLocation,p.DeathDate)
  if options.withParents then while true do
    local father, mother = p:father(), p:mother()
    if not (father or mother) then break end
    father = father and father:name(true)
    mother = mother and mother:name(true)
    options.language = options.language or "Afrikaans"
    options.language = options.language:sub(1,3)
    local lang = child_of[options.language] or child_of.Eng
    local CO = p.Gender or "Child"  
    if father and mother then
      insert(("%s %s %s %s"):format(lang[CO],father,lang.AND,mother))
    else
      insert(("%s %s"):format(lang[CO],father or mother))
    end
    break
  end end  
  return table.concat(parts," ")
end
    
--- person:surname(surnameupper,surnamefirst)
-- Approximately LifeLines 'surname' and 'fullname', except that
-- the options to capitalize the surname and to give two surnames
-- are available.
Person.surname = function(p,surnameupper,bothnames)
  local LNAB = nonblank(p.LastNameAtBirth) 
  local LNC = nonblank(p.LastNameCurrent)
  if surnameupper then 
    LNAB, LNC = LNAB and LNAB:upper(), LNC and LNC:upper()
  end
  if LNAB then
    if bothnames and LNC and LNC~=LNAB then 
      LNAB = LNAB .. " x "..LNC 
    end
  else
    LNAB = LNC
  end
  return LNAB
end   

Crowd.__index = function(crowd,key)
  -- numeric keys or methods
  local item = rawget(Crowd,key) or rawget(crowd,tostring(key))
  if item then return item end
  local simple = crowd._simple
  if simple then
    item = rawget(simple,key)
    if item then return item end
  end
end  

-- suppy global tables
Indi = Crowd{}

return {Person=Person, Crowd=Crowd, isPerson=isPerson, isCrowd=isCrowd}
