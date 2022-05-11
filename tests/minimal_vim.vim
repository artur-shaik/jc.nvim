set rtp+=.
set rtp+=vendor/plenary.nvim
set rtp+=~/.config/nvim/bundle/nvim-lspconfig/

runtime plugin/plenary.vim

lua require('plenary.busted')
