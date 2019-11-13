ardour {
   ["type"]    = "EditorAction",
   name        = "Reset session start and end",
   license     = "MIT",
   author      = "Daniel Appelt",
   description = [[Reset session start and end markers according to existing regions]]
}

function factory (unused_params)
   return function ()
      local min = math.maxinteger
      local max = 0

      -- iterate over all regions in all available tracks and update min and max time
      for route in Session:get_tracks():iter() do
         for region in route:to_track():playlist():region_list():iter() do
            local pos = region:position()
            local len = region:length()

            if pos < min then min = pos end
            if pos + len > max then max = pos + len end
         end
      end

      -- reset session range markers
      local session_range = Session:locations():session_range_location()
      session_range:set_start(min, false, false, 1)
      session_range:set_end(max, false, false, 1)

      -- TODO: zoom in on whole session. There does not seem to be a LUA equivalent
      -- for temporal_zoom_session.
      -- Editor:temporal_zoom_session()
   end
end
