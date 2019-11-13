ardour {
   ["type"]    = "EditorAction",
   name        = "LFO automation",
   license     = "MIT",
   author      = "Daniel Appelt",
   description = [[Add LFO-like plugin automation to selected region]]
}

function factory (unused_params)
   return function ()
      -- Retrieve the first selected region
      -- TODO: the following statement should do just that, no!?
      -- local region = Editor:get_selection().regions:regionlist():front()
      local region = nil
      for r in Editor:get_selection().regions:regionlist():iter() do
         if region == nil then region = r end
      end

      -- Bail out if no region was selected
      if region == nil then
         LuaDialog.Message("LFO Automation", "Please first select a region", LuaDialog.MessageType.Info, LuaDialog.ButtonType.Close):run()
         return
      end

      -- Identify the track the region belongs to. There really is no better way?!
      local track = nil
      for route in Session:get_tracks():iter() do
         for r in route:to_track():playlist():region_list():iter() do
            if r == region then track = route:to_track() end
         end
      end

      -- Get a list of all available plugin parameters on the track. For the original code
      -- see https://github.com/Ardour/ardour/blob/master/scripts/midi_cc_to_automation.lua
      local targets = {}
      local i = 0
      while true do -- iterate over all plugins on the route
         local proc = track:nth_plugin(i)
         if proc:isnil() then break end
         -- print(proc:display_name())
         local plug = proc:to_insert():plugin(0) -- we know it's a plugin-insert (we asked for nth_plugin)
         local n = 0 -- count control-ports
         for j = 0, plug:parameter_count() - 1 do -- iterate over all plugin parameters
            if plug:parameter_is_control(j) then
               local label = plug:parameter_label(j)
               -- print(label)
               if plug:parameter_is_input(j) and label ~= "hidden" and label:sub(1,1) ~= "#" then
                  local nn = n --local scope for return value function
                  -- TODO handle ambiguity if there are 2 plugins with the same name on the same track
                  -- we need 2 return values: the plugin-instance and the parameter-id, so we use a table (associative array)
                  -- however, we cannot directly use a table: the dropdown menu would expand it as another sub-menu.
                  -- so we produce a function that will return the table.
                  targets[proc:display_name()] = targets[proc:display_name()] or {}
                  targets[proc:display_name()][label] = function() return {["p"] = proc, ["n"] = nn} end
               end
               n = n + 1
            end
         end
         i = i + 1
      end

      -- Bail out if there are no parameters
      if next(targets) == nil then
         LuaDialog.Message("LFO Automation", "No plugin parameters found", LuaDialog.MessageType.Info, LuaDialog.ButtonType.Close):run()
         region, track, targets = nil, nil, nil
         collectgarbage()
         return
      end

      -- Display dialog to select (plugin and) plugin parameter, and LFO cycle type + min / max
      local dialog_options = {
         { type = "heading", title = "LFO automation", align = "left"},
         { type = "dropdown", key = "param", title = "Plugin parameter", values = targets },
         { type = "dropdown", key = "wave", title = "Waveform", values =
              { ["Ramp up"] = 1, ["Ramp down"] = 2, ["Triangle"] = 3, ["Sine"] = 4, ["Exp up"] = 5, ["Exp down"] = 6, ["Log up"] = 7, ["Log down"] = 8 } },
         { type = "number", key = "cycles", title = "No. of cycles", min = 1, max = 16, step = 1, digits = 0 },
         { type = "slider", key = "min", title = "Minimum in %", min = 0, max = 100, digits = 1 },
         { type = "slider", key = "max", title = "Maximum in %", min = 0, max = 100, digits = 1, default = 100 }
      }
      local rv = LuaDialog.Dialog("Select target", dialog_options):run()

      -- Return if the user cancelled
      if not rv then
         region, track, targets = nil, nil, nil
         collectgarbage()
         return
      end

      -- Parse user response
      assert(type(rv["param"]) == "function")
      local pp = rv["param"]() -- evaluate function, retrieve table {["p"] = proc, ["n"] = nn}
      local al, _, pd = ARDOUR.LuaAPI.plugin_automation(pp["p"], pp["n"])
      local wave = rv["wave"]
      local cycles = rv["cycles"]
      -- Compute minimum and maximum requested parameter values
      local lower = pd.lower + rv["min"] / 100 * (pd.upper - pd.lower)
      local upper = pd.lower + rv["max"] / 100 * (pd.upper - pd.lower)
      track, targets, rv, pd = nil, nil, nil, nil
      assert(not al:isnil())

      -- Define lookup tables for our waves
      local lut = {
         { 0, 1 }, -- ramp up
         { 1, 0 }, -- ramp down
         { 0, 1, 0 }, -- triangle
         {}, -- sine
         {}, -- exp up
         {}, -- exp down
         {}, -- log up
         {} -- log down
      }

      -- Calculate missing look up tables
      local log_min = math.exp(-2 * math.pi)
      for i = 0, 20 do
         -- sine
         lut[4][i+1] = 0.5 * math.sin(i * math.pi / 10) + 0.5
         -- exp up
         lut[5][i+1] = math.exp(-2 * math.pi + i * math.pi / 10)
         -- log up
         lut[7][i+1] = -math.log(1 + (i / log_min - i) / 20) / math.log(log_min)
      end

      for i = 21, 1, -1 do
         -- exp down
         lut[6][22-i] = lut[5][i]
         -- log down
         lut[8][22-i] = lut[7][i]
      end

      -- Initialize undo
      Session:begin_reversible_command("LFO automation")
      local before = al:get_state() -- save previous state (for undo)
      al:clear_list() -- clear target automation-list

      local values = lut[wave]
      local last = nil
      for i = 0, cycles - 1 do
         -- cycle length = region:length() / cycles
         local cycle_start = region:position() - region:start() + i * region:length() / cycles
         local offset = region:length() / cycles / (#values - 1)

         for k, v in pairs(values) do
            local pos = cycle_start + (k - 1) * offset
            if k == 1 and v ~= last then
               -- Move event one sample further
               pos = pos + 1
            end

            if k > 1 or v ~= last then
               -- Create automation point re-scaled to parameter target range. Do not create a new point
               -- at cycle start if the last cycle ended on the same value.
               al:add(pos, lower + v * (upper - lower), false, true)
            end
            last = v
         end
      end

      -- Save undo
      Session:add_command(al:memento_command(before, al:get_state()))
      Session:commit_reversible_command(nil)

      region, al, lut = nil, nil, nil
      collectgarbage()
   end
end
