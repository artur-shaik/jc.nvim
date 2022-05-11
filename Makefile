.PHONY: test prepare

prepare:
	@if [ ! -d "./vendor/plenary.nvim" ]; then git clone https://github.com/nvim-lua/plenary.nvim vendor/plenary.nvim; fi
	@if [ ! -d "./vendor/nvim-lspconfig" ]; then git clone https://github.com/neovim/nvim-lspconfig vendor/nvim-lspconfig; fi
	@if [ ! -d "./vendor/nvim-lsp-installer" ]; then git clone https://github.com/williamboman/nvim-lsp-installer vendor/nvim-lsp-installer; fi

test: prepare
	@nvim \
		--headless \
		--noplugin \
		-u tests/minimal_vim.vim \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_vim.vim' }"
