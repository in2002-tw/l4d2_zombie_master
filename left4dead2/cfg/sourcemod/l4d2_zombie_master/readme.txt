This folder is for GAMEMODE related settings.

The .cfg file that will be loaded is set with the server cvar zm_gamemode.

The default value is:
zm_gamemode "zm_default"
which will run the target cfg every time:
1) The plugin starts (once).
2) Whenever zm_enable is changed to 1.
3) Whenever zm_gamemode is changed.