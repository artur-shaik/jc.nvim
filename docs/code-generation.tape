# vhs script for the code-generation demo GIF.  Record: vhs docs/code-generation.tape
# Open a class that has a few fields; the picker windows let you choose fields
# and the generation style.

Output "docs/code-generation.gif"

Require nvim

Set Shell "zsh"
Set FontSize 18
Set Width 1200
Set Height 720
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

Hide
Type "cd /path/to/java-project && nvim src/main/java/com/example/Person.java" Enter
Sleep 26s
Show

# constructor: a picker lists the fields; press 2 to generate over all of them
Sleep 1s
Type ":JCgenerateConstructor" Sleep 700ms Enter
Sleep 2500ms
Type "2"
Sleep 4s

# toString: another picker offers the style; press 1
Type ":JCgenerateToString" Sleep 700ms Enter
Sleep 2500ms
Type "1"
Sleep 4s
