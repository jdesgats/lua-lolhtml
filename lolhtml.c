#include <lua.h>
#include <lauxlib.h>
#include <lol_html.h>
#include <stdint.h>

#define PREFIX "lolhtml."

/* VM registry name for a module wide sub-registry used to keep references to
 * actual objects using `luaL_ref` in case where we need to retrieve Lua objects
 * from callbacks.
 * This table will have weak values so it doesn't prevent GC.
 */
#define LOL_REGISTRY (PREFIX "weakreg")

typedef struct {
    lua_State *L;
    int builder_index;
    int callback_index;
} handler_data_t;

/* fallback in case lol_html_take_last_error fails */
static lol_html_str_t default_err = {
    .data = "unknown error",
    .len = sizeof("unknown error"),
};

static void push_lol_str_maybe(lua_State *L, const lol_html_str_t *s) {
    if (s == NULL) {
        lua_pushnil(L);
    } else {
        lua_pushlstring(L, s->data, s->len);
    }
}

static int push_last_error(lua_State *L) {
    lol_html_str_t *err = lol_html_take_last_error();
    if (err == NULL) err = &default_err;
    lua_pushnil(L);
    lua_pushlstring(L, err->data, err->len);
    return 2;
}

/* checks a function result code and prepares a method reutrn to Lua:
 * if zero, shrik the stack to 1 (the slef argument) and returns 1
 * otherwise, pushes nil and the error message and retuns 2
 */
static int return_self_or_err(lua_State *L, int rc) {
    if (rc != 0) {
        return push_last_error(L);
    }
    lua_settop(L, 1);
    return 1;
}

/* document content handlers callbacks */
static void init_document_content_callback(handler_data_t *handler) {
    lua_getfield(handler->L, LUA_REGISTRYINDEX, LOL_REGISTRY); /* reg */
    lua_rawgeti(handler->L, -1, handler->builder_index);       /* reg, ud */
    lua_getuservalue(handler->L, -1);                          /* reg, ud, uv */
    lua_rawgeti(handler->L, -1, handler->callback_index);      /* reg, ud, uv, cb */
    lua_replace(handler->L, -4);                               /* cb, ud, uv */
    lua_pop(handler->L, 2);                                    /* cb */
}

static lol_html_rewriter_directive_t call_document_content_callback(lua_State *L) {
    lol_html_rewriter_directive_t directive;

    // TODO: pcall
    lua_call(L, 1, 1);

    switch (lua_type(L, -1)) {
    case LUA_TNIL: /* no return value => assume continue */
        directive = LOL_HTML_CONTINUE;
        break;
    case LUA_TNUMBER: {
        int isnum;
        lua_Integer result = lua_tointegerx(L, -1, &isnum);
        if (!isnum) goto error;
        switch (result) {
        case LOL_HTML_CONTINUE:
        case LOL_HTML_STOP:
            directive = result;
            break;
        default: goto error;
        }
    }
    default: goto error;
    }

    return directive;

error:
    // TODO: is it safe to throw errors here?
    // probably shold stop processing and return an error afterwards
    luaL_error(L, "invalid return value");
    return LOL_HTML_STOP; /* never actually reached */
}

static lol_html_rewriter_directive_t
doctype_handler(lol_html_doctype_t *doctype, void *user_data)
{
    handler_data_t *handler = user_data;
    init_document_content_callback((handler_data_t*) user_data);

    lol_html_doctype_t **lua_doctype = lua_newuserdata(handler->L, sizeof(lol_html_doctype_t *));
    luaL_getmetatable(handler->L, PREFIX "doctype");
    lua_setmetatable(handler->L, -2);
    *lua_doctype = doctype;

    return call_document_content_callback(handler->L);
}

