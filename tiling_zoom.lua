ardour {
   ["type"]    = "EditorAction",
   name        = "Tiling zoom",
   license     = "MIT",
   author      = "Daniel Appelt",
   description = [[Zoom 50% into first selected track and to 25% on both surrounding tracks]]
}

function factory (unused_params)
   return function ()
      local available = Editor:visible_canvas_height()
      local before_selection = true

      -- TODO: there does not seem to be an easy way to determine the currently selected
      -- visible track count. We use a fixed number of three tracks for now.
      Editor:set_visible_track_count(3)
      -- Scroll to top. TODO: there does not seem to be an easy way to do it.
      for route in Session:get_tracks():iter() do
         Editor:scroll_up_one_track()
      end

      -- Scroll to first three relevant tracks and resize them to 25%, 50%, 25% height.
      for route in Session:get_tracks():iter() do
         local tav = Editor:rtav_from_route(route):to_timeaxisview()

         if route:is_selected() then
	    -- Apply a "floor division"
            -- tav:set_height(available // 2)
            before_selection = false
         else
            -- TODO: this sets every other track to 25%
            -- Apply a "floor division"
            -- tav:set_height(available // 4)
         end

         if before_selection then Editor:scroll_down_one_track() end
      end
   end
end
