rockspec_format = "3.0"
package = "lolhtml"
version = "dev-1"
source = {
  url = "git+https://github.com/jdesgats/lua-lolhtml.git"
}
description = {
  summary = "HTML parser/rewriter with CSS selector-based API",
  detailed = [[
  This library is a Lua binding for lol-html, a Low output latency
  streaming HTML parser/rewriter with CSS selector-based API.]],
  homepage = "https://github.com/jdesgats/lua-lolhtml",
  license = "BSD3"
}
dependencies = {
  "lua ~> 5.3"
}
build = {
  type = "make",
  install_pass = false,
  install = {
    lib = { lolhtml="lolhtml.so" },
  }
}