static lol_html_rewriter_directive_t
comment_handler(lol_html_comment_t *comment, void *user_data)
{
    handler_data_t *handler = user_data;
    init_document_content_callback((handler_data_t*) user_data);

    lol_html_comment_t **lua_comment = lua_newuserdata(handler->L, sizeof(lol_html_comment_t *));
    luaL_getmetatable(handler->L, PREFIX "comment");
    lua_setmetatable(handler->L, -2);
    *lua_comment = comment;

    return call_document_content_callback(handler->L);
}

static lol_html_rewriter_directive_t
text_chunk_handler(lol_html_text_chunk_t *chunk, void *user_data)
{
    handler_data_t *handler = user_data;
    init_document_content_callback((handler_data_t*) user_data);

    lol_html_text_chunk_t **lua_text_chunk = lua_newuserdata(handler->L, sizeof(lol_html_text_chunk_t *));
    luaL_getmetatable(handler->L, PREFIX "text_chunk");
    lua_setmetatable(handler->L, -2);
    *lua_text_chunk = chunk;

    return call_document_content_callback(handler->L);
}

static lol_html_rewriter_directive_t
doc_end_handler(lol_html_doc_end_t *doc_end, void *user_data)
{
    handler_data_t *handler = user_data;
    init_document_content_callback((handler_data_t*) user_data);

    lol_html_doc_end_t **lua_doc_end = lua_newuserdata(handler->L, sizeof(lol_html_doc_end_t *));
    luaL_getmetatable(handler->L, PREFIX "doc_end");
    lua_setmetatable(handler->L, -2);
    *lua_doc_end = doc_end;

    return call_document_content_callback(handler->L);
}

/* doctype */
static int doctype_get_name(lua_State *L) {
    const lol_html_doctype_t **doctype = luaL_checkudata(L, 1, PREFIX "doctype");
    push_lol_str_maybe(L, lol_html_doctype_name_get(*doctype));
    return 1;
}

static int doctype_get_id(lua_State *L) {
    const lol_html_doctype_t **doctype = luaL_checkudata(L, 1, PREFIX "doctype");
    push_lol_str_maybe(L, lol_html_doctype_public_id_get(*doctype));
    return 1;
}

static int doctype_get_system_id(lua_State *L) {
    const lol_html_doctype_t **doctype = luaL_checkudata(L, 1, PREFIX "doctype");
    push_lol_str_maybe(L, lol_html_doctype_system_id_get(*doctype));
    return 1;
}

static luaL_Reg doctype_methods[] = {
    { "get_name", doctype_get_name },
    { "get_id", doctype_get_id },
    { "get_system_id", doctype_get_system_id },
    { NULL, NULL }
};

/* comment */
static int comment_get_text(lua_State *L) {
    const lol_html_comment_t **comment = luaL_checkudata(L, 1, PREFIX "comment");
    lol_html_str_t text = lol_html_comment_text_get(*comment); // TODO: free?
    lua_pushlstring(L, text.data, text.len);
    return 1;
}

static int comment_set_text(lua_State *L) {
    size_t text_len;
    lol_html_comment_t **comment = luaL_checkudata(L, 1, PREFIX "comment");
    const char *text = luaL_checklstring(L, 2, &text_len);
    return return_self_or_err(L, lol_html_comment_text_set(*comment, text, text_len));
}

static int comment_before(lua_State *L) {
    size_t content_len;
    lol_html_comment_t **comment = luaL_checkudata(L, 1, PREFIX "comment");
    const char *content = luaL_checklstring(L, 2, &content_len);
    bool is_html = lua_toboolean(L, 3);
    return return_self_or_err(L, lol_html_comment_before(*comment, content, content_len, is_html));
}

static int comment_after(lua_State *L) {
    size_t content_len;
    lol_html_comment_t **comment = luaL_checkudata(L, 1, PREFIX "comment");
    const char *content = luaL_checklstring(L, 2, &content_len);
    bool is_html = lua_toboolean(L, 3);
    return return_self_or_err(L, lol_html_comment_after(*comment, content, content_len, is_html));
}

