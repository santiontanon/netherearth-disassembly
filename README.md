# netherearth-disassembly
Disassembly of the original 1986 Nether Earth ZX Spectrum game

Disassembled by Santiago Ontañón

Files:
- The main disassembler file is called "netherearth-annotated.asm".
- The file "netherearth-annotated-data.asm" contains the graphic data of the game.
- You can assembler the game back to a binary using the build.sh file included in the repo. You do not need any additional assembler, as I include mdl.jar in the repo, that allows you to assemble the game. MDL ( https://github.com/santiontanon/mdlz80optimizer ) is my own assembler optimizer, which also has assembly/disassembly capabilities. However, if you happen to plan to use the Nether Earth code-base and edit it, I would recommend you using another assembler. MDL is much slower at assembling than other assemblers like Glass or sjasmplus, since it does many other things, and hence it might not be ideal for heavy development.
- I also include an html rendered version of the source code ( netherearth-annotated.html ), that might be easier to see than the raw .asm file. The html file also has .png files to illustrate al the graphic data (scroll all the way to the bottom once you open it).

All the symbol names and comments in this file are my own interpretation of the original source code, they could be wrong. So, take them all with a grain of salt! And if you see any errors, please report!
