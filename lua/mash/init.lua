local M = {}

M.ns = vim.api.nvim_create_namespace("mash")

M.labels = "asdfghjklqwertyuiopzxcvbnmASDFGHJKLQWERTYUIOPZXCVBNM"

function M.t(str)
    return vim.api.nvim_replace_termcodes(str, true, true, true)
end

M.CR = M.t("<cr>")
M.ESC = M.t("<esc>")
M.BS = M.t("<bs>")
M.EXIT = M.t("<C-\\><C-n>")
M.LUA_CALLBACK = "\x80\253g"
M.CMD = "\x80\253h"

function M.exit()
    vim.api.nvim_feedkeys(M.EXIT, "nx", false)
    vim.api.nvim_feedkeys(M.ESC, "n", false)
end

function M.clear(ns)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
end

function M.setup()
    if vim.g.vscode then
        local hls = {
            MashBackdrop = { fg = "#545c7e" },
            MashCurrent = { bg = "#ff966c", fg = "#1b1d2b" },
            MashLabel = { bg = "#ff007c", bold = true, fg = "#c8d3f5" },
            MashMatch = { bg = "#3e68d7", fg = "#c8d3f5" },
            MashCursor = { reverse = true },
        }
        for hl_group, hl in pairs(hls) do
            hl.default = true
            vim.api.nvim_set_hl(0, hl_group, hl)
        end
    else
        local links = {
            MashBackdrop = "Comment",
            MashMatch = "Search",
            MashCurrent = "IncSearch",
            MashLabel = "Substitute",
            MashPrompt = "MsgArea",
            MashPromptIcon = "Special",
            MashCursor = "Cursor",
        }
        for hl_group, link in pairs(links) do
            vim.api.nvim_set_hl(0, hl_group, { link = link, default = true })
        end
    end
end

M.state = {
    active = false,
    search_text = "",
    prompt_bufnr = nil,
    prompt_winid = nil,
    original_bufnr = nil,
    original_winid = nil,
    matches = {},
}

function M.create_prompt()
    M.state.original_bufnr = vim.api.nvim_get_current_buf()
    M.state.original_winid = vim.api.nvim_get_current_win()

    local bufnr = vim.api.nvim_create_buf(false, true)
    M.state.prompt_bufnr = bufnr

    vim.bo[bufnr].buftype = 'prompt'
    vim.bo[bufnr].bufhidden = 'wipe'
    vim.bo[bufnr].swapfile = false

    local width = vim.o.columns
    local height = 1
    local row = vim.o.lines - vim.o.cmdheight - 1
    local col = 0

    local opts = {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'none',
        noautocmd = true,
    }

    local winid = vim.api.nvim_open_win(bufnr, true, opts)
    M.state.prompt_winid = winid

    vim.wo[winid].winhl = 'Normal:Normal'

    vim.o.showmode = false

    vim.fn.prompt_setprompt(bufnr, '> ')

    vim.cmd('startinsert')

    return bufnr, winid
end

function M.get_visible_lines()
    if not M.state.original_winid or not vim.api.nvim_win_is_valid(M.state.original_winid) then
        return nil, nil
    end

    local win_info = vim.fn.getwininfo(M.state.original_winid)[1]
    if not win_info then
        return nil, nil
    end

    return win_info.topline - 1, win_info.botline
end

function M.apply_backdrop()
    if not M.state.original_bufnr or not vim.api.nvim_buf_is_valid(M.state.original_bufnr) then
        return
    end

    local start_line, end_line = M.get_visible_lines()
    if not start_line then
        return
    end

    vim.api.nvim_buf_clear_namespace(M.state.original_bufnr, M.ns, 0, -1)

    for line = start_line, end_line - 1 do
        local line_text = vim.api.nvim_buf_get_lines(M.state.original_bufnr, line, line + 1, false)[1]
        if line_text and #line_text > 0 then
            vim.api.nvim_buf_set_extmark(M.state.original_bufnr, M.ns, line, 0, {
                end_line = line,
                end_col = 0,
                hl_eol = true,
                line_hl_group = "MashBackdrop",
            })
        end
    end
end

