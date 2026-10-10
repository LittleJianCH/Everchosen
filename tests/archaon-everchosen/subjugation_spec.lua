-- Command/confirmation boundaries, not an emulation of confederation or armies.
local root = assert(os.getenv("EVERCHOSEN_ROOT"))
local native = assert(os.getenv("EVERCHOSEN_VANILLA_DB"))
local host = "wh_main_chs_chaos"
local source_key = "wh_dlc03_bst_beastmen"
local client_key = "wh_dlc03_bst_beastmen_chaos"
local prefix = "everchosen_subjugation_"
local function list(values)
    return {num_items = function() return #values end,
        item_at = function(_, i) return values[i + 1] end,
        is_empty = function() return #values == 0 end}
end

local function campaign(saved)
    local s = {saved = saved or {}, factions = {}, characters = {}, queue = {},
        calls = {}, objects = {}, listeners = {}, logs = {}, turn = 1}
    local function record(name, value)
        s.calls[name] = s.calls[name] or {}
        table.insert(s.calls[name], value or true)
    end
    function s:count(name) return #(self.calls[name] or {}) end
    function s:faction(key)
        local f = {key = key, chars = {}, regions = {}, dead = false}
        function f:is_null_interface() return false end
        function f:name() return self.key end
        function f:is_human() return self.key == (s.player or host) end
        function f:culture() return "wh_dlc03_bst_beastmen" end
        function f:command_queue_index() return self.key end
        function f:is_dead() return self.dead end
        function f:has_faction_leader() return self.leader ~= nil end
        function f:faction_leader() return self.leader end
        function f:master() return self.overlord end
        function f:is_vassal_of(other) return self.overlord == other end
        function f:character_list() return list(self.chars) end
        function f:military_force_list() return list(self.forces or {}) end
        function f:was_confederated() return self.absorbed_by ~= nil end
        function f:num_regions() return #self.regions end
        function f:region_list() return list(self.regions) end
        function f:was_confederated_by_faction(other)
            assert.is_table(other) -- API takes an interface, not its key.
            return self.absorbed_by == other
        end
        self.factions[key] = f
        return f
    end
    function s:character(id, faction, subtype, wounded)
        local c = {id = id, owner = faction, subtype = subtype, alive = not wounded}
        function c:is_null_interface() return false end
        function c:cqi() return self.id end
        c.command_queue_index = c.cqi
        function c:faction() return self.owner end
        function c:character_type(kind) return kind == "general" end
        function c:character_subtype_key() return self.subtype end
        function c:character_subtype(kind) return kind == self.subtype end
        function c:is_alive() return self.alive end
        function c:has_region() return true end
        function c:region() return {name = function() return "native_region" end} end
        function c:family_member()
            return {is_null_interface = function() return false end,
                command_queue_index = function() return id end,
                character = function() return s.characters[id] end}
        end
        self.characters[id] = c
        table.insert(faction.chars, c)
        return c
    end
    s.host, s.source, s.client = s:faction(host), s:faction(source_key), s:faction(client_key)
    s.host.leader = s:character(1, s.host, "wh_main_chs_archaon")
    s.lord = s:character(2, s.source, "wh_dlc03_bst_khazrak")
    s.source.leader = s.lord
    s.client.dead = true
    local cm = {
        get_campaign_name = function() return "main_warhammer" end,
        is_multiplayer = function() return false end,
        get_human_factions = function() return {s.player or host} end,
        get_faction = function(_, key) return s.factions[key] end,
        get_saved_value = function(_, key) return s.saved[key] end,
        set_saved_value = function(_, key, value) s.saved[key] = value end,
        add_saving_game_callback = function() end,
        add_loading_game_callback = function() end,
        add_first_tick_callback = function() end,
        add_pre_first_tick_callback = function() end,
        callback = function(_, fn) table.insert(s.queue, fn) end,
        turn_number = function() return s.turn end,
        get_family_member_by_cqi = function(_, id)
            return s.characters[id] and s.characters[id]:family_member()
        end,
        get_character_by_cqi = function(_, id) return s.characters[id] end,
        char_lookup_str = function(_, id) return "character_cqi:" .. id end,
        kill_character = function(_, lookup, wound)
            assert.is_true(wound)
            record("wound", lookup)
            s.characters[tonumber(lookup:match("%d+"))].alive = false
        end,
        reassign_character = function(_, id, receiver)
            assert.equals(host, receiver)
            record("reassign", id) -- Ownership is deliberately not confirmed here.
        end,
        stop_character_convalescing = function(_, id) record("recover", id) end,
        randomise_character_name = function() end,
        change_localised_faction_name = function(_, key, name)
            assert.equals(client_key, key)
            record("rename", name)
        end,
        find_valid_spawn_location_for_character_from_settlement = function()
            return s.no_spawn and -1 or 1, 2
        end,
        awaken_faction_from_death = function(_, f) record("awaken", f:name()) end,
        awaken_faction_from_death_with_region = function(_, f)
            record("resurrect", f:name()); f.dead = false
        end,
        create_force_with_general = function(_, key, units, region, x, y,
                kind, subtype, a, b, c, d, leader, callback)
            assert.equals(client_key, key)
            assert.is_nil(units) -- No reconstruction of the legendary lord's army.
            assert.is_true(leader)
            record("create", key); s.created = callback
        end,
        force_make_vassal = function(_, owner, key)
            assert.equals(host, owner); record("vassal", key)
        end,
        create_payload = function()
            return {form_confederation = function(_, receiver, source, dead, keep)
                assert.equals(s.client, receiver); assert.equals(s.source, source)
                assert.is_false(dead); assert.is_true(keep)
            end}
        end,
        apply_payload = function() record("merge") end,
        kill_faction = function(_, key) record("kill_faction", key) end,
        trigger_dilemma_with_targets = function(_, winner, key, a, b, c, d, e, f, fn)
            record("dilemma", key); fn()
        end,
        model = function() return {manual_saves_disabled = function() return false end} end,
    }
    local env = setmetatable({cm = cm, dpairs = pairs,
        out = function(message) table.insert(s.logs, message) end,
        core = {get_static_object = function(_, key) return s.objects[key] end,
            add_static_object = function(_, key, value) s.objects[key] = value end,
            trigger_event = function(_, event, key) record("completed", key) end,
            add_listener = function(_, key, event, condition, fn)
                s.listeners[key] = {condition, fn}
            end}}, {__index = _G})
    -- Match CA's separate campaign environment and global registry.
    env._G = setmetatable({campaign_env = env}, {__index = _G})
    env.core.get_env = function() return env end
    env.package = {preload = {}, loaded = {}}
    env.require = function(name)
        if not env.package.loaded[name] then
            env.package.loaded[name] = assert(env.package.preload[name])()
        end
        return env.package.loaded[name]
    end
    local function load(path) setfenv(assert(loadfile(path)), env)() end
    function s:flush()
        local queue = self.queue; self.queue = {}
        for _, fn in ipairs(queue) do fn() end
    end
    function s:start()
        load(native .. "/script/campaign/wh3_dlc29_archaon_subjugation.lua")
        self.original_accept = env.archaon_subjugation.subjugate_chaos_faction
        load(root .. "/build/archaon-everchosen/script/campaign/mod/everchosen_inheritance_data.lua")
        load(root .. "/build/archaon-everchosen/script/campaign/mod/everchosen_archaon.lua")
        env.require("everchosen_subjugation.campaign").start()
        self.manager = env.archaon_subjugation
        self:flush()
    end
    function s:accept() self.manager:subjugate_chaos_faction(self.source); self:flush() end
    function s:confirm_client()
        self.client.dead = false
        self.client.leader = self:character(3, self.client, "wh_dlc03_bst_beastlord")
        self.client.overlord = self.host
        if self.created then self.created(3) end
    end
    return s
end

describe("Extended subjugation", function()
    it("leaves a borrowed faction alone when another mod has activated it", function()
        local s = campaign()
        s.client.dead = false
        s.client.forces = {{}}
        s:start(); s:accept()
        s.manager:trigger_archaon_confederation_dilemma(s.host, s.source)
        assert.equals(0, s:count("dilemma"))
        assert.equals(0, s:count("rename"))
        assert.equals(0, s:count("create"))
        assert.equals(0, s:count("vassal"))
        assert.equals(0, s:count("merge"))
    end)

    it("waits for a valid client and merger, then transfers only accepted lords", function()
        local s = campaign(); s:start()
        local wounded = s:character(4, s.source, "wh_dlc03_bst_malagor", true)
        local ordinary = s:character(5, s.source, "wh_dlc03_bst_beastlord")
        s:accept(); s:accept()
        assert.equals(1, s:count("create"))
        assert.equals(0, s:count("merge"))
        assert.equals(0, s:count("reassign"))
        s:confirm_client(); s:accept()
        assert.equals(1, s:count("merge"))
        assert.equals(0, s:count("reassign"))
        s.source.absorbed_by, s.source.dead = s.client, true
        s.lord.owner, wounded.owner, ordinary.owner = s.client, s.client, s.client
        s:accept()
        assert.same({"character_cqi:2"}, s.calls.wound)
        assert.equals(2, s:count("reassign"))
        assert.is_nil(s.saved[prefix .. "completed"])
        assert.equals(s.client, ordinary.owner)
        s.lord.owner, wounded.owner = s.host, s.host
        s.host.chars = {s.host.leader, s.lord, wounded}
        -- An accepted operation resumes from saved IDs even when eligibility ends.
        s.listeners[prefix .. "turn"][2]()
        s:flush()
        assert.is_true(s.saved[prefix .. "completed"][source_key])
        assert.equals(1, s:count("completed"))
        s:accept()
        assert.equals(1, s:count("completed"))
        assert.equals(0, s:count("kill_faction"))
    end)

    it("does not merge after an invalid spawn and resumes a saved merger", function()
        local s = campaign(); s.no_spawn = true; s:start(); s:accept()
        assert.equals(0, s:count("create"))
        assert.equals(0, s:count("merge"))
        assert.equals(0, s:count("rename"))
        assert.is_nil(s.saved[prefix .. "claimed_clients"])
        s.no_spawn = false; s:accept(); s:confirm_client(); s:accept()
        local loaded = campaign(s.saved)
        loaded:confirm_client()
        loaded.source.absorbed_by, loaded.source.dead = loaded.client, true
        loaded.lord.owner = loaded.client
        loaded:start()
        assert.equals(0, loaded:count("create"))
        assert.equals(0, loaded:count("merge"))
        assert.is_true(loaded:count("reassign") > 0)
    end)

    it("recovers a destroyed faction's lord without creating a client", function()
        local s = campaign(); s.source.dead = true; s.lord.alive = false
        s:start(); s:accept()
        assert.equals(1, s:count("resurrect")) -- Actual CA resurrection helper.
        assert.equals(0, s:count("create"))
        assert.equals(0, s:count("merge"))
        s.lord.owner = s.host; s.host.chars = {s.host.leader, s.lord}
        s.listeners[prefix .. "turn"][2](); s:flush()
        assert.equals(1, s:count("kill_faction"))
        assert.equals(1, s:count("completed"))
    end)

    it("keeps the native reject choice and excludes human vassals and other players", function()
        local s = campaign(); s:start()
        s.manager:trigger_archaon_confederation_dilemma(s.host, s.source)
        assert.equals(1, s:count("dilemma"))
        local listener = s.listeners.ArchaonConfederationDilemmaChoiceMadeEvent
        local choice = {dilemma = function() return prefix .. "accept" end,
                        choice = function() return 1 end}
        assert.is_true(listener[1](choice)); listener[2](choice); s:flush()
        assert.equals(0, s:count("create"))
        assert.is_nil(s.saved[prefix .. "pending"])
        s.source.overlord = s.host; s:accept()
        assert.equals(0, s:count("create"))
        s = campaign(); s.player = source_key; s:start()
        assert.equals(s.original_accept, s.manager.subjugate_chaos_faction)
    end)
end)
