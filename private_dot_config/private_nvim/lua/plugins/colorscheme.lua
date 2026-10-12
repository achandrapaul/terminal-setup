return {
    { "rose-pine/neovim" },
    {
        "AnudeepChPaul/dracula.nvim",
        lazy = false,
        config = function()
            vim.cmd("colorscheme dracula-soft")

            local highlight_overrides = {
                Error = { fg = "red", bg = "#fafafa" },
                Visual = { fg = "#F8F8F2", bg = "#415854" },
                Normal = { bg = "none" },
                NormalFloat = { bg = "none" },
                NormalNC = { bg = "none" },
                PortalBorder = { bg = "none" },
                GitSignsAdd = { bg = "none" },
                GitSignsDelete = { bg = "none" },
                GitSignsChange = { bg = "none" },
                EndOfBuffer = { bg = "none" },
                LineNr = { bg = "none", fg = "#ababab" },
                CursorLineNr = { bg = "none", fg = "#F8F8F2", bold = true },
                CursorLine = { bg = "#415854" },
                ColorColumn = { bg = "none" },
                NvimTreeNormal = { bg = "none" },
                VertSplit = { bg = "none" },
                NvimTreeWinSeparator = { bg = "none" },
                NvimTreeCursorLine = { bg = "none", bold = true, underline = true },
                SignColumn = { bg = "none" },
                TelescopeNormal = { bg = "none" },
                TelescopeBorder = { bg = "none" },
                TelescopeSelectionCaret = { bg = "none" },
                TelescopeMatching = { bg = "none" },
                TelescopePromptNormal = { bg = "none" },
                TelescopePromptTitle = { bg = "none" },
                TelescopePromptPrefix = { bg = "none" },
                TelescopePromptBorder = { bg = "none" },
                TelescopePreviewTitle = { bg = "none" },
                TelescopePreviewBorder = { bg = "none" },
                TelescopeResultsTitle = { bg = "none" },
                TelescopeResultsBorder = { bg = "none" },
                NeoTree = { bg = "none" },
                NeoTreeNormal = { bg = "none" },
                NeoTreeNormalNC = { bg = "none" },
                NeoTreeTitleBar = { bg = "#F8F8F2", fg = "#415854" },
                NeoTreeFloatTitle = { bg = "#F8F8F2", fg = "#415854" },
                NeoTreeIndentMarker = { fg = "#F8F8F2", bg = "none" },
                NeoTreeDotfile = { fg = "#F8F8F2", bg = "none" },
                NeoTreeGitIgnored = { fg = "#F8F8F2", bg = "none" },
                NeoTreeHiddenByName = { fg = "#F8F8F2", bg = "none" },
                NeoTreeWindowsHidden = { fg = "#F8F8F2", bg = "none" },
            }
            for group_name, group_opts in pairs(highlight_overrides) do
                vim.api.nvim_set_hl(0, group_name, group_opts)
            end
        end,
    },
}
