-- This script will grab title and links from the Hacker News front page.
-- This example demonstrate how to extract content from a page without
-- necessarily rewriting it.
--
-- Run it like this:
--   curl -s https://news.ycombinator.com/ | lua hn.lua

local lolhtml = require "lolhtml"

-- This table will hold all our links
local links = {}

-- this variable will store the currently parsed link as the content extraction
-- will span across different callbacks
-- Note that `links[#links]` should be equivalent.
local current_link

local builder = lolhtml.new_rewriter_builder()
  :add_element_content_handlers {
    selector = lolhtml.new_selector "a.storylink",
    element_handler = function(el)
      -- This is called right after parsing the opening anchor: create a new
      -- link table and grab the target. the `tmp` filed will be used as an
      -- accumulator
      current_link = { href = el:get_attribute("href"), tmp = {} }
      table.insert(links, current_link)
    end,
    text_handler = function(t)
      -- Grabbing text is a bit more involved than attributes as the callback
      -- might be called an arbitrary number of times (depending how the text
      -- is fed into the parser.
      -- Here we use the accumulator to keep the whole text nutil the anchor
      -- tag is closed.
      table.insert(current_link.tmp, t:get_text())

      if t:is_last_in_text_node() then
        -- At this point the anchor tab is being closed and we are sure we
        -- grabbed the entire text.
        current_link.text = table.concat(current_link.tmp)
        current_link.tmp = {} -- reset the accumulator
      end
    end
  }
  -- grab the score: we need another selector for that
  :add_element_content_handlers {
    selector = lolhtml.new_selector "span.score",
    text_handler = function(t)
      -- This callback is called after the above one (as long as the page
      -- structure doesn't change. So we should have a current_link object.
      -- Apply the same accumulator technique as above.
      table.insert(current_link.tmp, t:get_text())

      if t:is_last_in_text_node() then
        local score = table.concat(current_link.tmp)
        current_link.tmp = {}

        -- now we just want the actual score as a number, not the text
        current_link.points = tonumber(score:match("^(%d+) points?$")) or -1
      end
    end
  }

local rewriter = lolhtml.new_rewriter {
  builder = builder,
  -- here we don't care about the output, just throw it away
  sink = function() end,
}

while true do
  local chunk = io.stdin:read(1024)
  if not chunk then break end
  assert(rewriter:write(chunk))
end
assert(rewriter:close())

for _, l in ipairs(links) do
  io.stdout:write(string.format("%s\n\tpoints: %d\n\tlink: %s\n", l.text, l.points, l.href))
end