static int comment_replace(lua_State *L) {
    size_t content_len;
    lol_html_comment_t **comment = luaL_checkudata(L, 1, PREFIX "comment");
    const char *content = luaL_checklstring(L, 2, &content_len);
    bool is_html = lua_toboolean(L, 3);
    return return_self_or_err(L, lol_html_comment_replace(*comment, content, content_len, is_html));
}

static int comment_remove(lua_State *L) {
    lol_html_comment_t **comment = luaL_checkudata(L, 1, PREFIX "comment");
    lol_html_comment_remove(*comment);
    return return_self_or_err(L, 0); /* cannot fail */
}

static int comment_is_removed(lua_State *L) {
    lol_html_comment_t **comment = luaL_checkudata(L, 1, PREFIX "comment");
    lua_pushboolean(L, lol_html_comment_is_removed(*comment));
    return 1;
}

static luaL_Reg comment_methods[] = {
    { "get_text", comment_get_text },
    { "set_text", comment_set_text },
    { "before", comment_before },
    { "after", comment_after },
    { "replace", comment_replace },
    { "remove", comment_remove },
    { "is_removed", comment_is_removed },
    { NULL, NULL }
};


/* text_chunk */
static int text_chunk_get_text(lua_State *L) {
    const lol_html_text_chunk_t **chunk = luaL_checkudata(L, 1, PREFIX "text_chunk");
    lol_html_text_chunk_content_t content = lol_html_text_chunk_content_get(*chunk);
    lua_pushlstring(L, content.data, content.len);
    return 1;
}

static int text_chunk_is_last_in_text_node(lua_State *L) {
    const lol_html_text_chunk_t **chunk = luaL_checkudata(L, 1, PREFIX "text_chunk");
    lua_pushboolean(L, lol_html_text_chunk_is_last_in_text_node(*chunk));
    return 1;
}

static int text_chunk_before(lua_State *L) {
    size_t content_len;
    lol_html_text_chunk_t **chunk = luaL_checkudata(L, 1, PREFIX "text_chunk");
    const char *content = luaL_checklstring(L, 2, &content_len);
    bool is_html = lua_toboolean(L, 3);
    return return_self_or_err(L, lol_html_text_chunk_before(*chunk, content, content_len, is_html));
}

static int text_chunk_after(lua_State *L) {
    size_t content_len;
    lol_html_text_chunk_t **chunk = luaL_checkudata(L, 1, PREFIX "text_chunk");
    const char *content = luaL_checklstring(L, 2, &content_len);
    bool is_html = lua_toboolean(L, 3);
    return return_self_or_err(L, lol_html_text_chunk_after(*chunk, content, content_len, is_html));
}

static int text_chunk_replace(lua_State *L) {
    size_t content_len;
    lol_html_text_chunk_t **chunk = luaL_checkudata(L, 1, PREFIX "text_chunk");
    const char *content = luaL_checklstring(L, 2, &content_len);
    bool is_html = lua_toboolean(L, 3);
    return return_self_or_err(L, lol_html_text_chunk_replace(*chunk, content, content_len, is_html));
}

static int text_chunk_remove(lua_State *L) {
    lol_html_text_chunk_t **chunk = luaL_checkudata(L, 1, PREFIX "text_chunk");
    lol_html_text_chunk_remove(*chunk);
    return return_self_or_err(L, 0); /* cannot fail */
}

static int text_chunk_is_removed(lua_State *L) {
    const lol_html_text_chunk_t **chunk = luaL_checkudata(L, 1, PREFIX "text_chunk");
    lua_pushboolean(L, lol_html_text_chunk_is_removed(*chunk));
    return 1;
}

static luaL_Reg text_chunk_methods[] = {
    { "get_text", text_chunk_get_text },
    { "is_last_in_text_node", text_chunk_is_last_in_text_node },
    { "before", text_chunk_before },
    { "after", text_chunk_after },
    { "replace", text_chunk_replace },
    { "remove", text_chunk_remove },
    { "is_removed", text_chunk_is_removed },
    { NULL, NULL }
};


