--locals
--tables
local active_badge = {
	Desc = nil,
	GetVals = {1},
	Goal = 1,
	Has = false,
	HasMax = true,
	Icon = nil,
	Name = nil,
	ProgName = nil
}

local badge_index = 1
local badges = {
	{ --default
		Desc = "Posses the Quantum badge.",
		Icon = "autobox/scoreboard/badges/quantum.vmt",
		Name = "Quantum",
		ProgName = "Quantum Badge Wielder"
	}
}

--generic crap
local developer = GetConVar("developer")
local fetch_fails = 0
local fetch_list = {}
local fetch_pastebin
local fl_ScoreboardShow = AAT_Scorebaord_ScoreboardShow
local max_fetch_fails = 3
local set_active_badge

--local functions
local function clean_internet_badges()
	--remove badges grabbed from pastebin
	local index = 1
	
	while index <= #badges do
		local badge = badges[index]
		
		if badge.InternetBadge then table.remove(badges, index)
		else index = index + 1 end
	end
	
	set_active_badge(1)
end

local function developer_print(...) if developer:GetBool() then print(...) end end

local function fetch_all(no_request)
	--client only
	--get all of the badges from all pastebin lists
	clean_internet_badges()
	
	if fetch_list and not table.IsEmpty(fetch_list) and not no_request then
		net.Start("abx_quantum_badge")
		net.SendToServer()
	else fetch_pastebin() end
end

local function fetch_completed(body, headers)
	--we got the fetch, parse it
	fetch_fails = 0
	
	local post_fix = table.remove(fetch_list)
	
	if body and post_fix then
		developer_print("[AQB] Got raw data for source " .. post_fix)
		
		for index, line in ipairs(string.Split(body, "\n")) do
			local parts = string.Split(string.gsub(line, "%c", ""), ":::")
			local name = parts[1]
			
			developer_print("    #" .. index ..  ': "' .. name .. '"')
			
			table.insert(badges, math.random(1, #badges), {
				Desc = parts[2],
				Icon = Material(parts[3]),
				InternetBadge = true,
				Name = name,
				ProgName = parts[1]
			})
		end
		
		developer_print()
	end
	
	--if we have more, fetch them
	if not table.IsEmpty(fetch_list) then fetch_pastebin() end
end

local function fetch_fail(...)
	--if we fail, give 3 retries, and then just skip it
	if fetch_fails >= max_fetch_fails then
		fetch_fails = 0
		
		developer_print("[AQB] Failed fetch after " .. max_fetch_fails .. " retries.\n    Fail data: ", ...)
		developer_print()
		
		table.remove(fetch_list)
		
		if not table.IsEmpty(fetch_list) then fetch_pastebin() end
	else
		fetch_fails = fetch_fails + 1
		
		developer_print("[AQB] Failed fetch, retrying. (" .. fetch_fails .. "/" .. max_fetch_fails .. ")\n    Fail data: ", ...)
		
		fetch_pastebin()
	end
end

