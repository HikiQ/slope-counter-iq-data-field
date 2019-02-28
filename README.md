# Description
Data field that calculates the number of downhill runs for lift assisted fun and stores it in the fit file.
Shows a negative number when going uphill.

## Downhill is counted when:
1. Descent speed is large enough
2. Enough time has passed since the last downhill ended
3. There is an uphill between the slopes based on ascent speed or on large enough slow altitude gain

## Settings:

- Vertical speed threshold [m/s] :
    - Values below this are considered stationary
    - Reasonable starting values 0.3 - 0.5

- Minimum time between slopes [s] :
    - A new slope is not counted if enough time has not passed since the end of the last slope
    - Reasonable starting value 30s

- SLOW ascent as uphill [m] :
    - Uphill is defined by the speed threshold but a large elevation gain can also be counted as uphill.
    - Value depends on the environment, perhaps 100m
    - If this value is too small, the number of slopes increases.
    - If this value is really large, only the ascent and descent speeds define hills (normal operation).

- Up-down transition delay :
    - Larger values make the transitions between uphill, flat and downhill slower
    - Reasonable starting values around 3-5
    - State transitions are modeled as a Hidden Markov model.
    - The value is defined as follows: probability of state transition = 0.001, Filter = -log10(0.001) = 3

# Notes
- Still testing

# Model
- Uses a Hidden Markov model with 3 states: upphill, flat, downhill
    - user selectable state transition probability
- Observations: up, level, down
    - based on the selected speed threshold
- Forward algorithm is used to solve the most probable state at the given time
- A new slope can start when:
    - an uphill is found between slopes
    - enough time has passed since the last slope ended
    
