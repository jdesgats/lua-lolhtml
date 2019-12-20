local lolhtml = require "lolhtml"

-- Note: these tests are not meant to test lolhtml itself (it already has tests
-- on its own), but the Lua binding and its behaviour

local basic_page = [[
<!DOCTYPE html>
<html>
  <head>
    <title>Hello, Lua-lolhtml</title>
  </head>
  <body>
    <!--hello, comments-->
    <h1>Hello, Lua-lolhtml</h1>
  </body>
</html>
]]

-- basic string buffer for the sink
local sink_buffer do
  local mt = {
    __index = { value = table.concat },
    __call = table.insert
  }
  sink_buffer = function()
    return setmetatable({}, mt)
  end
end

describe("lolhtml rewriter", function()
  after(function()
    collectgarbage("collect")
  end)

  test("basic pipeline", function()
    local result = {}
    local function sink(t) table.insert(result, t) end

    local rewriter = lolhtml.new_rewriter {
      builder = lolhtml.new_rewriter_builder(),
      sink = sink,
    }
    assert(rewriter:write(basic_page))
    assert(rewriter:close())
    assert_equal(table.concat(result), basic_page)
  end)

  test("callable sink", function()
    local buf = sink_buffer()
    local rewriter = lolhtml.new_rewriter {
      builder = lolhtml.new_rewriter_builder(),
      sink = buf,
    }
    assert(rewriter:write(basic_page))
    assert(rewriter:close())
    assert_equal(buf:value(), basic_page)
  end)

  describe("document content handlers", function()
    test("doctype handler", function()
      local data, buf = nil, sink_buffer()
      local kept_ref
      local builder = lolhtml.new_rewriter_builder()
        :add_document_content_handlers{
          doctype_handler = function(doctype)
            data = { doctype:get_name(), doctype:get_id(), doctype:get_system_id() }
            kept_ref = doctype
          end
        }
      collectgarbage("collect") -- loose the ref to the handler function

      local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
      assert(rewriter:write(basic_page))
      assert(rewriter:close())
      assert_not_nil(data, "callback not called")
      assert_equal(data[1], "html")
      assert_equal(data[2], nil)
      assert_equal(data[3], nil)
      assert_equal(buf:value(), basic_page)

      -- now try to use the doctype object outside of the callback
      assert_not_nil(kept_ref)
      assert_error(function() kept_ref:get_name() end)

      local full_doctype = [[
        <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
        "http://www.w3.org/TR/html4/strict.dtd">
      ]]
      data, buf = nil, sink_buffer()
      rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
      assert(rewriter:write(full_doctype))
      assert_not_nil(data, "callback not called")
      assert_equal(data[1], "html")
      assert_equal(data[2], "-//W3C//DTD HTML 4.01//EN")
      assert_equal(data[3], "http://www.w3.org/TR/html4/strict.dtd")
      assert_equal(buf:value(), full_doctype)
    end)

    describe("comment_handler", function()
      local function run_parser(input, cb)
        local buf = sink_buffer()
        local builder = lolhtml.new_rewriter_builder()
          :add_document_content_handlers{
            comment_handler = cb,
          }
        local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
        assert(rewriter:write(input))
        assert(rewriter:close())
        collectgarbage("collect") -- loose the ref to the handler and builder
        return buf:value()
      end

      test("get_text", function()
        local data
        local out = run_parser(basic_page, function(comment)
          data = comment:get_text()
        end)
        assert_equal(out, basic_page)
        assert_equal(data, "hello, comments")
      end)

      test("set_text", function()
        local out = run_parser("<!--replace me--> hello <!-- and me -->", function(comment)
          comment:set_text("replaced")
        end)
        assert_equal(out, "<!--replaced--> hello <!--replaced-->")
      end)

      test("before/after", function()
        local out = run_parser("hello, <!-- comment -->", function(comment)
          comment:before("<World>")
          comment:after("<strong>!</strong>", true)
        end)
        assert_equal(out, "hello, &lt;World&gt;<!-- comment --><strong>!</strong>")
      end)

      test("replace", function()
        local out = run_parser("hello, <!-- comment -->", function(comment)
          comment:replace("World!")
        end)
        assert_equal(out, "hello, World!")
      end)

      test("remove/is_removed", function()
        local before_removing, after_removing
        local out = run_parser("hello, <!-- comment -->", function(comment)
          before_removing = comment:is_removed()
          comment:remove()
          after_removing = comment:is_removed()
        end)
        assert_equal(out, "hello, ")
        assert_false(before_removing)
        assert_true(after_removing)
      end)

      test("usage after lifetime", function()
        local c
        run_parser("hello, <!-- comment -->", function(comment) c=comment end)

        assert_error(function() c:get_text() end)
        assert_error(function() c:set_text("foo") end)
        assert_error(function() c:before("foo") end)
        assert_error(function() c:after("foo") end)
        assert_error(function() c:replace("foo") end)
        assert_error(function() c:remove() end)
        assert_error(function() c:is_removed() end)
      end)
    end)

    describe("text chunk handler", function()
      local function run_parser(input, cb)
        local buf = sink_buffer()
        local builder = lolhtml.new_rewriter_builder()
          :add_document_content_handlers{
            text_handler = cb,
          }
        local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
        assert(rewriter:write(input))
        assert(rewriter:close())
        collectgarbage("collect") -- loose the ref to the handler and builder
        return buf:value()
      end

      test("get_text/is_last_in_text_node", function()
        local calls = {}
        local out = run_parser("foo<b>bar</b>baz", function(text)
          local txt = text:get_text()
          if txt == "" then
            assert_true(text:is_last_in_text_node())
          else
            assert_false(text:is_last_in_text_node())
            table.insert(calls, txt)
          end
        end)
        assert_equal(out, "foo<b>bar</b>baz")
        assert_equal(#calls, 3)
        assert_equal(calls[1], "foo")
        assert_equal(calls[2], "bar")
        assert_equal(calls[3], "baz")
      end)

      test("before/after", function()
        local out = run_parser("World", function(chunk)
          if chunk:get_text() == "" then
            chunk:after("<strong>!</strong>", true)
          else
            chunk:before("<Hello>, ")
          end
        end)
        assert_equal(out, "&lt;Hello&gt;, World<strong>!</strong>")
      end)

      test("replace", function()
        local out = run_parser("Hello, <em>World</em>!", function(chunk)
          if chunk:get_text() == "World" then
            chunk:replace("lolhtml")
          end
        end)
        assert_equal(out, "Hello, <em>lolhtml</em>!")
      end)

      test("remove/is_removed", function()
        local out = run_parser("Hello, <em>World</em>!", function(chunk)
          assert_false(chunk:is_removed())
          if chunk:get_text() == "World" then
            chunk:remove()
            assert_true(chunk:is_removed())
          end
        end)
        assert_equal(out, "Hello, <em></em>!")
      end)

      test("usage after lifetime", function()
        local c
        run_parser("hello, <em>World</em>!", function(chunk) c=chunk end)

        assert_error(function() c:get_text() end)
        assert_error(function() c:is_last_in_text_node() end)
        assert_error(function() c:before("foo") end)
        assert_error(function() c:after("foo") end)
        assert_error(function() c:replace("foo") end)
        assert_error(function() c:remove() end)
        assert_error(function() c:is_removed() end)
      end)
    end)

    test("docuemnt end", function()
      local buf = sink_buffer()
      local ref
      local builder = lolhtml.new_rewriter_builder()
        :add_document_content_handlers{
          doc_end_handler = function(doc_end)
            doc_end:append("bye...")
            ref = doc_end
          end,
        }
      collectgarbage("collect") -- loose the ref to the handler function
      local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
      assert(rewriter:write(basic_page):close())
      assert_equal(buf:value(), basic_page .. "bye...")
      assert_error(function() ref:append("foo") end)
    end)

    test("multiple handlers", function()
      local buf = sink_buffer()
      local calls = {}
      local builder = lolhtml.new_rewriter_builder()
        :add_document_content_handlers {
          doc_end_handler = function() table.insert(calls, "doc_end 1") end
        }:add_document_content_handlers {
          doctype_handler = function() table.insert(calls, "doctype") end,
          doc_end_handler = function() table.insert(calls, "doc_end 2") end
        }
      collectgarbage("collect") -- loose the ref to the handler function
      local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
      assert(rewriter:write(basic_page):close())
      assert_equal(buf:value(), basic_page)
      assert_same(calls, { "doctype", "doc_end 2", "doc_end 1" })
    end)

    describe("handler throws errors", function()
      for _, callback in ipairs { "doctype_handler", "comment_handler", "text_handler" } do
        test(callback, function()
          local buf = sink_buffer()
          local error_object = {} -- do not throw a string here, otherwise the Lua runtime will decorate it
          local builder = lolhtml.new_rewriter_builder()
            :add_document_content_handlers{
              [callback] = function() error(error_object) end
            }
          collectgarbage("collect") -- loose the ref to the handler function
          local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
          local ok, err = rewriter:write(basic_page)
          assert_nil(ok)
          assert_equal(err, error_object)
          -- the result should be a subset of the page we fed
          assert_equal(basic_page:find(buf:value(), 1, true), 1)

          -- now try do interact again with the rewriter, it should raise errors
          -- (and not crash, preferably)
          assert_nil(rewriter:write("foo"))
          assert_nil(rewriter:close())
        end)
      end

      test("doc_end", function()
          local buf = sink_buffer()
          local error_object = {} -- do not throw a string here, otherwise the Lua runtime will decorate it
          local builder = lolhtml.new_rewriter_builder()
            :add_document_content_handlers{
              doc_end_handler = function() error(error_object) end
            }
          collectgarbage("collect") -- loose the ref to the handler function
          local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
          assert(rewriter:write(basic_page))
          local ok, err = rewriter:close()
          assert_nil(ok)
          assert_equal(err, error_object)
          -- the result should be a subset of the page we fed
          assert_equal(basic_page:find(buf:value(), 1, true), 1)
      end)
    end)


    describe("callback return values", function()
      local function run(val)
        local builder = lolhtml.new_rewriter_builder()
          :add_document_content_handlers {
            text_handler = function(chunk) return val end
          }
        local buf = sink_buffer()
        local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
        local ok, err = rewriter:write("foo<em>bar</em><em>baz</em>")
        return rewriter, ok, err, buf
      end

      test("continue", function()
        local rewriter, ok, err, buf = run(lolhtml.CONTINUE)
        assert_equal(ok, rewriter) -- no error: return self
        assert_equal(rewriter:close(), rewriter)
        assert_equal(buf:value(), "foo<em>bar</em><em>baz</em>")
      end)

      for testcase, val in pairs {
        ["stop"] = lolhtml.STOP,
        ["other numbers"] = 42,
        ["wrong type"] = {}
      } do
        test(testcase, function()
          local rewriter, ok, err, buf = run(val)
          assert_nil(ok)
          assert_type(err, "string")
          -- keep using the rewriter will result in errors
          assert_nil(rewriter:write("foo"))
          assert_nil(rewriter:close())
        end)
      end
    end)
  end)

  test("write after close", function()
    local buf = sink_buffer()
    local rewriter = lolhtml.new_rewriter {
      builder=lolhtml.new_rewriter_builder(),
      sink = buf,
    }

    assert(rewriter:write("hello, "))
    assert(rewriter:close())
    assert_nil(rewriter:write("world"))
  end)

  test("sink throw errors", function()
    local called = false
    local error_object = {}
    local rewriter = lolhtml.new_rewriter {
      builder=lolhtml.new_rewriter_builder(),
      sink = function()
        called = true
        error(error_object)
      end
    }

    -- XXX: hard to tell when the error will be thrown (at the :write call
    -- or at the :close). If this test breaks, it might be because of an
    -- internal change in lol-html
    local ok, err = rewriter:write("hello, world")
    assert_true(called)
    assert_nil(ok)
    assert_equal(err, error_object)
    local ok, err = rewriter:close()
    assert_nil(ok)
    assert_equal(err, "broken rewriter")
  end)

  test("selector syntax errors", function()
    local ok, err = lolhtml.new_selector("foo[attr=")
    assert_nil(ok)
    assert_type(err, "string")
  end)

  describe("element content handlers", function()
    -- comment/text are the samie as the document handlers, so minimal testing is done
    test("comment_handler", function()
      local buf = sink_buffer()
      local builder = lolhtml.new_rewriter_builder()
        :add_element_content_handlers{
          selector = lolhtml.new_selector("strong"),
          comment_handler = function(comment)
            assert_equal(comment:get_text(), " name ")
            comment:set_text(" World ")
          end,
        }
      collectgarbage("collect")
      local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
      assert(rewriter:write("<!--before -->hello, <strong><!-- name --></strong><!-- after -->"))
      assert(rewriter:close())
      assert_equal(buf:value(), "<!--before -->hello, <strong><!-- World --></strong><!-- after -->")
    end)

    test("text_handler", function()
      local buf = sink_buffer()
      local builder = lolhtml.new_rewriter_builder()
        :add_element_content_handlers{
          selector = lolhtml.new_selector("strong"),
          text_handler = function(text)
            -- this handler might be called multiple times
            if text:get_text() == "name" then
              text:replace("World")
            end
          end,
        }
      collectgarbage("collect")
      local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
      assert(rewriter:write("hello, <strong>name</strong>"))
      assert(rewriter:close())
      assert_equal(buf:value(), "hello, <strong>World</strong>")
    end)

    describe("element_handler", function()
      local function run_parser(sel, input, cb)
        local buf = sink_buffer()
        local builder = lolhtml.new_rewriter_builder()
          :add_element_content_handlers{
            selector = lolhtml.new_selector(sel),
            element_handler = cb,
          }
        local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
        assert(rewriter:write(input))
        assert(rewriter:close())
        collectgarbage("collect") -- loose the ref to the handler and builder
        return buf:value()
      end

      test("get_tag_name/get_namespace_uri", function()
        local called = 0
        local out = run_parser("h1", basic_page, function(el)
          called = called + 1
          assert_equal(el:get_tag_name(), "h1")
          assert_type(el:get_namespace_uri(), "string")
        end)

        assert_equal(1, called)
        assert_equal(out, basic_page)
      end)

      test("get_attribute/has_attribute", function()
        local called = 0
        local out = run_parser("a", '<em>hello</em>, <a href="http://example.com">World</a>!', function(el)
          called = called + 1
          assert_true(el:has_attribute("href"))
          assert_equal(el:get_attribute("href"), "http://example.com")
          assert_false(el:has_attribute("foo"))
          assert_nil(el:get_attribute("foo"))
        end)
        assert_equal(1, called)
        assert_equal(out, '<em>hello</em>, <a href="http://example.com">World</a>!')
      end)

      test("set_attribute", function()
        local out = run_parser("a", '<em>hello</em>, <a href="http://example.com">World</a>!', function(el)
          assert_not_nil(el:set_attribute("href", "https://example.com"))
          assert_not_nil(el:set_attribute("target", "_blank"))
        end)

        -- XXX: the position of new attributes is kind of an implementation detail, so this might break easily
        assert_equal(out, '<em>hello</em>, <a href="https://example.com" target="_blank">World</a>!')
      end)

      test("remove attribute", function()
        local out = run_parser("a", '<em target="foo">hello</em>, <a href="http://example.com" target="_blank">World</a>!', 
        function(el)
          assert_not_nil(el:remove_attribute("target"))
          assert_not_nil(el:remove_attribute("foo")) -- removing non-existant element should "work"
        end)
        assert_equal(out, '<em target="foo">hello</em>, <a href="http://example.com">World</a>!')
      end)

      local test_table = {
        { method="before", is_html="<em>hello</em>, <TEST><b>World</b>!", no_html="<em>hello</em>, &lt;TEST&gt;<b>World</b>!" },
        { method="after", is_html="<em>hello</em>, <b>World</b><TEST>!", no_html="<em>hello</em>, <b>World</b>&lt;TEST&gt;!" },
        { method="prepend", is_html="<em>hello</em>, <b><TEST>World</b>!", no_html="<em>hello</em>, <b>&lt;TEST&gt;World</b>!" },
        { method="append", is_html="<em>hello</em>, <b>World<TEST></b>!", no_html="<em>hello</em>, <b>World&lt;TEST&gt;</b>!" },
        { method="set_inner_content", is_html="<em>hello</em>, <b><TEST></b>!", no_html="<em>hello</em>, <b>&lt;TEST&gt;</b>!" },
        { method="replace", is_html="<em>hello</em>, <TEST>!", no_html="<em>hello</em>, &lt;TEST&gt;!" },
      }

      for _, testcase in ipairs(test_table) do
        test(testcase.method .. " is_html=true", function()
          local out = run_parser("b", '<em>hello</em>, <b>World</b>!', function(el)
            el[testcase.method](el, "<TEST>", true)
          end)
          assert_equal(out, testcase.is_html)
        end)
        test(testcase.method .. " is_html=false", function()
          local out = run_parser("b", '<em>hello</em>, <b>World</b>!', function(el)
            el[testcase.method](el, "<TEST>", false)
          end)
          assert_equal(out, testcase.no_html)
        end)
      end

      test("remove", function()
        local out = run_parser("b", '<em>hello</em>, <b>World</b>!', function(el)
          assert_false(el:is_removed())
          assert_not_nil(el:remove())
          assert_true(el:is_removed())
        end)
        assert_equal(out, '<em>hello</em>, !')
      end)

      test("remove_and_keep_content", function()
        local out = run_parser("b", '<em>hello</em>, <b>World</b>!', function(el)
          assert_false(el:is_removed())
          assert_not_nil(el:remove_and_keep_content())
          assert_true(el:is_removed())
        end)
        assert_equal(out, '<em>hello</em>, World!')
      end)

      test("attributes", function()
        local called = 0
        run_parser("a", '<em target="foo">hello</em>, <a href="http://example.com" target="_blank">World</a>!',
        function(el)
          local it = 0
          called = called + 1
          for name, value in el:attributes() do
            it = it + 1
            if it == 1 then
              assert_equal(name, "href")
              assert_equal(value, "http://example.com")
            elseif it == 2 then
              assert_equal(name, "target")
              assert_equal(value, "_blank")
            else
              error("more than 2 iterations")
            end
          end
        end)
        assert_equal(called, 1)
      end)

      test("usage after lifetime", function()
        local el
        run_parser("b", '<em>hello</em>, <b>World</b>!', function(e) el=e end)
        assert_error(function() el:get_tag_name() end)
        assert_error(function() el:get_namespace_uri() end)
        assert_error(function() el:get_attribute("foo") end)
        assert_error(function() el:has_attribute("foo") end)
        assert_error(function() el:set_attribute("foo", "bar") end)
        assert_error(function() el:remove_attribute("foo") end)
        assert_error(function() el:attributes() end)
        assert_error(function() el:before("foo") end)
        assert_error(function() el:after("foo") end)
        assert_error(function() el:prepend("foo") end)
        assert_error(function() el:append("foo") end)
        assert_error(function() el:set_inner_content("foo") end)
        assert_error(function() el:replace("foo") end)
        assert_error(function() el:is_removed() end)
        assert_error(function() el:remove() end)
        assert_error(function() el:remove_and_keep_content() end)
      end)

      test("multiple selectors", function()
        local buf = sink_buffer()
        local builder = lolhtml.new_rewriter_builder()
          :add_element_content_handlers {
            selector = lolhtml.new_selector("span"),
            element_handler = function(el)
              el:set_inner_content("span content")
            end
          }
          :add_element_content_handlers {
            selector = lolhtml.new_selector("div"),
            element_handler = function(el)
              el:set_inner_content("div content")
            end
          }
        local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
        collectgarbage("collect")
        assert(rewriter:write("aaa <span>bbb</span> ccc <div>ddd</div> eee <span>fff</span> ggg"))
        assert(rewriter:close())
        collectgarbage("collect")
        assert_equal(buf:value(), "aaa <span>span content</span> ccc <div>div content</div> eee <span>span content</span> ggg")
      end)
      test("multiple handlers for the same selector", function()
        local buf = sink_buffer()
        local counter = 0
        local builder = lolhtml.new_rewriter_builder()
          :add_element_content_handlers {
            selector = lolhtml.new_selector("span"),
            element_handler = function(el)
              el:set_inner_content("span content")
            end
          }
          :add_element_content_handlers {
            selector = lolhtml.new_selector("span"),
            element_handler = function(el)
              counter = counter + 1
              el:set_attribute("count", tostring(counter))
            end
          }
        local rewriter = lolhtml.new_rewriter { builder=builder, sink=buf }
        collectgarbage("collect")
        assert(rewriter:write("aaa <span>bbb</span> ccc <div>ddd</div> eee <span>fff</span> ggg"))
        assert(rewriter:close())
        collectgarbage("collect")
        assert_equal(buf:value(), 'aaa <span count="1">span content</span> ccc <div>ddd</div> eee <span count="2">span content</span> ggg')
      end)
    end)
  end)
end)
