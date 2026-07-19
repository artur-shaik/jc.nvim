# vhs script for the test-runner demo GIF.  Record: vhs docs/test-runner.tape
# Open a test class in a java project with the neotest adapter wired in.

Output docs/test-runner.gif

Require nvim

Set Shell "zsh"
Set FontSize 18
Set Width 1280
Set Height 760
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

Hide
Type "cd ~/demo-java && nvim src/test/java/com/example/UserTest.java" Enter
Sleep 6s
Show

# run the test class; neotest paints the gutter and opens the summary
Type ":JCtestFile" Sleep 800ms Enter
Sleep 8s
