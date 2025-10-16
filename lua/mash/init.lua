local M = {}
local ns = vim.api.nvim_create_namespace("mash")

local function setup_highlights()
    local set_hl = vim.api.nvim_set_hl

    set_hl(0, "dim", {
        fg = "#606079",
        bg = "NONE",
        italic = true,
        ctermfg = 242,
        ctermbg = "NONE",
    })

    set_hl(0, "targetHighlight", {
        bg = "#404065",
        fg = "NONE",
        ctermbg = 13,
        ctermfg = "NONE",
    })

    -- Target text
    set_hl(0, "targetText", {
        fg = "#c3c3d5",
        bg = "NONE",
        ctermfg = 13,
        ctermbg = "NONE",
    })

    set_hl(0, "labelHighlight", {
        bg = "#333738",
        fg = "NONE",
        ctermbg = 13,
        ctermfg = "NONE",
    })

    set_hl(0, "labelText", {
        fg = "#9bb4bc",
        bg = "NONE",
        italic = false,
        ctermfg = 13,
        ctermbg = "NONE",
    })
end

setup_highlights()

local dim_group = "dim"
local highlight_group = "targetHighlight"
local text_group = "targetText"
local label_group = "labelText"

local labels = "asdfghjklqwertyuiopzxcvbnmASDFGHJKLQWERTYUIOPZXCVBNM"
local targets = {} -- go to targets
local ducks = {}   -- avoid all ducks

local function dim_visible_window()
    local buf = vim.api.nvim_get_current_buf()
    local start_line = vim.fn.line("w0") - 1
    local end_line = vim.fn.line("w$")
    for lnum = start_line, end_line - 1 do
        vim.api.nvim_buf_add_highlight(buf, ns, dim_group, lnum, 0, -1)
    end
end

local function clear()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    targets = {}
end

local function get_valid_labels()
    local valid = {}

    for i = 1, #labels do
        local label = labels:sub(i, i)
        local skip = false

        -- skip if this label matches any duck
        for _, d in ipairs(ducks) do
            if label == d then
                skip = true
                break
            end
        end

        if not skip then
            table.insert(valid, label)
        end
    end

    local label_str = table.concat(valid, "")
    return label_str
end

local function highlight_matches(query)
    clear()
    dim_visible_window()
    vim.api.nvim_command("redraw")

    targets = {}
    ducks = {} -- an array of chars
    if query == "" then return end

    local buf = vim.api.nvim_get_current_buf()
    local start_line = vim.fn.line("w0") - 1
    local end_line = vim.fn.line("w$")
    local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)

    local matches = {}

    -- get all ducks
    for idx, line in ipairs(lines) do
        local lnum = start_line + idx - 1
        local start = 1
        while true do
            local s, e = string.find(line, query, start, true)
            if not s then break end

            table.insert(matches, { lnum = lnum, s = s, e = e })

            local duck_col = e + 1
            local duck_char = line:sub(duck_col, duck_col)
            if duck_char ~= "" then
                table.insert(ducks, duck_char)
            end

            start = e + 1
        end
    end

    -- get valid labels
    local valid_labels = get_valid_labels()

    -- FUCK
    local label_index = 1
    for idx, line in ipairs(lines) do
        local lnum = start_line + idx - 1
        local start = 1

        while true do
            local s, e = string.find(line, query, start, true)
            if not s then break end
            if label_index > #valid_labels then break end -- stop if no more labels

            local label = valid_labels:sub(label_index, label_index)

            -- highlight match
            vim.api.nvim_buf_add_highlight(buf, ns, highlight_group, lnum, s - 1, e)
            vim.api.nvim_buf_add_highlight(buf, ns, text_group, lnum, s - 1, e)

            -- overlay label at end of match
            vim.api.nvim_buf_set_extmark(buf, ns, lnum, e, {
                virt_text = { { label, label_group } },
                virt_text_pos = "overlay",
                hl_mode = "combine",
            })

            table.insert(matches, {
                label = label,
                lnum = lnum,
                col = s - 1,
            })

            label_index = label_index + 1
            start = e + 1
        end
    end

    targets = matches
end

-- Termcodes
function M.t(str)
    return vim.api.nvim_replace_termcodes(str, true, true, true)
end

M.CR = M.t("<cr>")
M.ESC = M.t("<esc>")
M.BS = M.t("<bs>")

-- Jump to a given label
local function jump_to_label()
    local ok, input = pcall(vim.fn.getcharstr)
    if not ok or not input then return end
    for _, t in ipairs(targets) do
        if t.label == input then
            -- visually mark active label
            vim.api.nvim_buf_set_extmark(0, ns, t.lnum, t.col, {
                virt_text = { { t.label, label_group } },
                virt_text_pos = "overlay",
                hl_mode = "combine",
            })

            -- jump
            vim.api.nvim_win_set_cursor(0, { t.lnum + 1, t.col })
            vim.cmd("normal! zz") -- center view
            return
        end
    end
end

-- Main entrypoint
function M.jump()
    clear()
    dim_visible_window()
    vim.api.nvim_command("redraw")

    local query = ""

    while true do
        local ok, input = pcall(vim.fn.getcharstr)
        if not ok or not input then break end

        if input == M.ESC then
            vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
            targets = {}
            return
        elseif input == M.CR then
            break
        elseif input == M.BS then
            if #query > 0 then
                query = query:sub(1, -2)
            clear()
            dim_visible_window()
            vim.api.nvim_command("redraw")
            end
        elseif input and input ~= "" then
            for _, target in ipairs(targets) do
                if input == target.label then
                    vim.api.nvim_win_set_cursor(0, { target.lnum + 1, target.col })
                    clear()
                    dim_visible_window()
                    vim.api.nvim_command("redraw")
                    return
                end
            end
            query = query .. input
        end

        if #query > 0 then
            highlight_matches(query)
        end

        vim.api.nvim_command("redraw")
        vim.api.nvim_echo({ { "mash: " .. (#query > 0 and query or ""), "Normal" } }, false, {})
    end

    if #targets > 0 then
        jump_to_label()
    end

    clear()
    vim.api.nvim_command("redraw")
end

return M
