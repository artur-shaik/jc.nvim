# vhs script for the class-creation demo GIF.
#   https://github.com/charmbracelet/vhs
#
# Record with:  vhs docs/class-creation.tape
# Run it from a java project that starts jdtls (nvim-java) on open, and adjust
# the `cd` path below. The Sleep calls give jdtls time to index — tune them to
# your machine.

Output docs/class-creation.gif

Require nvim

Set Shell "zsh"
Set FontSize 18
Set Width 1280
Set Height 760
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

# open a source file so jdtls attaches (path: your demo project)
Hide
Type "cd ~/demo-java && nvim src/main/java/com/example/App.java" Enter
Sleep 6s
Show

# generate a class with fields, a constructor and toString in one line
Type ":JCgenerateClass" Sleep 800ms Enter
Sleep 1200ms
Type "/com.example.model.User(String name, int age):constructor:toString" Sleep 1500ms
Enter

# jdtls scaffolds the file, then the chain adds the constructor and toString
Sleep 7s