/* doc_end */
static int doc_end_append(lua_State *L) {
    size_t content_len;
    lol_html_doc_end_t **doc_end = luaL_checkudata(L, 1, PREFIX "doc_end");
    const char *content = luaL_checklstring(L, 2, &content_len);
    bool is_html = lua_toboolean(L, 3);
    return return_self_or_err(L, lol_html_doc_end_append(*doc_end, content, content_len, is_html));
}

static luaL_Reg doc_end_methods[] = {
    { "append", doc_end_append },
    { NULL, NULL }
};

/* rewriter builder */
/* note: as there is a dynamic number of callbacks, the userdata for the builder
 * is just a boxed pointer with a table as uservalue.
 * Each callback will also have a userdata associated with it, and the references
 * will be anchored with the table uservalue mentioned above.
 */

/***
 * Create a new builder.
 * @return the created builder
 */
static int rewriter_builder_new(lua_State *L) {
    int builder_ref;
    lol_html_rewriter_builder_t **ud = lua_newuserdata(L, sizeof(lol_html_rewriter_builder_t *));
    *ud = lol_html_rewriter_builder_new();

    luaL_getmetatable(L, PREFIX "builder");
    lua_setmetatable(L, -2);

    /* register the new builder in the builder registry */
    lua_getfield(L, LUA_REGISTRYINDEX, LOL_REGISTRY);  /* ud, reg */
    lua_pushvalue(L, -2);                                       /* ud, reg, ud */
    builder_ref = luaL_ref(L, -2);                              /* ud, reg */
    lua_pop(L, 1);                                              /* ud */

    /* allocate a table as a uservalue for the builder: this uservalue will be
     * used to keep references to the callback functions and the handler_data_t
     * structures used as userdata for the lol_html API */
    lua_newtable(L);                                            /* ud, uv */
    lua_pushinteger(L, builder_ref);                            /* ud, uv, ref */
    lua_setfield(L, -2, "ref");                                 /* ud, uv */
    lua_setuservalue(L, -2);                                    /* ud */

    return 1;
}

static int rewriter_builder_destroy(lua_State *L) {
    lol_html_rewriter_builder_t **ud = luaL_checkudata(L, 1, PREFIX "builder");
    lol_html_rewriter_builder_free(*ud);
    return 0;
}

static handler_data_t* create_handler(lua_State *L, int builder_idx, int cb_table_idx, const char *field) {
    if (lua_getfield(L, cb_table_idx, field) == LUA_TFUNCTION) {
        handler_data_t *handler = lua_newuserdata(L, sizeof(handler_data_t)); /* func, hander_data */
        handler->L = L;

        lua_getuservalue(L, builder_idx);                                     /* func, hander_data, uv */
        lua_getfield(L, -1, "ref");                                           /* func, hander_data, uv, ref */
        handler->builder_index = lua_tointeger(L, -1);
        lua_pop(L, 1);                                                        /* func, hander_data, uv */

        /* keep a reference to the callback function */
        lua_pushvalue(L, -3);                                                 /* func, hander_data, uv, func */
        handler->callback_index = luaL_ref(L, -2);                            /* func, hander_data, uv */

        /* keep a reference to the handler data (kept until the builder is GC'd */
        lua_pushvalue(L, -2);                                                 /* func, hander_data, uv, hander_data */
        luaL_ref(L, -2);                                                      /* func, hander_data, uv */

        lua_pop(L, 3);                                                        /* func */
        return handler;
    } else {
        lua_pop(L, 1);
        return NULL;
    }
}

