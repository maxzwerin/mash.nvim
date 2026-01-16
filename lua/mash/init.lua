local M = {}


local defaults = {
    labels = "asdfghjklqwertyuiopzxcvbnm",
    mode = "fuzzy", -- "fuzzy" | "exact"
    prompt = {
        enabled = true,
        prefix = "> ",
    },
}

M.config = vim.deepcopy(defaults)

function M.setup(opts)
    opts = opts or {}
    M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
    M._setup_highlights()
end


M.state = {
    active = false,
    search_text = "",
    matches = {},
    original_bufnr = nil,
    original_winid = nil,
    prompt_bufnr = nil,
    prompt_winid = nil,
}

M.ns = vim.api.nvim_create_namespace("mash")


function M._setup_highlights()
    if vim.g.vscode then
        local hls = {
            MashBackdrop = { fg = "#545c7e" },
            MashMatch    = { bg = "#3e68d7", fg = "#c8d3f5" },
            MashLabel    = { bg = "#ff007c", bold = true, fg = "#c8d3f5" },
        }
        for k, v in pairs(hls) do
            v.default = true
            vim.api.nvim_set_hl(0, k, v)
        end
    else
        local links = {
            MashBackdrop = "Comment",
            MashMatch    = "Search",
            MashLabel    = "Substitute",
        }
        for k, v in pairs(links) do
            vim.api.nvim_set_hl(0, k, { link = v, default = true })
        end
    end
end


local function clear()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
end

local function visible_lines()
    local info = vim.fn.getwininfo(M.state.original_winid)[1]
    if not info then return end
    return info.topline - 1, info.botline
end


local function fuzzy_match(text, pattern)
    text = text:lower()
    pattern = pattern:lower()

    local ti, first, last, score = 1, nil, nil, 0

    for pi = 1, #pattern do
        local c = pattern:sub(pi, pi)
        local found = false

        while ti <= #text do
            if text:sub(ti, ti) == c then
                found = true
                first = first or ti
                last = ti
                score = score + 1
                ti = ti + 1
                break
            end
            ti = ti + 1
        end

        if not found then return nil end
    end

    score = score * 10 - (last - first)
    return { start = first - 1, finish = last, score = score }
end


function M._search()
    clear()

    if M.state.search_text == "" then return end

    local bufnr = M.state.original_bufnr
    local start_line, end_line = visible_lines()
    if not start_line then return end

    local matches = {}

    for l = start_line, end_line - 1 do
        local text = vim.api.nvim_buf_get_lines(bufnr, l, l + 1, false)[1]
        if text then
            if M.config.mode == "fuzzy" then
                local r = fuzzy_match(text, M.state.search_text)
                if r then
                    table.insert(matches, {
                        line = l,
                        col = r.start,
                        end_col = r.finish,
                        score = r.score,
                    })
                end
            else
                local s, e = text:find(M.state.search_text, 1, true)
                if s then
                    table.insert(matches, {
                        line = l,
                        col = s - 1,
                        end_col = e,
                        score = 1000 - s,
                    })
                end
            end
        end
    end

    table.sort(matches, function(a, b)
        return a.score > b.score
    end)

    M.state.matches = {}
    local labels = M.config.labels

    for i, m in ipairs(matches) do
        local label = labels:sub(i, i)
        if label == "" then break end

        M.state.matches[label] = m

        vim.api.nvim_buf_set_extmark(bufnr, M.ns, m.line, m.col, {
            end_col = m.end_col,
            hl_group = "MashMatch",
        })

        vim.api.nvim_buf_set_extmark(bufnr, M.ns, m.line, m.end_col, {
            virt_text = { { label, "MashLabel" } },
            virt_text_pos = "overlay",
        })
    end
end


function M._jump(label)
    local m = M.state.matches[label]
    if not m then return false end

    vim.api.nvim_set_current_win(M.state.original_winid)
    vim.api.nvim_win_set_cursor(M.state.original_winid, { m.line + 1, m.col })

    M._cleanup()
    return true
end

function M._cleanup()
    vim.on_key(nil, M.ns)
    clear()

    if M.state.prompt_winid and vim.api.nvim_win_is_valid(M.state.prompt_winid) then
        vim.api.nvim_win_close(M.state.prompt_winid, true)
    end

    if M.state.prompt_bufnr and vim.api.nvim_buf_is_valid(M.state.prompt_bufnr) then
        vim.api.nvim_buf_delete(M.state.prompt_bufnr, { force = true })
    end

    M.state = {
        active = false,
        search_text = "",
        matches = {},
    }
end


function M._prompt_mode()
    local bufnr = vim.api.nvim_create_buf(false, true)
    M.state.prompt_bufnr = bufnr

    vim.bo[bufnr].buftype = "prompt"
    vim.fn.prompt_setprompt(bufnr, M.config.prompt.prefix)

    local winid = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        width = vim.o.columns,
        height = 1,
        row = vim.o.lines - vim.o.cmdheight - 1,
        col = 0,
        style = "minimal",
    })

    M.state.prompt_winid = winid
    vim.cmd("startinsert")

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = bufnr,
        callback = function()
            local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
            M.state.search_text =
                line:gsub("^" .. vim.pesc(M.config.prompt.prefix), "")
            M._search()
        end,
    })
end

function M._direct_mode()
    vim.on_key(function(key)
        if key == "\027" then
            M._cleanup()
            return
        end

        local c = vim.fn.keytrans(key)
        if #c == 1 then
            if M._jump(c) then return end
            M.state.search_text = M.state.search_text .. c
            M._search()
        end
    end, M.ns)
end


function M.jump()
    if M.state.active then return end
    M.state.active = true

    M.state.original_bufnr = vim.api.nvim_get_current_buf()
    M.state.original_winid = vim.api.nvim_get_current_win()

    if M.config.prompt.enabled then
        M._prompt_mode()
    else
        M._direct_mode()
    end
end

return M
