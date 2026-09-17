# IMPACT Newsletter Studio

A public, client-side newsletter design demo. Open `index.html` for the editor or `sample.html` to read the entire sample edition.

All sample people, customer scenarios, quotes, and metrics are fictional. The four contributor JPEGs are original illustrations, not real staff photographs. This is not an official Microsoft communication.

## Editing and exporting

Select a section, edit its plain text, and add, remove, or reorder stories. The index follows automatically. The masthead supports hosted banner URLs, and the contributors section supports editable names, roles, and portrait URLs. Drafts are saved only in the current browser. There is no backend, account, or shared draft store.

Switch between 640 px desktop and 375 px mobile previews. Copy HTML or download a standalone email file. Use an HTML-capable sending platform; pasting source into Outlook's regular compose window will show code.

The exported email uses inline styles and presentation tables. The masthead gradient, story cards, and feedback button include conditional VML for classic Outlook. Shadows, portrait rounding, and image cropping are progressive enhancements. Pre-crop banner and portrait images for reliable Outlook dimensions. Clients may block remote images or internal jump links; alt text and live-text content remain available. Browser previews do not simulate Outlook's Word rendering engine.

## Sample and assets

`sample.html` is generated from fictional defaults, not a saved browser draft:

```sh
node build-sample.cjs
```

`make-portraits.ps1` recreates the four 320 x 320 JPEG illustrations using Windows System.Drawing. The stock collaboration banner is hosted by Unsplash, and the official Microsoft logo is hosted by Microsoft. The contributor illustrations are served from this demo's `assets` directory. Image hosts receive ordinary image requests; authored draft text is not uploaded.

No installation is needed to use either page. Keep the app files together when copying them. Default contributor URLs point to this GitHub Pages deployment; update them if hosting elsewhere.