static int rewriter_builder_add_document_content_handlers(lua_State *L) {
    void *doctype_ud, *comment_ud, *text_ud, *doc_end_ud;

    lol_html_rewriter_builder_t **ud = luaL_checkudata(L, 1, PREFIX "builder");
    luaL_checktype(L, 2, LUA_TTABLE);
    doctype_ud = create_handler(L, 1, 2, "doctype_handler");
    comment_ud = create_handler(L, 1, 2, "comment_handler");
    text_ud = create_handler(L, 1, 2, "text_handler");
    doc_end_ud = create_handler(L, 1, 2, "doc_end_handler");

    lol_html_rewriter_builder_add_document_content_handlers(
            *ud,
            (doctype_ud == NULL) ? NULL : doctype_handler, doctype_ud,
            (comment_ud == NULL) ? NULL : comment_handler, comment_ud,
            (text_ud == NULL) ? NULL : text_chunk_handler, text_ud,
            (doc_end_ud == NULL) ? NULL : doc_end_handler, doc_end_ud);

    /* return self */
    lua_settop(L, 1);
    return 1;
}

static luaL_Reg rewriter_builder_methods[] = {
    { "add_document_content_handlers", rewriter_builder_add_document_content_handlers },
    { NULL, NULL }
};


/* Rewriter */
typedef struct {
    lol_html_rewriter_t *rewriter;
    lua_State *L;
    int reg_idx;
} lua_rewriter_t;

static void sink_callback(const char *chunk, size_t chunk_len, void *user_data) {
    lua_rewriter_t *rewriter = user_data;
    lua_checkstack(rewriter->L, 4);
    lua_getfield(rewriter->L, LUA_REGISTRYINDEX, LOL_REGISTRY);
    lua_rawgeti(rewriter->L, -1, rewriter->reg_idx);
    lua_getuservalue(rewriter->L, -1);
    lua_pushlstring(rewriter->L, chunk, chunk_len);
    lua_call(rewriter->L, 1, 0);
}

static int rewriter_new(lua_State *L) {
    size_t encoding_len;
    const char *encoding;
    lol_html_memory_settings_t memory_settings;
    lua_rewriter_t *rewriter;
    bool strict;

    luaL_checktype(L, 1, LUA_TTABLE);
    
    /* the error messages for the luaL_opt* functions are not great in this case */
    lua_getfield(L, 1, "builder");
    lol_html_rewriter_builder_t **builder = luaL_checkudata(L, -1, PREFIX "builder");
    lua_pop(L, 1);

    lua_getfield(L, 1, "encoding");
    encoding = luaL_optlstring(L, -1, "utf-8", &encoding_len);
    lua_pop(L, 1);

    lua_getfield(L, 1, "preallocated_parsing_buffer_size");
    memory_settings.preallocated_parsing_buffer_size = luaL_optinteger(L, -1, 1024);
    lua_pop(L, 1);

    lua_getfield(L, 1, "max_allowed_memory_usage");
    memory_settings.max_allowed_memory_usage = luaL_optinteger(L, -1, SIZE_MAX);
    lua_pop(L, 1);

    lua_getfield(L, 1, "strict");
    strict = lua_toboolean(L, -1);
    lua_pop(L, 1);

    // TODO: support a "blackhole" sink by default that avoids all the callback
    // machinery
    if (lua_getfield(L, 1, "sink") != LUA_TFUNCTION) {
        /* not a function, check if it's a callable */
        if (luaL_getmetafield(L, -1, "__call") == LUA_TNIL) {
            luaL_argerror(L, 1, "field \"sink\" cannot be called");
        }
        lua_pop(L, 1);
    }

    rewriter = lua_newuserdata(L, sizeof(lua_rewriter_t)); /* cb, ud */
    rewriter->L = L;
    rewriter->rewriter = lol_html_rewriter_build(
        *builder,
        encoding, encoding_len,
        memory_settings,
        sink_callback, rewriter,
        strict
    );

    if (rewriter->rewriter == NULL) {
        return push_last_error(L);
    }

    // keep a reference of the rewriter in the weak registry to retrieve the
    // reference later on
    lua_getfield(L, LUA_REGISTRYINDEX, LOL_REGISTRY); /* cb, ud, reg */
    lua_pushvalue(L, -2);                             /* cb, ud, reg, ud */
    rewriter->reg_idx = luaL_ref(L, -2);              /* cb, ud, reg */
    lua_pop(L, 1);                                    /* cb, ud */

    // attach the callback function
    lua_pushvalue(L, -2);                             /* cb, ud, cb */
    lua_setuservalue(L, -2);                          /* cb, ud */

    luaL_getmetatable(L, PREFIX "rewriter");          /* cb, ud, mt */
    lua_setmetatable(L, -2);                          /* cb, ud */

    return 1; 
}