function M.search_and_highlight()
    if not M.state.original_bufnr or not vim.api.nvim_buf_is_valid(M.state.original_bufnr) then
        return
    end

    vim.api.nvim_buf_clear_namespace(M.state.original_bufnr, M.ns, 0, -1)

    if M.state.search_text == "" then
        M.apply_backdrop()
        return
    end

    local start_line, end_line = M.get_visible_lines()
    if not start_line then
        return
    end

    M.apply_backdrop()

    local search_pattern = vim.fn.escape(M.state.search_text, "\\")
    local matches = {}

    for line = start_line, end_line - 1 do
        local line_text = vim.api.nvim_buf_get_lines(M.state.original_bufnr, line, line + 1, false)[1]
        if line_text then
            local col = 0
            while true do
                local start_col, end_col = string.find(line_text, search_pattern, col + 1, true)
                if not start_col then
                    break
                end

                table.insert(matches, {
                    line = line,
                    start_col = start_col - 1,
                    end_col = end_col,
                    line_text = line_text
                })

                col = start_col
            end
        end
    end

    M.state.matches = {}
    local label_idx = 1

    local ducks = {}
    for _, match in ipairs(matches) do
        local next_char_pos = match.end_col + 1
        local next_char = match.line_text:sub(next_char_pos, next_char_pos)
        if next_char ~= "" then
            table.insert(ducks, next_char:lower())
        end
    end

    for _, match in ipairs(matches) do
        vim.api.nvim_buf_set_extmark(
            M.state.original_bufnr, M.ns, match.line, match.start_col, {
                end_col = match.end_col,
                hl_group = "MashMatch",
            })

        local label = nil
        while label_idx <= #M.labels do
            local candidate_label = M.labels:sub(label_idx, label_idx)
            label_idx = label_idx + 1

            local is_duck = false
            for _, duck in ipairs(ducks) do
                if duck == candidate_label:lower() then
                    is_duck = true
                    break
                end
            end

            if not is_duck then
                label = candidate_label
                break
            end
        end

        if label and label_idx <= 53 then
            match.label = label

            M.state.matches[label] = match

            vim.api.nvim_buf_set_extmark(M.state.original_bufnr, M.ns, match.line, match.end_col, {
                virt_text = { { label, "MashLabel" } },
                virt_text_pos = "overlay",
                priority = 200,
            })
        end
    end

    if #matches == 1 then
        vim.schedule(function()
            M.jump_to_label(matches[1].label)
        end)
    end
end

function M.on_input(text)
    M.state.search_text = text
    M.search_and_highlight()
end

function M.jump_to_label(label)
    local match = M.state.matches[label]
    if not match then
        return false
    end

    if M.state.original_winid and vim.api.nvim_win_is_valid(M.state.original_winid) then
        vim.api.nvim_set_current_win(M.state.original_winid)
    end

    vim.api.nvim_win_set_cursor(M.state.original_winid, { match.line + 1, match.start_col })

    M.cleanup()

    vim.cmd('stopinsert')
    vim.schedule(function() vim.cmd('redraw') end)

    return true
end

function M.cleanup()
    vim.o.showmode = true

    M.clear(M.ns)

    if M.state.prompt_winid and vim.api.nvim_win_is_valid(M.state.prompt_winid) then
        vim.api.nvim_win_close(M.state.prompt_winid, true)
    end

    if M.state.prompt_bufnr and vim.api.nvim_buf_is_valid(M.state.prompt_bufnr) then
        vim.api.nvim_buf_delete(M.state.prompt_bufnr, { force = true })
    end

    if M.state.original_bufnr and vim.api.nvim_buf_is_valid(M.state.original_bufnr) then
        local windows = vim.api.nvim_list_wins()
        for _, win in ipairs(windows) do
            if vim.api.nvim_win_is_valid(win) then
                local success = pcall(vim.api.nvim_win_set_buf, win, M.state.original_bufnr)
                if success then
                    vim.api.nvim_set_current_win(win)
                    break
                end
            end
        end
    end

    M.state = {
        active = false,
        search_text = "",
        prompt_bufnr = nil,
        prompt_winid = nil,
        original_bufnr = nil,
        original_winid = nil,
        matches = {},
    }
end

function M.map(str, opts)
    vim.keymap.set('i', str, function()
        M.cleanup()
    end, opts)
end

function M.setup_keymaps(bufnr)
    local opts = { buffer = bufnr, noremap = true, silent = true }

    M.map('<Esc>', opts)
    M.map('<C-c>', opts)
    M.map('<CR>', opts)

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = bufnr,
        callback = function()
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            if #lines > 0 then
                local text = lines[1]
                text = text:gsub("^> ", "")

                if #text > #M.state.search_text then
                    local last_char = text:sub(-1)
                    if M.jump_to_label(last_char) then
                        return
                    end
                end

                M.state.search_text = text
                M.search_and_highlight()
            end
        end
    })
end

function M.jump()
    if M.state.active then
        return
    end

    M.state.active = true
    M.state.search_text = ""

    local bufnr, winid = M.create_prompt()

    M.apply_backdrop()

    M.setup_keymaps(bufnr)

    vim.fn.prompt_setcallback(bufnr, function(text)
        M.on_input(text)
        M.cleanup()
    end)

    vim.fn.prompt_setinterrupt(bufnr, function()
        M.cleanup()
    end)
end

return M
