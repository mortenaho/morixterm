(() => {
  const REPO = "mortenaho/morixtrem";
  const API = `https://api.github.com/repos/${REPO}/releases?per_page=10`;

  const btnWindows = document.getElementById("btn-windows");
  const btnLinux = document.getElementById("btn-linux");
  const metaWindows = document.getElementById("meta-windows");
  const metaLinux = document.getElementById("meta-linux");
  const versionLine = document.getElementById("version-line");

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "";
    const units = ["B", "KB", "MB", "GB"];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    const digits = value >= 10 || unit === 0 ? 0 : 1;
    return `${value.toFixed(digits)} ${units[unit]}`;
  }

  function isWindowsAsset(name) {
    const n = name.toLowerCase();
    return n.includes("windows") || n.endsWith(".zip") || n.endsWith(".msi") || n.endsWith(".exe");
  }

  function isLinuxAsset(name) {
    const n = name.toLowerCase();
    return n.endsWith(".deb") || n.endsWith(".AppImage") || n.includes("linux");
  }

  function pickAsset(assets, predicate) {
    return assets.find((a) => predicate(a.name));
  }

  function enableButton(button, metaEl, asset, fallbackMeta) {
    if (!asset) {
      metaEl.textContent = "موجود نیست";
      return;
    }
    button.href = asset.browser_download_url;
    button.removeAttribute("aria-disabled");
    button.setAttribute("download", "");
    const size = formatBytes(asset.size);
    metaEl.textContent = size ? `${fallbackMeta} · ${size}` : fallbackMeta;
  }

  function setError(message) {
    versionLine.textContent = message;
    metaWindows.textContent = "خطا";
    metaLinux.textContent = "خطا";
  }

  async function loadLatestRelease() {
    const response = await fetch(API, {
      headers: { Accept: "application/vnd.github+json" },
    });

    if (!response.ok) {
      throw new Error(`GitHub API ${response.status}`);
    }

    const releases = await response.json();
    if (!Array.isArray(releases) || releases.length === 0) {
      throw new Error("no releases");
    }

    // Releases API returns newest first and includes prereleases.
    const latest = releases.find((r) => Array.isArray(r.assets) && r.assets.length > 0) || releases[0];
    const assets = latest.assets || [];
    const windows = pickAsset(assets, isWindowsAsset);
    const linux = pickAsset(assets, isLinuxAsset);

    enableButton(btnWindows, metaWindows, windows, ".zip");
    enableButton(btnLinux, metaLinux, linux, ".deb · amd64");

    const label = latest.name || latest.tag_name || "latest";
    const published = latest.published_at
      ? new Date(latest.published_at).toLocaleDateString("fa-IR")
      : "";

    versionLine.innerHTML = published
      ? `آخرین نسخه: <strong dir="ltr">${label}</strong> · ${published}`
      : `آخرین نسخه: <strong dir="ltr">${label}</strong>`;
  }

  loadLatestRelease().catch(() => {
    // Fallback: GitHub "latest" redirect works for non-prerelease tags;
    // for this repo we still point users to the releases page.
    btnWindows.href = `https://github.com/${REPO}/releases`;
    btnLinux.href = `https://github.com/${REPO}/releases`;
    btnWindows.removeAttribute("aria-disabled");
    btnLinux.removeAttribute("aria-disabled");
    metaWindows.textContent = "از صفحهٔ Releases";
    metaLinux.textContent = "از صفحهٔ Releases";
    setError("دریافت خودکار نسخه ممکن نشد. از صفحهٔ Releases دانلود کنید.");
  });
})();
