# The web interface

`webui/` is static — no build step, no dependencies. It offers lyrics with
section tags, the caption, length, seed and output format, then plays the result
and offers it for download. The length field can be derived from the lyrics.

**The endpoint is an operator's concern, not the user's.** There is deliberately
no input field for it. It is set in `webui/config.js` and nowhere else:

```js
window.SOUTHBYTE_MUSIC = { endpunkt: "" };   // empty = derive from the page address
```

Three cases:

| Value | Meaning |
|---|---|
| `""` | derive from the page address: same host, port 8011. For serving `webui/` straight off the disk, without a proxy |
| `"/"` | same origin as the page, so through a reverse proxy. This is what compose and the Kubernetes chart both use |
| a URL | wherever the music server actually is |

In the container the file is written at startup from `SOUTHBYTE_ENDPUNKT`, which
defaults to `/`. That default arrived after `v0.1.0`, so image tag `0.1.0` still
ignores the variable — one more reason the pinned tag in `compose.yaml` is
`0.1.3`.

The resolved endpoint is shown in the page footer, so a misconfiguration stays
visible without being editable.

The interface is in German; the code and configuration are documented in German
too, which is the house style across this family of repositories.
