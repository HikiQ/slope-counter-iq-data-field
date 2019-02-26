# slope-counter-iq-data-field
Counts the number of downhill slopes during snowboarding, dh biking, etc.

# Notes
- Still testing
- Summary field might not work (cannot see the value in Monkeygraph)

# Description
- Uses a Hidden Markov model with 3 states: upphill, flat, downhill
    - user selectable state transition probability
- Observations: up, level, down
    - based on the selected speed threshold
- Forward algorithm is used to solve the most probable state at the given time
- A new slope can start when:
    - an uphill is found between slopes
    - enough time has passed since the last slope ended
    
