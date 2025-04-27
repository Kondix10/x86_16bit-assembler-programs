# x86_16bit-assembler-programs
A collection of programs I wrote in 16-bit assembly for x86

# Disclaimer
To run these programs use DOSBox.

The executables were compiles using MASM 5.00 and MS Overlay Linker 3.60

# Description
- SNAKE2 - Ordinary snake game with some QoL features such as displaying current number of points. The game works by overwriting the clock interrupt vector by the game code. 
  - Controls are WASD, X to exit
  - Debug: Q - add 1 point
- IMVIEW - Image viewer with 7-bit color depth. I was testing possible interrupts with it. This program writes to the console, loads input text from it and then loads data byte by byte from a given file. All this with interrupts.
- IMVIEW16 - Video viewer. It is based on IMVIEW and can play videos with 4-bit color depth. 
