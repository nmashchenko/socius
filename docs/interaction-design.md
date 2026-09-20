# Pixel octopus — interaction study 04

## Direction

A small pixel octopus, with gentle hunger and mood changes. Care restores its willingness to help. Design comes before backend integrations and custom skills.

## Current interaction

Click Mochi: a tiny lift and floating pixel heart, finished within 650 ms. Its action menu opens immediately, without waiting for the animation. The desktop has no persistent top toolbar or bottom instruction pill.

One menu contains equally sized, labeled Feed / Play / Sleep buttons and the tool picker. Hungry or grumpy pets still allow care, while tool actions remain disabled. The native popover owns the outer corners; its content fills the background instead of drawing a second, conflicting rounded card.

Speech appears only during activities, in a bubble with a tail toward the pet. The desktop pet remains draggable.

## Octopus care identity

Food and game labels are defined under the octopus species. Future animals should have their own food, game, sprites, and behavior rather than inheriting a generic ball and snack.

- Food: a small pixel shrimp, brought to the mouth and eaten in bites.
- Game: shell hunt. Three shells sit near the tentacles. Pick the pearl: +45 spirits. Empty shells fade, and Mochi invites another try. No penalty for guessing wrong. Repeated selection after success cannot award extra spirits.
- Rest: arms curl beneath the mantle, the body settles and slowly breathes, and tiny bubbles drift up. No blanket. Sleep pauses need decay.

The shared care loop uses fullness / spirits, each capped at 100. Hunger decays over roughly 12 waking hours and spirits over 18. Tools stop cooperating at 20 or below. Feeding restores 45 fullness, winning a game restores 45 spirits, and petting restores 8 spirits.

## Motion

Affection is short feedback, not a long celebration. Care sequences are interruptible: new interactions cancel old resets and animation tasks. macOS Reduce Motion remove travel, bounce, and rotation while keeping state changes visible. Pocket opening uses native presentation; the playground uses a 200 ms anchored fade/scale.

## To settle together

Offline decay, preferred sleep schedule, timing of hunger, whether already-open tools remain usable when mood falls, and later animal designs. There is no death, permanent harm, or lost user data. This prototype resets on restart and has no active tool integrations.


## Edge retreat and idle life

Inactivity is local to Mochi, not a system-wide keyboard/mouse monitor. After 10 seconds without interaction, the native pet window moves horizontally toward its nearest visible screen edge. Artwork clips at that edge (including between adjacent displays), leaving a small sliver. Its original height and home position are retained.

A seven-second speaking visit happens every 90 seconds while awake. The resting pose keeps the face visible, leaning around the edge with two gripping tentacles. Hovering holds the target steady; clicking restores the home position and opens the menu. Menus, food, affection, and active shell games prevent retreat. Sleeping pets remain tucked rather than periodically waking up. A display change restores the pet to reachable screen bounds.

The pet peeks with a reminder after 30 seconds at the edge. macOS Reduce Motion suppresses travel animations. Right-click Keep Mochi here disables the default retreat behavior. The desktop hosting view accepts first mouse events, and the pet permits activation clicks.

Visible awake idle motion is an alternating one-pixel tentacle ripple; it stops during care activities and while hidden. Sleep uses a slow breathing pose. Reduced Motion stops the ripple and breathing, and makes edge movement immediate. Moving windows use a cancellable 500 ms travel curve; tuck/peek artwork uses a 500 ms spring with 0.2 bounce. Retargeting starts from the current window position.
