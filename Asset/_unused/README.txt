Assets with no reference anywhere in the project (no res:// path, no uid://,
no filename string) as of the cleanup pass.

Nothing is deleted. The .gdignore beside this file makes Godot skip this whole
tree, so these files no longer import, no longer appear in the FileSystem dock
and no longer bloat the project - but they are still on disk and in git.

To bring one back: move it (and its .import sibling) to its original path shown
by the folder structure here, then let the editor reimport.

Deliberately NOT moved: Asset/Main Sound (SFX slots are filled by dragging files
in the Inspector, so unused-today does not mean unwanted) and Asset/UI Elements.
