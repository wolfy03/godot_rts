# 2D RTS Prototype

This prototype is meant as a starting point for 2D real time strategy games.

## What this prototype offers

### Unit selection
A single unit can be selected with the left mouse button. To select multiple units simply draw a box with the mouse cursor by holding the left mouse button. Hold SHIFT to add units to your current selecting. Left-clicking on the ground clears the unit selection.

### Move command
Right click issues a move command to the selected units. If the click was away from the units they will keep their current formation.
If it was inside the "magic box" (an imagined box around all selected units) then the selected units will converge around that point and clump up.

### Attacking
If an enemy unit enters the "enemy detection radius" of a unit it will automatically move towards the enemy and start attacking them once they are in attack range.

By pressing Q an "attack-move" command can be issued. This is like a move command but enemies along the way will be attacked.
Once all enemies are defeated the units will go to the destination point.

### Hold position
By pressing E units can be stopped while in motion. They will not attack enemies while in this state. Issuing any other command will clear them out of this state again.

## What this prototype lacks

- Networking
- Different unit types
- GUI
- Buildings
- Multiple levels
- A core gameplay loop
