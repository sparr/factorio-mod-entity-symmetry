# Entity Symmetry
A mod for the game Factorio, places rotated/mirrored entities around specified points.

The purpose of this mod is to speed up development of blueprints, particularly 
for rail junctions.

## Usage

Craft a "Symmetry Center" item. Place it in the world as a "Symmetry Center" 
entity. Place some entities nearby and see them duplicated around the center. 
Remove those entities and the duplicates will be removed.

## Configuration

The Symmetry Center entity is a constant combinator. Setting signals within it 
will control its behavior as follows:

- **C**  
Move the center of symmetry to a corner/edge of the tile. 0 = north edge, 1 = 
northeast corner, ..., 6 = west edge, 7 = northwest corner.
- **D**  
Set the max distance from the center to copy entities. Default is 64. Negative 
numbers are circular distance, positive square.
- **R**  
Rail entities are always placed on a 2x2 grid. This setting controls whether 
other entities honor that grid. -1 is never. 1 is always. 0 is not until a 
rail entity is placed then it automatically becomes 1.
- **S**  
Type of Symmetry. 0 = None. Positive = rotation, 4 and 2 are useful, other 
numbers are just pretty. Negative = mirror, -1 = east/west, -2 = north/south, 
-3 = both.
- **item**  
Positive signal will copy only the signaled item(s). Negative signal will 
exclude the signaled item(s) from copying.
