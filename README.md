# Reflex Control

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3601100812)

Reflex Control adds the ability to power on and off the reflex sight upgrade for the Pistol and SMG, making it less obtrusive when you're not aiming down sights.

This uses [Alyxlib](https://github.com/FrostSource/alyxlib).

It's implemented by first detecting any installed pistol mods, then replacing the reflex sights model with one that has an active/inactive bodygroup. The SMG model already has this feature, but for all the pistol mods this is a modified version. Alternatively, some guns just disable-draw the sights, if the sights is a physical item which would have to be entirely removed to disable it.
