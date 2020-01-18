Lua binding for lol-html
========================

This library is a Lua binding for [lol-html][lolhtml], a *Low output latency
streaming HTML parser/rewriter with CSS selector-based API*.

It can be used to either extract data from HTML documents or rewrite them
on-the-fly.

Installation
------------

You need a functional setup of Rust and Cargo to be able to build this module.
Please refer to the [Rust website][rust-install] or install it with your
distribution's package manager.

Also, be sure to clone the submodules before trying to compile:

```
git submodule init --recursive
```

After that, the provided Makefile should be able to compile the module:

```
make
```

Running the test require [my fork][telescope] of Telescope:

```
luarocks install https://raw.githubusercontent.com/jdesgats/telescope/master/rockspecs/telescope-scm-1.rockspec
tsc spec/lolhtml.lua
```

Quick start
-----------

The workflow is usually:

1. Create a [*rewriter builder*](#rewriterbuilder-objects) object:
   ```lua
   local lolhtml = require "lolhtml"
   local my_builder = lolhtml.new_rewriter_builder()
   ```
2. Attach callbacks to it with the logic to transform your documents:
   ```lua
   my_builder:add_element_content_handlers {
     selector = lolhtml.new_selector("h1"),
     element_handler = function(el) el:set_attribute("class", "title") end
   }
   ```
3. Use the previous builder to create [*rewriter*](#rewriter-objects) objects,
   one for each HTML page you want to work on:
   ```lua
   local my_rewriter = lolhtml.new_rewriter {
     builder = my_builder,
     sink = function(s) print(s) end,
   }
   ```
4. Feed the rewriter with the actual HTML stream:
   ```lua
   for l in io.stdin:lines() do
     my_rewriter:write(l)
   end
   my_rewriter:close()
   ```

The `examples` directory contains a port of the original Rust examples from
lol-html. You can run them by feeding an HTML page as input:

```sh
curl -NL https://git.io/JeOSZ | lua examples/defer_scripts.lua
```

Status
------

**ALPHA VERSION**

This binding is not finished yet. Even if the test coverage is quite good and
pass and Valgrind is not complaining, bugs might still be present.

Also, the API is dot frozen and might change. Here are a non-exhaustive list
of things that I still consider:

* API naming: stay close of the original names, or choose shorter ones
* Selectors: should they be exposed at all? or compiled and cached transparently
* Some data could be exposed as attributes rather than methods, is it better?
* Tables vs. lots of arguments for some functions
* Error handling: when to raise errors, when to return `nil, err`

Reference
---------

This library tries to stay close of the original API, while being more Lua-ish
when appropriate. In particular it should not panic (as in triggering
`SIGABRT`), such case would be considered as a bug.

### Top-level objects

Object constructors:

* `lolhtml.new_selector`: see [`Selector`](#selector-objects)
* `lolhtml.new_rewriter_builder`: see [`RewriterBuilder`](#rewriterbuilder-objects)
* `lolhtml.new_rewriter`: see [`Rewriter`](#rewriter-objects)

Constants:

* `lolhtml.CONTINUE`
* `lolhtml.STOP`

### Selector objects

Selector object represent a parsed CSS selector that can be used to build
rewriter builders.

Selector objects don't have any methods or attributes. They are exposed only
for garbage collection purposes (and also as an optimization if you need to
reuse the same selector in multiple builders).

#### `lolhtml.new_selector(sel: string) => Selector | nil, err`

Builds a new [`Selector`](#selector-objects) object out of the give string.
Returns `nil, err` in case of syntax error.

### RewriterBuilder objects

The `RewriterBuilder` encapsulate the logic to make rewrites, usually they are
created at program startup and are used to instantiate many `Rewriter` objects.

All callbacks functions are called with a single argument whose type depend on
the type of callback. This argument should not outlive the callback and any
attempt to keep a reference of it to use it later will reeuslt in an error.

These functions can return:

* `lolhtml.CONTINUE`: instructs the parser to continue processing the HTML
  stream
* `lolhtml.STOP`: causes the parser to stop immediately, `write()` or `end()`
  methods of the rewriter will return an error code
* *nothing*: same as `lolhtml.CONTINUE`

If a callback raises an error, it will also causes the rewriter to stop
immediately. The error object or message will be returned as error by the
`write()` or `end()` methods of the rewriter.

#### `lolhtml.new_rewriter_builder() => RewriterBuilder`

Create a new `RewriterBuilder` object.

#### `RewriterBuilder:add_document_content_handlers(callbacks) => self`

Adds new document-level content handlers. This function might be called
multiple times to add multiple handlers.

The `callback` parameter must be a table with callbacks for different types
of events, the possible fields are:

* `doctype_handler`: called after parsing the Document Type declaration with
  a [`Doctype`](#doctype-objects) object.
* `comment_handler`: called whenever a comment is parsed with a
  [`Comment`](#comment-objects) object.
* `text_handler`: called when text nodes are parsed with a
  [`TextChunk`](#textchunk-objects) object.
* `doc_end_handler`: called at the end of the document with a
  [`DocumentEnd`](#documentend-objects) object.

All of the fields are optional. Calling a callback has a cost so leave out any
callback you don't need.

#### `RewriterBuilder:add_element_content_handlers(callbacks) => self`

Adds new element content handlers associated with a selector. This function
might be called multiple times to add multiple handlers for different
selectors.

The `callback` parameter must be a table with the selector and the callbacks
for different types of events, the possible fields are:

* `selector`: the [CSS selector](#selector-objects) to call the callbacks on
  (required)
* `comment_handler`: called whenever a comment is parsed with a
  [`Comment`](#comment-objects) object.
* `text_handler`: called when text nodes are parsed with a
  [`TextChunk`](#textchunk-objects) object.
* `element_handler`: called when an element is parsed with a
  [`Element`](#element-objects) object.

All of the fields are optional (except `selector`). Calling a callback has a
cost so leave out any callback you don't need.


### Rewriter objects

Rewriter object are processing a single HTML document and are instantiated with
a [`RewriterBuilder`](#rewriterbuilder-objects) object.

Each rewriter has an associated `sink`, which is a function called to output
the rewritten HTML.

#### `lolhtml.new_rewriter(options) => Rewriter | nil, err`

Creates a new reriter object. The `options` argument must be a table, the
following fields are allowed:

* `builder`: a `RewriterBuilder` object (required)
* `encoding`: the text encoding for the HTML stream. Can be a label for any of
  the web-compatible encodings with an exception for `UTF-16LE`, `UTF-16BE`,
  `ISO-2022-JP` and `replacement` (these non-ASCII-compatible encodings are
  not supported). (optional, default is `"utf-8"`)
* `preallocated_parsing_buffer_size`: Specifies the number of bytes that should
  be preallocated on HtmlRewriter instantiation for the internal parsing
  buffer. See [lol-html documentation][lolhtml-memory] for details. (optional,
  default is 1024)
* `max_allowed_memory_usage`: Sets a hard limit in bytes on memory consumption
  of a Rewriter instance. See [lol-html documentation][lolhtml-memory] for
  details. (optional, default is `SIZE_MAX`)
* `strict`: boolean, if set to true the rewriter bails out if it encounters
   markup that drives the HTML parser into ambigious state. See
  [lol-html documentation][lolhtml-strict] for details. (optional, default is
  `false`)

Returns the new Rewriter on success, or `nil` and an error message on failure.

#### `Rewriter:write(s) => self | nil, err`

Write HTML chunk to rewriter. Returns the rewriter itself on success, or `nil`
and an error message on failure. Failure happens if (incomplete list):

* A callback or a sink raises an error
* A previous invocation returned an error
* Called after `close`

#### `Rewriter:close(s) => self | nil, err`

Finalizes the rewriting process. Should be called once the last chunk of the
input is written. Returns the rewriter itself on success, or `nil` and an
error message on failure. Failure happens if (incomplete list):

* A callback or a sink raises an error
* A previous invocation returned an error
* Called more than once


### Doctype objects

#### `Doctype:get_name() => string|nil`
#### `Doctype:get_id() => string|nil`
#### `Doctype:get_system_id() => string|nil`

### Comment objects

#### `Comment:get_text() => string`
#### `Comment:set_text(string) => self|nil, err`
#### `Comment:before(string, is_html) => self|nil, err`
#### `Comment:after(string, is_html) => self|nil, err`
#### `Comment:replace(string, is_html) => self|nil, err`
#### `Comment:remove() => self|nil, err`
#### `Comment:is_removed() => boolean`

### TextChunk objects

#### `TextChunk:get_text() => string`
#### `TextChunk:is_last_in_text_node() => boolean`
#### `TextChunk:before(string, is_html) => self|nil, err`
#### `TextChunk:after(string, is_html) => self|nil, err`
#### `TextChunk:replace(string, is_html) => self|nil, err`
#### `TextChunk:remove() => self|nil, err`
#### `TextChunk:is_removed() => boolean`

### Element objects

#### `Element:get_tag_name() => string`
#### `Element:get_namespace_uri() => string`
#### `Element:get_attribute(name) => string|nil`
#### `Element:has_attribute(name) => boolean`
#### `Element:set_attribute(name, value) => self|nil, err`
#### `Element:remove_attribute(name) => self|nil, err`
#### `Element:attributes() => iterator`

Returns a Lua iterator triplet so the following construction is valid:

```lua
for attr_name, value in element:attribute() do
  ...
end
```

#### `Element:before(string, is_html) => self|nil, err`
#### `Element:after(string, is_html) => self|nil, err`
#### `Element:prepend(string, is_html) => self|nil, err`
#### `Element:append(string, is_html) => self|nil, err`
#### `Element:set_inner_content(string, is_html) => self|nil, err`
#### `Element:replace(string, is_html) => self|nil, err`
#### `Element:remove() => self|nil, err`
#### `Element:remove_and_keep_content() => self|nil, err`
#### `Element:is_removed() => boolean`

### DocumentEnd objects

#### `DocumentEnd:append(string, is_html) => self|nil, err`


[lolhtml]: https://github.com/cloudflare/lol-html
[lolhtml-memory]: https://docs.rs/lol_html/0.1.0/lol_html/struct.MemorySettings.html
[lolhtml-strict]: https://docs.rs/lol_html/0.1.0/lol_html/struct.Settings.html#structfield.stricti
[rust-install]: https://www.rust-lang.org/tools/install