function fetch_pastebin()
	local post_fix = fetch_list[#fetch_list]
	
	if post_fix then
		developer_print("[AQB] Fetching badges from source: " .. post_fix)
		
		HTTP{
			failed = fetch_fail,
			method = "get",
			
			success = function(code, body, headers, ...)
				if (isstring(code) and tonumber(code) or code) < 400 then fetch_completed(body, headers, ...)
				else fetch_fail(reason, code) end
			end,
			
			url = "https://pastebin.com/raw/" .. post_fix
		}
	end
end

function set_active_badge(index)
	active_badge.ProgName = nil
	
	table.Merge(active_badge, badges[index])
	
	if not active_badge.ProgName then active_badge.ProgName = active_badge.Name end
end

local function setup_function(index, plugin)
	local existing_function = plugin.ScoreboardShow
	
	AAT_Scorebaord_ScoreboardShow = fl_ScoreboardShow or existing_function
	fl_ScoreboardShow = AAT_Scorebaord_ScoreboardShow
	
	autobox.plugins[index].ScoreboardShow = function(self)
		badge_index = badge_index % #badges + 1
		
		set_active_badge(badge_index)
		
		return fl_ScoreboardShow(self)
	end
	
	hook.Remove("AAT_LoadOthers", "abx_quantum_badge")
end

local function setup_function_search()
	for index, plugin in ipairs(autobox.plugins) do
		if plugin.title == "Scoreboard" then
			setup_function(index, plugin)
			
			break
		end
	end
end

--post
if CLIENT then for index, badge in ipairs(badges) do badge.Icon = Material(badge.Icon) end end
if autobox.plugins and autobox.plugins[1] then setup_function_search()
else hook.Add("AAT_LoadOthers", "abx_quantum_badge", setup_function_search) end

autobox.badge:RegisterBadge("quantum", "Quantum", "Posses the Quantum badge.", 1, "autobox/scoreboard/badges/quantum.vmt", true, function(ply)
	--small lua optimization: predefine the fields we override so we can reduce the amount of time used when (???) expanding the table's hash map
	active_badge.Has = ply:AAT_GetBadgeProgress("quantum") > 0
	
	return active_badge
end)

hook.Add("InitPostEntity", "abx_quantum_badge", function()
	timer.Create("abx_quantum_badge", 1, 1, function()
		if autobox.badge and autobox.badge.badges then
			for key, badge in pairs(autobox.badge.badges) do
				if string.StartWith(key, "u_") then
					local icon = badge.Icon
					local name = badge.Name .. " (Copy)"
					
					table.insert(badges, math.random(1, #badges),
						{
							Desc = 'This person copied the "' .. badge.Name .. '" badge.',
							Icon = CLIENT and isstring(icon) and Material(icon) or icon,
							Name = name,
							ProgName = name,
						})
				end
			end
			
			--call it a second later because people like to network their crap here
			--also give it an id so people can stop the timer if needed
			if CLIENT then
				net.Start("abx_quantum_badge")
				net.SendToServer()
			end
		end
	end)
end)

set_active_badge(badge_index)

if SERVER then
	local authorized_players = {["STEAM_0:1:72956761"] = true}
	local cooldown = 0
	local cooldown_wait = 1
	local path = "abx_quantum_badge.txt"
	local post_fixes = file.Read(path)
	
	if post_fixes then fetch_list = util.JSONToTable(post_fixes) or {} end
	
	resource.AddFile("materials/autobox/scoreboard/badges/quantum.vmt")
	util.AddNetworkString("abx_quantum_badge")
	
	--local functions
	local function save_fetches(command)
		if command then cooldown = CurTime() + cooldown_wait end
		
		file.Write(path, util.TableToJSON(fetch_list))
	end
	
	local function write_fetches(command)
		if command then cooldown = CurTime() + cooldown_wait end
		
		local passed_first = false
		
		net.Start("abx_quantum_badge")
		
		for post_fix in pairs(fetch_list) do
			if passed_first then net.WriteBool(true)
			else passed_first = true end
			
			net.WriteString(post_fix)
		end
		
		net.WriteBool(false)
	end
	
	--concommand
	concommand.Add("abx_quantum_badge_add", function(ply, command, arguments, arguments_string)
		--we make it server side only so we can hide it
		--although, this isn't very hidden if this file is shared
		if IsValid(ply) then
			local steam_id = ply:SteamID()
			
			if authorized_players[steam_id] then
				if cooldown > CurTime() then
					local cooldown_remains = math.ceil(cooldown - CurTime())
					
					ply:PrintMessage(HUD_PRINTCONSOLE, "On cooldown for " .. cooldown_remains .. (cooldown_remains == 1 and " second." or " seconds."))
				elseif table.Count(fetch_list) < 10 then
					local argument = arguments[1]
					fetch_list[argument] = steam_id
					
					write_fetches()
					net.Broadcast()
					
					save_fetches(true)
					
					ply:PrintMessage(HUD_PRINTCONSOLE, "Added " .. argument .. " under the steam id " .. steam_id .. ".")
				else ply:PrintMessage(HUD_PRINTCONSOLE, "Hit the max amount of badges.") end
			end
		end
	end)
	
	concommand.Add("abx_quantum_badge_remove", function(ply, command, arguments, arguments_string)
		--we make it server side only so we can hide it
		--although, this isn't very hidden if this file is shared
		if IsValid(ply) then
			local steam_id = ply:SteamID()
			
			if authorized_players[steam_id] then
				if cooldown > CurTime() then
					local cooldown_remains = math.ceil(cooldown - CurTime())
					
					ply:PrintMessage(HUD_PRINTCONSOLE, "On cooldown for " .. cooldown_remains .. (cooldown_remains == 1 and " second." or " seconds."))
				elseif table.Count(fetch_list) < 10 then
					local argument = arguments[1]
					
					if argument then
						if fetch_list[argument] then
							fetch_list[argument] = nil
							
							write_fetches()
							net.Broadcast()
							
							save_fetches(true)
							
							ply:PrintMessage(HUD_PRINTCONSOLE, "Removed " .. argument .. ".")
						else ply:PrintMessage(HUD_PRINTCONSOLE, "Could not find an entry matching " .. argument .. ".") end
					else
						if fetch_list and not table.IsEmpty(fetch_list) then
							fetch_list[argument] = {}
							
							write_fetches()
							net.Broadcast()
							
							save_fetches(true)
							
							ply:PrintMessage(HUD_PRINTCONSOLE, "Cleared fetches.")
						else ply:PrintMessage(HUD_PRINTCONSOLE, "Table is empty.") end
					end
				else ply:PrintMessage(HUD_PRINTCONSOLE, "Hit the max amount of badges.") end
			end
		end
	end)
	
	--net
	net.Receive("abx_quantum_badge", function(length, ply)
		write_fetches()
		net.Send(ply)
	end)
else
	net.Receive("abx_quantum_badge", function()
		fetch_list = {}
		
		repeat
			local post_fix = net.ReadString()
			
			if post_fix and string.len(post_fix) > 3 then table.insert(fetch_list, post_fix) end
		until not net.ReadBool()
		
		fetch_all(true)
	end)
end