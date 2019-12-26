-- Reads HTML from the stdin stream, rewrites mixed content in it and streams
-- the result to the stdout.

local lolhtml = require "lolhtml"

local function rewrite_url_in_attr(el, attr)
  local val = el:get_attribute(attr):gsub("http://", "https://")
  el:set_attribute(attr, val)
end

-- create the rewriter
local rewriter = lolhtml.new_rewriter {
  builder = lolhtml.new_rewriter_builder()
    :add_element_content_handlers {
      selector = lolhtml.new_selector("a[href], link[rel=stylesheet][href]"),
      element_handler = function(el) rewrite_url_in_attr(el, "href") end,
    }
    :add_element_content_handlers {
      selector = lolhtml.new_selector("script[src], iframe[src], img[src], audio[src], video[src]"),
      element_handler = function(el) rewrite_url_in_attr(el, "src") end,
    },
  -- just write the output to stdout
  sink = function(s)
    io.stdout:write(s)
  end,
}

-- feed from stdin to the rewriter
for l in io.stdin:lines() do
  assert(rewriter:write(l .. "\n"))
end
assert(rewriter:close())
