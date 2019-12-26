-- Reads HTML from the stdin stream and defers render-blocking scripts, then
-- streams the result to the stdout.

local lolhtml = require "lolhtml"

-- create the rewriter
local rewriter = lolhtml.new_rewriter {
  builder = lolhtml.new_rewriter_builder()
    :add_element_content_handlers {
      selector = lolhtml.new_selector("script[src]:not([async]):not([defer])"),
      element_handler = function(el)
        el:set_attribute("defer", "")
      end
    },
  -- just write the output to stdout
  sink = function(s)
    io.stdout:write(s)
  end,
}

-- feed from stdin to the rewriter
for l in io.stdin:lines() do
  rewriter:write(l .. "\n")
end
rewriter:close()
