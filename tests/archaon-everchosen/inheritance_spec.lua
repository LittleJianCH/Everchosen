-- Adapter regressions under Lua 5.1. Native plague and Great Game functions
-- are loaded from the current game extraction; the engine is not simulated.
local root = assert(os.getenv("EVERCHOSEN_ROOT"))
local native = assert(os.getenv("EVERCHOSEN_VANILLA_DB"))
local host = "wh_main_chs_chaos"
local prefix = "everchosen_inheritance_"

local function list(values)
    return {num_items = function() return #values end,
            item_at = function(_, index) return values[index + 1] end}
end

local function sandbox(saved, player)
    local s = {saved = saved or {}, named = {}, listeners = {}, objects = {},
        first = {}, pre_first = {}, saving = {}, loading = {}, callbacks = {}, factions = {},
        balances = {}, bundles = {}, characters = {}, rituals = {}, calls = {},
        contexts = {}, logs = {}, new_game = not saved, player = player or host}
    s.effects = {[host] = s.bundles}
    s.nodes = {}
    s.province = "wh3_main_combi_province_albion"
    s.ui = {}
    local function record(kind, value)
        s.calls[#s.calls + 1] = {kind, value}
    end
    function s:count(kind)
        local count = 0
        for _, call in ipairs(self.calls) do
            if call[1] == kind then count = count + 1 end
        end
        return count
    end
    function s:create_hud()
        for _, id in ipairs({"button_nurgle_plagues",
            "button_changing_of_the_ways", "button_great_game_rituals",
            "nurgle_infections_holder", "dae_ascendant_race_holder"}) do
            local component = {visible = true, state = "inactive"}
            function component:SetVisible(visible)
                self.visible = visible
                record("visibility", id)
            end
            self.ui[id] = component
        end
    end
    s:create_hud()
    function s:faction(key, subculture)
        local f = {key = key, sc = subculture, absorbed_by = nil}
        function f:is_null_interface() return false end
        function f:name() return self.key end
        function f:subculture() return self.sc end
        function f:culture() return "wh_main_chs_chaos" end
        function f:is_human() return self.key == s.player end
        function f:is_dead() return self.dead or false end
        function f:is_vassal_of(overlord)
            assert(type(overlord) == "table", "Native API takes a faction")
            return self.master == overlord:name()
        end
        function f:faction_leader()
            local province = {is_null_interface = function() return false end,
                              key = function() return s.province end}
            local region = {is_null_interface = function() return false end,
                            province = function() return province end}
            return {is_null_interface = function() return false end,
                    has_region = function() return not s.no_region end,
                    region = function() return region end}
        end
        function f:character_list() return list(s.characters[self.key] or {}) end
        function f:was_confederated_by_faction(receiver)
            assert(type(receiver) == "table", "Native API takes a faction")
            return self.absorbed_by == receiver
        end
        function f:has_effect_bundle(key)
            return (s.effects[self.key] or {})[key] == true
        end
        function f:command_queue_index() return self.key == host and 1 or 2 end
        function f:has_rituals() return true end
        function f:has_access_to_ritual_category() return true end
        function f:is_contained_in_faction_set()
            return self.key == host or self.key == "wh3_dlc20_chs_festus"
        end
        function f:plagues()
            return {plague_component_list = function() return list({}) end}
        end
        function f:pooled_resource_manager()
            return {resource = function(_, key)
                return {is_null_interface = function() return s.missing == key end,
                        value = function() return s.balances[key] or 0 end}
            end}
        end
        s.factions[key] = f
        return f
    end
    function s:own(subtype)
        local c = {is_null_interface = function() return false end,
            character_subtype_key = function() return subtype end,
            faction = function() return s.factions[host] end}
        -- No deployment/health methods: wounded ownership must not need them.
        self.characters[host][#self.characters[host] + 1] = c
    end
    s:faction(host, "wh_main_sc_chs_chaos")
    s:faction("wh3_dlc20_chs_festus", "wh_main_sc_chs_chaos")
    s:faction("wh3_dlc20_chs_vilitch", "wh_main_sc_chs_chaos")
    s:faction("wh3_main_chs_shadow_legion", "wh_main_sc_chs_chaos")
    s:faction("wh3_main_sla_seducers_of_slaanesh", "wh3_main_sc_sla_slaanesh")
    s:faction("wh3_main_kho_exiles_of_khorne", "wh3_main_sc_kho_khorne")
    s.characters[host] = {}
    local cm = {
        get_campaign_name = function() return s.campaign or "main_warhammer" end,
        is_multiplayer = function() return s.multiplayer or false end,
        is_new_game = function() return s.new_game end,
        get_faction = function(_, key) return s.factions[key] end,
        get_faction_list = function() return list({s.factions[host]}) end,
        get_local_faction = function() return s.factions[s.player] end,
        get_saved_value = function(_, key) return s.saved[key] end,
        set_saved_value = function(_, key, value)
            assert(value ~= nil, "CA saved values cannot be nil")
            s.saved[key] = value
        end,
        save_named_value = function(_, key, value) s.named[key] = value end,
        load_named_value = function(_, key, default) return s.named[key] or default end,
        add_first_tick_callback = function(_, fn) s.first[#s.first + 1] = fn end,
        add_pre_first_tick_callback = function(_, fn) s.pre_first[#s.pre_first + 1] = fn end,
        add_saving_game_callback = function(_, fn) s.saving[#s.saving + 1] = fn end,
        add_loading_game_callback = function(_, fn) s.loading[#s.loading + 1] = fn end,
        callback = function(_, fn) s.callbacks[#s.callbacks + 1] = fn end,
        model = function()
            local network = {
                is_null_interface = function() return false end,
                lookup_open_node = function(_, key)
                    return {is_null_interface = function() return not s.nodes[key] end,
                            record_key = function() return key end,
                            template_key = function() return s.nodes[key] end}
                end,
            }
            local system = {lookup_network = function(_, key)
                assert.equals("wh3_main_teleportation_network_belakor", key)
                return network
            end}
            return {world = function() return {
                teleportation_network_system = function() return system end,
                faction_list = function()
                    local factions = {}
                    for _, faction in pairs(s.factions) do
                        factions[#factions + 1] = faction
                    end
                    return list(factions)
                end,
            } end}
        end,
        teleportation_network_open_node = function(_, key)
            record("portal", key)
            if not s.fail_portal then
                s.nodes[key] = "wh3_main_teleportation_node_template_belakor"
            end
        end,
        add_or_remove_faction_features = function(_, faction, features, enable)
            assert(faction == s.factions[host] and enable)
            record("features", features)
        end,
        apply_effect_bundle = function(_, key, faction)
            s.effects[faction] = s.effects[faction] or {}
            s.effects[faction][key] = true
            record("apply_bundle", faction .. ":" .. key)
        end,
        remove_effect_bundle = function(_, key, faction)
            if not s.fail_removal then s.effects[faction][key] = nil end
            record("remove_bundle", faction .. ":" .. key)
        end,
        unlock_ritual = function(_, faction, key)
            s.rituals[key] = true; record("unlock", key)
        end,
        lock_ritual = function(_, faction, key) s.rituals[key] = false end,
        faction_add_pooled_resource = function(_, faction, key, factor, amount)
            assert(faction == host and factor == "other")
            s.balances[key] = (s.balances[key] or 0) + amount
            record("resource", key)
        end,
        set_plague_component_state = function(_, faction, component, state)
            record("component", component .. state)
        end,
        override_ui = function() end,
        random_number = function(_, maximum) return maximum end,
        pending_battle_cache_faction_won_battle = function(_, faction)
            return faction == host and s.won
        end,
        pending_battle_cache_faction_won_battle_against_culture = function(_, faction, culture)
            return faction == host and s.enemy == culture
        end,
    }
    local env = setmetatable({cm = cm, core = {
        get_ui_root = function() return s.ui end,
        add_listener = function(_, key, event, condition, callback)
            s.listeners[key] = {event, condition, callback}
        end,
        add_static_object = function(_, key, value) s.objects[key] = value end,
        get_static_object = function(_, key) return s.objects[key] end,
    }, common = {set_context_value = function(key, value) s.contexts[key] = value end},
        find_uicomponent = function(root, id) return root[id] end,
        out = function(value) s.logs[#s.logs + 1] = value end,
        archaon_subjugation_config = {faction_key_to_leader_subtype_list = {
            wh3_dlc20_chs_festus = {subtype_key = "wh3_dlc20_nur_festus"},
            wh3_dlc20_chs_vilitch = {subtype_key = "wh3_dlc20_tze_vilitch"},
            wh3_main_chs_shadow_legion = {subtype_key = "wh3_main_dae_belakor"},
        }}}, {__index = _G})
    -- CA loads campaign/mod chunks into core:get_env(), not the Lua registry.
    -- lib_campaign_manager exposes that environment as _G.campaign_env.
    env._G = setmetatable({campaign_env = env}, {__index = _G})
    env.core.get_env = function() return env end
    -- Fennel's include bundles loaders in package.preload. Each simulated
    -- campaign session has a fresh module cache, just like a new Lua state.
    env.package = {preload = {}, loaded = {}}
    env.require = function(name)
        if not env.package.loaded[name] then
            env.package.loaded[name] = assert(env.package.preload[name])()
        end
        return env.package.loaded[name]
    end
    function s:load(path) setfenv(assert(loadfile(path)), env)() end
    function s:start()
        self:load(native .. "/script/campaign/wh3_dlc29_archaon_subjugation.lua")
        self:load(native .. "/script/campaign/wh3_campaign_nurgle_plagues.lua")
        self:load(native .. "/script/campaign/wh3_campaign_great_game.lua")
        for _, fn in ipairs(self.loading) do fn({}) end
        self:load(root .. "/build/archaon-everchosen/script/campaign/mod/everchosen_inheritance_data.lua")
        self:load(root .. "/build/archaon-everchosen/script/campaign/mod/everchosen_archaon.lua")
        for _, fn in ipairs(self.pre_first) do fn() end
        env.nurgle_plagues:initialise()
        for _, fn in ipairs(self.first) do fn() end
        if self.late_hud then self:create_hud() end
        self:flush()
    end
    function s:emit(event, context)
        -- Limit delivery to this mod; native functions are called explicitly.
        for key, listener in pairs(self.listeners) do
            if key:sub(1, #prefix) == prefix and listener[1] == event
                and (listener[2] == true or listener[2](context)) then
                listener[3](context)
            end
        end
        self:flush()
    end
    function s:flush()
        local queue = self.callbacks
        self.callbacks = {}
        for _, fn in ipairs(queue) do fn() end
    end
    function s:turn() self:emit("FactionTurnStart", {faction = function() return s.factions[host] end}) end
    function s:reload()
        for _, fn in ipairs(self.saving) do fn({}) end
        local next = sandbox(self.saved, self.player)
        next.named, next.balances, next.bundles = self.named, self.balances, self.bundles
        next.effects, next.nodes = self.effects, self.nodes
        for key, faction in pairs(self.factions) do
            local copy = next.factions[key] or next:faction(key, faction.sc)
            copy.master, copy.dead = faction.master, faction.dead
        end
        next.rituals = self.rituals
        next:start()
        return next
    end
    s.env = env
    return s
end

describe("Archaon inheritance", function()
    it("hides unearned HUD controls after layout and opens each earned mechanic", function()
        local s = sandbox()
        s.ui, s.late_hud = {}, true
        s:start()
        for _, component in pairs(s.ui) do assert.is_false(component.visible) end
        s:own("wh3_dlc20_nur_festus"); s:turn()
        assert.is_true(s.ui.button_nurgle_plagues.visible)
        assert.is_true(s.ui.nurgle_infections_holder.visible)
        assert.is_false(s.ui.button_changing_of_the_ways.visible)
        assert.is_false(s.ui.button_great_game_rituals.visible)
        assert.is_false(s.ui.dae_ascendant_race_holder.visible)
        s:create_hud() -- A panel/layout refresh reapplied the native defaults.
        s:emit("PanelClosedCampaign", {})
        assert.is_true(s.ui.button_nurgle_plagues.visible)
        assert.is_false(s.ui.button_changing_of_the_ways.visible)
        assert.is_false(s.ui.button_great_game_rituals.visible)
        s:own("wh3_dlc20_tze_vilitch"); s:turn()
        assert.is_true(s.ui.button_changing_of_the_ways.visible)
        assert.is_false(s.ui.button_great_game_rituals.visible)
        s:own("wh3_main_dae_belakor"); s:turn()
        assert.is_true(s.ui.button_great_game_rituals.visible)
        assert.is_true(s.ui.dae_ascendant_race_holder.visible)
        local loaded = s:reload()
        for _, component in pairs(loaded.ui) do
            assert.is_true(component.visible)
            assert.equals("inactive", component.state) -- Keep native cooldown/turn locks.
        end
    end)

    it("requires verified ownership, counts wounded lords and unlocks once", function()
        local s = sandbox(); s:start()
        assert.is_false(s.env.faction_has_great_game_rituals(s.factions[host]))
        s:emit("ScriptEventArchaonSubjugatesChaosFaction", {string = "wh3_dlc20_chs_vilitch"})
        s:own("wh3_main_tze_lord_of_change")
        s:turn()
        assert.is_nil(s.saved[prefix .. "unlocked_tze"])
        s:own("wh3_dlc20_tze_vilitch")
        s:emit("ScriptEventArchaonSubjugatesChaosFaction", {})
        assert.is_true(s.saved[prefix .. "unlocked_tze"])
        local calls = s:count("unlock")
        local ritual = s.objects.everchosen_inheritance_data.tze[1]
        s.rituals[ritual] = false -- An engine cooldown/temporary lock.
        s:turn(); s:emit("ScriptEventArchaonSubjugatesChaosFaction", {})
        assert.equals(calls, s:count("unlock"))
        local loaded = s:reload()
        loaded:turn()
        assert.equals(0, loaded:count("unlock"))
        assert.is_false(loaded.rituals[ritual])
    end)

    it("waits for a real confederation, rejects other recipients", function()
        local s = sandbox(); s:start()
        local source = s.factions.wh3_main_sla_seducers_of_slaanesh
        local event = {faction = function() return source end,
                       confederation = function() return s.factions[host] end}
        s:emit("FactionJoinsConfederation", event)
        assert.is_nil(s.saved[prefix .. "unlocked_sla"])
        source.absorbed_by = s.factions.wh3_dlc20_chs_festus
        s:turn()
        assert.is_nil(s.saved[prefix .. "unlocked_sla"])
        source.absorbed_by = s.factions[host]
        s:turn(); s:emit("FactionJoinsConfederation", event)
        assert.is_true(s.saved[prefix .. "unlocked_sla"])
        assert.equals(1, s:count("features"))
        source = s.factions.wh3_main_kho_exiles_of_khorne
        source.absorbed_by = s.factions[host]
        s:emit("FactionJoinsConfederation", event)
        s:emit("FactionJoinsConfederation", event)
        assert.is_true(s.saved[prefix .. "unlocked_kho"])
        assert.equals(2, s:count("features"))
        local last_features
        for _, call in ipairs(s.calls) do
            if call[1] == "features" then last_features = call[2] end
        end
        assert.same({"streaks"}, last_features)
    end)

    it("keeps native plague recipes, resource balances and shuffle variants", function()
        local s = sandbox(); s:start()
        s.balances.wh3_main_nur_infections = 47
        s:own("wh3_dlc20_nur_festus"); s:turn()
        local manager = s.env.nurgle_plagues
        local info = manager.plague_faction_info[host]
        assert.equals(18, #s.contexts["random_plague_component_list_" .. host])
        assert.equals(3, s.contexts["random_plague_creation_count_" .. host])
        assert.equals(1, s.contexts[prefix .. "ui_nur"])
        assert.equals(47, s.balances.wh3_main_nur_infections)
        assert.is_nil(s.bundles[prefix .. "infections_locked"])
        assert.equals(2, s:count("component"))
        info.plague_creation_counter = 1
        info.current_symptoms_list[1] = "saved_recipe"
        local loaded = s:reload()
        info = loaded.env.nurgle_plagues.plague_faction_info[host]
        assert.equals(1, info.plague_creation_counter)
        assert.equals("saved_recipe", info.current_symptoms_list[1])
        assert.equals("saved_recipe",
            loaded.contexts["random_plague_component_list_" .. host][1])
        assert.equals(1, loaded.contexts["random_plague_creation_count_" .. host])
        assert.equals(0, loaded:count("component"))
        assert.equals(47, loaded.balances.wh3_main_nur_infections)
        manager = loaded.env.nurgle_plagues
        manager:randomise_symptom_location(loaded.factions[host])
        local found = false
        for _, key in ipairs(info.current_symptoms_list) do
            if key == "wh3_dlc25_nur_force_5_festus" then found = true end
        end
        assert.is_true(found)
    end)

    it("does not commit a failed initialization and retries from ownership", function()
        local s = sandbox(); s:start()
        s.missing = "wh3_main_nur_infections"
        s:own("wh3_dlc20_nur_festus"); s:turn()
        assert.is_nil(s.saved[prefix .. "unlocked_nur"])
        assert.is_true(s.bundles[prefix .. "infections_locked"])
        s.missing = nil; s:turn()
        assert.is_true(s.saved[prefix .. "unlocked_nur"])
    end)

    it("persists battle deduplication and updates only on new ascendancy", function()
        local s = sandbox(); s:start()
        s:own("wh3_main_dae_belakor"); s:turn()
        local resource = "wh3_main_ritual_belakor_gg_1_uses"
        assert.is_nil(s.balances[resource]) -- No free charges on acquisition.
        s.won, s.enemy = true, "wh3_main_kho_khorne"
        s:emit("PendingBattle", {}); s:emit("BattleCompleted", {})
        s:emit("BattleCompleted", {})
        assert.equals(1, s.balances[resource])
        s = s:reload(); s.won, s.enemy = true, "wh3_main_kho_khorne"
        s:emit("BattleCompleted", {})
        assert.equals(1, s.balances[resource])
        s:emit("PendingBattle", {}); s:emit("BattleCompleted", {})
        assert.equals(2, s.balances[resource])
        s.saved.great_game_ascendant_god = "wh3_main_kho_khorne"
        s:emit("ScriptEventNewGodAscendant", {})
        assert.is_true(s.rituals.wh3_main_ritual_belakor_gg_1_upgraded)
        local count = s:count("unlock")
        s:emit("ScriptEventNewGodAscendant", {}); s:turn()
        assert.equals(count, s:count("unlock"))
        -- The wrapper delegates other factions to CA's actual function.
        s.env.unlock_gg_rituals(nil, s.factions.wh3_main_chs_shadow_legion, false)
        assert.equals(count + 4, s:count("unlock"))
    end)

    it("does not initialize inheritance for another player or multiplayer", function()
        for _, settings in ipairs({{player = "wh3_dlc20_chs_festus"}, {multiplayer = true}}) do
            local s = sandbox(nil, settings.player)
            s.multiplayer = settings.multiplayer
            s:start()
            assert.is_nil(s.objects.everchosen_inheritance)
            assert.equals(0, s:count("features"))
            assert.is_nil(s.bundles[prefix .. "infections_locked"])
            assert.equals(0, s:count("portal"))
            assert.equals(0, s:count("visibility"))
        end
    end)

    it("opens and confirms only the starting province, never reopens on load", function()
        local s = sandbox(); s:start()
        assert.equals(s.province, s.saved[prefix .. "starting_portal"])
        assert.equals(1, s:count("portal"))
        assert.is_nil(s.saved[prefix .. "unlocked_gg"])
        s.nodes[s.province] = nil -- The node was closed during normal play.
        s = s:reload(); s:turn()
        assert.equals(0, s:count("portal"))
        assert.is_nil(s.nodes[s.province])

        s = sandbox(); s.fail_portal = true; s:start()
        assert.equals(1, s:count("portal"))
        assert.is_nil(s.saved[prefix .. "starting_portal"])
        assert.matches("did not open", s.logs[#s.logs])
        s = s:reload()
        assert.equals(0, s:count("portal"))

        s = sandbox(); s.province = "province_without_a_native_node"; s:start()
        assert.equals(0, s:count("portal"))
        assert.is_nil(s.saved[prefix .. "starting_portal"])
    end)

    it("follows direct vassals, preserves unrelated effects and retries removal", function()
        local s = sandbox()
        local vassal = s:faction("test_vassal", "wh_main_sc_emp_empire")
        local indirect = s:faction("test_indirect", "wh_main_sc_emp_empire")
        local other = s:faction("test_other", "wh_main_sc_chs_chaos")
        vassal.master, indirect.master = host, vassal.key
        s.effects[vassal.key] = {unrelated_native_bundle = true}
        s:start()
        local bundles = s.objects.everchosen_inheritance_data.blessings
        assert.is_false(vassal:has_effect_bundle(bundles.nur))
        s:own("wh3_dlc20_nur_festus"); s:turn()
        assert.is_true(vassal:has_effect_bundle(bundles.nur))
        assert.is_false(vassal:has_effect_bundle(bundles.tze))
        assert.is_false(indirect:has_effect_bundle(bundles.nur))
        assert.is_false(other:has_effect_bundle(bundles.nur))
        assert.is_false(s.factions[host]:has_effect_bundle(bundles.nur))
        s:own("wh3_dlc20_tze_vilitch"); s:turn()
        assert.is_true(vassal:has_effect_bundle(bundles.tze))
        local applied = s:count("apply_bundle")
        s:turn()
        assert.equals(applied, s:count("apply_bundle"))
        s = s:reload()
        assert.equals(0, s:count("apply_bundle"))
        vassal, other = s.factions.test_vassal, s.factions.test_other
        local event = {is_vassalage = function() return true end,
                       was_vassalage = function() return true end,
                       proposer = function() return s.factions[host] end,
                       recipient = function() return other end}
        other.master = host
        s:emit("PositiveDiplomaticEvent", event)
        assert.is_true(other:has_effect_bundle(bundles.nur))
        assert.is_true(other:has_effect_bundle(bundles.tze))
        vassal.master = "wh3_main_chs_shadow_legion"
        s.fail_removal = true
        event.recipient = function() return vassal end
        s:emit("NegativeDiplomaticEvent", event)
        assert.is_true(s.saved[prefix .. "blessing_recipients"][vassal.key])
        s.fail_removal = false
        s:emit("FactionTurnStart", {faction = function() return vassal end})
        assert.is_false(vassal:has_effect_bundle(bundles.nur))
        assert.is_false(vassal:has_effect_bundle(bundles.tze))
        assert.is_true(vassal:has_effect_bundle("unrelated_native_bundle"))
        assert.is_nil(s.saved[prefix .. "blessing_recipients"][vassal.key])
        other.dead = true; s:turn()
        assert.is_false(other:has_effect_bundle(bundles.nur))
    end)
end)
