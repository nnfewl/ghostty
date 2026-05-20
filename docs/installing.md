# Installing Ghostty-Twemoji (stable)

## Homebrew (macOS)

The macOS builds are `.app` bundles, so they install via a Homebrew **Cask**.

### Setup

1. Create a tap repo `nnfewl/homebrew-ghostty-twemoji` on GitHub.
2. Add a cask file at `Casks/ghostty-twemoji.rb`:

```ruby
cask "ghostty-twemoji" do
  version :latest
  sha256 :no_check

  url "https://github.com/nnfewl/ghostty/releases/latest/download/ghostty-macos-arm64-colr.zip"
  name "Ghostty (Twemoji)"
  desc "GPU-accelerated terminal emulator with Twemoji"
  homepage "https://github.com/nnfewl/ghostty"

  depends_on macos: ">= :ventura"

  app "Ghostty.app"

  zap trash: [
    "~/Library/Application Support/com.mitchellh.ghostty",
    "~/Library/Preferences/com.mitchellh.ghostty.plist",
  ]
end
```

### Install

```bash
brew tap nnfewl/ghostty-twemoji
brew install --cask ghostty-twemoji
```

### Emoji variant

The cask above uses the **COLRv0** variant (vector emoji, ~2 MB, sharp at all
sizes). To use the **sbix** variant (bitmap, ~23 MB, maximum compatibility)
instead, change the URL to:

```
https://github.com/nnfewl/ghostty/releases/latest/download/ghostty-macos-arm64-sbix.zip
```

You could also publish both as separate casks (`ghostty-twemoji-colr` and
`ghostty-twemoji-sbix`).

---

## PKGBUILD (Arch Linux)

```bash
# Maintainer: nnfewl <hoaventunwigwe@gmail.com>
pkgname=ghostty-twemoji-bin
pkgver=1.3.1
pkgrel=1
pkgdesc="GPU-accelerated terminal emulator with Twemoji (prebuilt binary)"
arch=('x86_64')
url="https://github.com/nnfewl/ghostty"
license=('MIT')
provides=('ghostty')
conflicts=('ghostty' 'ghostty-git')
source=("ghostty-linux-x86_64-${pkgver}.tar.gz::https://github.com/nnfewl/ghostty/releases/latest/download/ghostty-linux-x86_64.tar.gz")
sha256sums=('SKIP')

package() {
    install -Dm755 ghostty "${pkgdir}/usr/bin/ghostty"
}
```

### Install

```bash
makepkg -si
```

### Updating

Bump `pkgver` and `pkgrel`, then run `makepkg -si` again. The source URL uses
`releases/latest`, so it always fetches the newest stable build.

---

## Caveat

The Linux tarball currently ships **only the binary** -- no `.desktop` file,
terminfo entries, shell completions, or man page. A future pipeline update
could include these from the build output (`out/share/`) for a more complete
package.