static int rewriter_write(lua_State *L) {
    size_t chunk_len;
    lol_html_rewriter_t **rewriter = luaL_checkudata(L, 1, PREFIX "rewriter");
    const char *chunk = luaL_checklstring(L, 2, &chunk_len);
    return return_self_or_err(L, lol_html_rewriter_write(*rewriter, chunk, chunk_len));
}

static int rewriter_end(lua_State *L) {
    lol_html_rewriter_t **rewriter = luaL_checkudata(L, 1, PREFIX "rewriter");
    return return_self_or_err(L, lol_html_rewriter_end(*rewriter));
}

static int rewriter_destroy(lua_State *L) {
    lol_html_rewriter_t **rewriter = luaL_checkudata(L, 1, PREFIX "rewriter");
    lol_html_rewriter_free(*rewriter);
    return 0;
}

static luaL_Reg rewriter_methods[] = {
    { "write", rewriter_write },
    { "close", rewriter_end }, // end is a keyword in Lua
    { NULL, NULL }
};

/* top level module */
static luaL_Reg module_functions[] = {
    { "new_rewriter_builder", rewriter_builder_new },
    { "new_rewriter", rewriter_new },
    { NULL, NULL }
};

int luaopen_lolhtml(lua_State *L) {
    /* create the document builders table */
    if (lua_getfield(L, LUA_REGISTRYINDEX, LOL_REGISTRY) != LUA_TNIL) {
        luaL_error(L, "the library is already loaded");
    }
    lua_pop(L, 1);
    lua_newtable(L);               /* reg */
    lua_newtable(L);               /* reg, mt */
    lua_pushliteral(L, "v");       /* reg, mt, "v" */
    lua_setfield(L, -2, "__mode"); /* reg, mt */
    lua_setmetatable(L, -2);       /* reg */
    lua_setfield(L, LUA_REGISTRYINDEX, LOL_REGISTRY);

    /* register types */
    luaL_newmetatable(L, PREFIX "builder");
    lua_newtable(L);
    luaL_setfuncs(L, rewriter_builder_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, rewriter_builder_destroy);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);

    luaL_newmetatable(L, PREFIX "rewriter");
    lua_newtable(L);
    luaL_setfuncs(L, rewriter_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, rewriter_destroy);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);

    luaL_newmetatable(L, PREFIX "doctype");
    lua_newtable(L);
    luaL_setfuncs(L, doctype_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newmetatable(L, PREFIX "comment");
    lua_newtable(L);
    luaL_setfuncs(L, comment_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newmetatable(L, PREFIX "text_chunk");
    lua_newtable(L);
    luaL_setfuncs(L, text_chunk_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newmetatable(L, PREFIX "doc_end");
    lua_newtable(L);
    luaL_setfuncs(L, doc_end_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    /* module functions */
    lua_newtable(L);
    luaL_setfuncs(L, module_functions, 0);
    lua_pushinteger(L, LOL_HTML_CONTINUE);
    lua_setfield(L, -2, "CONTINUE");
    lua_pushinteger(L, LOL_HTML_STOP);
    lua_setfield(L, -2, "STOP");
    return 1;
}
