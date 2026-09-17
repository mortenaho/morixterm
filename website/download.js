(() => {
  const repository = 'mortenaho/morixterm';
  const api = `https://api.github.com/repos/${repository}/releases/latest`;
  const releasePage = `https://github.com/${repository}/releases`;
  const versionLine = document.querySelector('#version-line span');

  const targets = [
    { button: 'download-windows', meta: 'meta-windows', label: '.exe', match: name => name.endsWith('.exe') },
    { button: 'download-appimage', meta: 'meta-appimage', label: '.AppImage', match: name => name.endsWith('.appimage') },
    { button: 'download-deb', meta: 'meta-deb', label: '.deb · amd64', match: name => name.endsWith('.deb') },
  ];

  const formatBytes = bytes => {
    if (!Number.isFinite(bytes) || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit += 1; }
    return `${value.toFixed(value >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
  };

  const enable = (target, asset) => {
    const button = document.getElementById(target.button);
    const meta = document.getElementById(target.meta);
    if (!asset) { meta.textContent = 'Unavailable'; return; }
    button.href = asset.browser_download_url;
    button.classList.remove('disabled');
    button.removeAttribute('aria-disabled');
    const size = formatBytes(asset.size);
    meta.textContent = size ? `${target.label} · ${size}` : target.label;
  };

  fetch(api, { headers: { Accept: 'application/vnd.github+json' } })
    .then(response => {
      if (!response.ok) throw new Error(`GitHub API ${response.status}`);
      return response.json();
    })
    .then(release => {
      const assets = Array.isArray(release.assets) ? release.assets : [];
      for (const target of targets) {
        enable(target, assets.find(asset => target.match(asset.name.toLowerCase())));
      }
      const date = release.published_at ? new Date(release.published_at).toLocaleDateString() : '';
      versionLine.textContent = `Latest release: ${release.tag_name}${date ? ` · ${date}` : ''}`;
    })
    .catch(() => {
      versionLine.textContent = 'Open GitHub Releases to download the latest build.';
      for (const target of targets) {
        const button = document.getElementById(target.button);
        button.href = releasePage;
        button.classList.remove('disabled');
        button.removeAttribute('aria-disabled');
        document.getElementById(target.meta).textContent = 'View releases';
      }
    });
})();
