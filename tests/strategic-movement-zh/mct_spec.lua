-- MCT interfaces follow the subscribed groovy_mct option and page objects.
-- This exercises text adaptation, not MCT layout or campaign movement.
local root = assert(os.getenv("EVERCHOSEN_ROOT"))
local mod_key = "pwd5032_dynamic_movement"
local prefix = "mct_" .. mod_key .. "_"

local function scenario()
    local s = {listeners = {}, settings = {}, options = {}, callback_calls = 0}
    local translations = {
        [prefix .. "lock_custom"] = "请先启用自定义行军方案。",
        [prefix .. "page_movement"] = "行军、地区与气候",
        [prefix .. "page_naval"] = "海上、英雄与调试",
    }
    local function option(key, values)
        s.settings[key] = values[2].key
        local o = {_values = values, _is_locked = true,
            _lock_reason = "Enable Custom Profile to edit"}
        function o:get_values() return self._values end
        function o:get_key() return key end
        function o:get_selected_setting() return s.settings[key] end
        function o:is_locked() return self._is_locked end
        function o:get_lock_reason() return self._lock_reason end
        s.options[key] = o
        return o
    end
    option("movement_preset", {
        {key = "light", text = "Light", tt = "Light tooltip"},
        {key = "standard", text = "Standard", tt = "Standard tooltip"},
    })
    option("territory_mode", {
        {key = "moderate", text = "Moderate", tt = "Moderate tooltip"},
        {key = "off", text = "Off", tt = "Off tooltip"},
    })
    option("climate_mode", {
        {key = "balanced_light", text = "Balanced Light", tt = "Light climate"},
        {key = "off", text = "Off", tt = "Off tooltip"},
    })
    local function page(key)
        local title = {text = key, writes = 0}
        function title:SetStateText(text)
            self.text = text
            self.writes = self.writes + 1
        end
        local p = {row = {dy_title = title}}
        function p:get_key() return key end
        function p:get_row_uic() return self.row end
        return p
    end
    s.pages = {page("Settings"), page("Naval, Hero & Debug")}
    s.foreign_pages = {page("Settings"), page("Naval, Hero & Debug")}
    local mod = {}
    function mod:get_option_by_key(key) return s.options[key] end
    function mod:get_options() return s.options end
    function mod:get_settings_pages() return s.pages end
    s.mods = {[mod_key] = mod, unrelated = {
        get_settings_pages = function() return s.foreign_pages end,
    }}
    local mct = {}
    function mct:get_mod_by_key(key) return s.mods[key] end
    s.context = {mct = function() return mct end}

    local env = setmetatable({package = {preload = {}, loaded = {}}, core = {},
        common = {get_localised_string = function(key)
            return translations[key] or ""
        end},
        find_uicomponent = function(row, key) return row[key] end,
    }, {__index = _G})
    function env.core:add_listener(name, event, condition, callback, persistent)
        s.listeners[name] = {event = event, condition = condition,
            callback = callback, persistent = persistent}
    end
    function env.require(name)
        if not env.package.loaded[name] then
            env.package.loaded[name] = assert(env.package.preload[name])()
        end
        return env.package.loaded[name]
    end
    function s:fire(event, context)
        context = context or self.context
        for _, listener in pairs(self.listeners) do
            if listener.event == event and (listener.condition == true or
                    listener.condition(context)) then
                listener.callback(context)
            end
        end
    end
    -- add_option_set_callback in MCT registers an ordinary core listener.
    env.core:add_listener("MctOptionmovement_presetSet",
        "MctOptionSelectedSettingSet", function(context)
            return context:option():get_key() == "movement_preset"
        end, function() s.callback_calls = s.callback_calls + 1 end, true)
    s.original_callback = s.listeners.MctOptionmovement_presetSet
    setfenv(assert(loadfile(root ..
        "/build/strategic-movement-zh/script/mct/settings/" ..
        "everchosen_strategic_movement_zh.lua")), env)()
    return s
end

describe("strategic movement MCT translation", function()
    it("changes display text without changing settings, locks or callbacks", function()
        local s = scenario()
        local preset = s.options.movement_preset
        local values = preset:get_values()
        s:fire("MctInitialized")
        local adapted_getter = preset.get_lock_reason
        s:fire("MctInitialized")

        assert.equals(values, preset:get_values())
        assert.equals(2, #values)
        assert.same({"light", "standard"}, {values[1].key, values[2].key})
        assert.equals(prefix .. "movement_preset_light_text", values[1].text)
        assert.equals(prefix .. "movement_preset_light_tooltip", values[1].tt)
        assert.equals(prefix .. "territory_mode_off_text",
            s.options.territory_mode:get_values()[2].text)
        assert.equals(prefix .. "climate_mode_off_tooltip",
            s.options.climate_mode:get_values()[2].tt)
        assert.equals("standard", preset:get_selected_setting())
        assert.equals("off", s.options.territory_mode:get_selected_setting())
        assert.equals("off", s.options.climate_mode:get_selected_setting())
        assert.equals(adapted_getter, preset.get_lock_reason)
        assert.equals("请先启用自定义行军方案。", preset:get_lock_reason())
        assert.is_true(preset:is_locked())
        assert.equals("Enable Custom Profile to edit", preset._lock_reason)
        preset._lock_reason = "Unrelated lock reason"
        assert.equals("Unrelated lock reason", preset:get_lock_reason())

        assert.equals(s.original_callback, s.listeners.MctOptionmovement_presetSet)
        s:fire("MctOptionSelectedSettingSet", {
            option = function() return preset end,
        })
        assert.equals(1, s.callback_calls)
    end)

    it("translates only the target page labels on repeated panel openings", function()
        local s = scenario()
        s:fire("MctPanelOpened")
        s:fire("MctPanelOpened")
        assert.equals("行军、地区与气候", s.pages[1].row.dy_title.text)
        assert.equals("海上、英雄与调试", s.pages[2].row.dy_title.text)
        assert.equals(2, s.pages[1].row.dy_title.writes)
        assert.equals(2, s.pages[2].row.dy_title.writes)
        assert.equals("Settings", s.pages[1]:get_key())
        assert.equals("Naval, Hero & Debug", s.pages[2]:get_key())
        assert.equals("Settings", s.foreign_pages[1].row.dy_title.text)
        assert.equals("Naval, Hero & Debug", s.foreign_pages[2].row.dy_title.text)
        assert.equals(0, s.foreign_pages[1].row.dy_title.writes)
        assert.equals(0, s.foreign_pages[2].row.dy_title.writes)
    end)

    it("leaves unrelated MCT mods alone when the source mod is absent", function()
        local s = scenario()
        s.mods[mod_key] = nil
        assert.has_no.errors(function()
            s:fire("MctInitialized")
            s:fire("MctPanelOpened")
        end)
        assert.equals("Light", s.options.movement_preset:get_values()[1].text)
        assert.equals(0, s.foreign_pages[1].row.dy_title.writes)
        assert.equals(0, s.foreign_pages[2].row.dy_title.writes)
    end)
end)
