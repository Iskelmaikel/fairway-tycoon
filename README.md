# Fairway Tycoon (web)

> **The game now lives in [`godot/`](godot/).** This web version (v0.41.0) is frozen: it stays playable and is the reference the Godot port was made from, but new features go into the Godot version.

Build and run your own golf club, from a patch of grass by the road to a five-star championship venue.

Play it in the browser: everything is in `index.html`. Saves are kept in your browser (local storage), per device.

## Hosting on GitHub Pages

1. Create a repository (for example `fairway-tycoon`) and upload `index.html`, `.nojekyll` and this README to the root.
2. In the repository, open **Settings → Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**, branch `main`, folder `/ (root)`, and save.
4. After a minute the game is live at `https://<your-username>.github.io/fairway-tycoon/`.

To update the game, replace `index.html` and commit.
