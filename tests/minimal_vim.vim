set rtp+=.
set rtp+=vendor/plenary.nvim
set rtp+=vendor/nvim-lspconfig/
set rtp+=vendor/nvim-lsp-installer/

runtime plugin/plenary.vim

lua require('plenary.busted')
