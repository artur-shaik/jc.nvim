set rtp+=.
set rtp+=vendor/plenary.nvim
set rtp+=~/.config/nvim/bundle/nvim-lspconfig/
set rtp+=~/.config/nvim/bundle/nvim-lsp-installer/

runtime plugin/plenary.vim

lua require('plenary.busted')
