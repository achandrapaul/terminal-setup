local parsers = require("config.treesitter_parsers")

local skipped_filetypes = { help = true, vimdoc = true }

return {
	{
		"windwp/nvim-ts-autotag",
		-- Top level, not a dependency: lazy loads dependencies with their parent, so an
		-- `ft` on a dependency of nvim-treesitter would never actually defer anything.
		ft = {"html", "xml", "javascriptreact", "typescriptreact", "svelte", "vue", "markdown"},
		dependencies = {"nvim-treesitter/nvim-treesitter"},
		opts = {},
	},
	{
	"nvim-treesitter/nvim-treesitter",
	-- main needs tree-sitter CLI >= 0.26.1 on PATH for :TSInstall; master breaks on nvim 0.12
	branch = "main",
	lazy = false,
	build = ":TSUpdate",
	dependencies = {
		{
			"nvim-treesitter/nvim-treesitter-context",
			enabled = true,
			opts = { mode = "cursor", max_lines = 3 },
			event = "VeryLazy",
			keys = {
				{
					"<leader>ut",
					function()
						require("treesitter-context").toggle()
					end,
					desc = "Toggle Treesitter Context",
				},
			},
		},
	},
	config = function()
		local installed = {}
		for _, parser_name in ipairs(require("nvim-treesitter").get_installed()) do
			installed[parser_name] = true
		end
		local missing_parsers = vim.tbl_filter(function(parser_name)
			return not installed[parser_name]
		end, parsers)
		if #missing_parsers > 0 then
			require("nvim-treesitter").install(missing_parsers)
		end
		vim.treesitter.language.register("json", "jsonc")

		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("treesitter_start", { clear = true }),
			callback = function(args)
				if skipped_filetypes[args.match] then
					return
				end
				if pcall(vim.treesitter.start, args.buf) then
					vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end,
		})

		vim.keymap.set("n", "<C-y>", "van", { remap = true, desc = "Increment selection" })
		vim.keymap.set("x", "<C-y>", "an", { remap = true, desc = "Increment selection" })
		vim.keymap.set("x", "<bs>", "in", { remap = true, desc = "Decrement selection" })
	end,
	},
}
