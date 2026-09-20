const menuButton = document.querySelector('.menu-toggle');
const nav = document.querySelector('.site-nav');

menuButton?.addEventListener('click', () => {
  const open = nav.classList.toggle('open');
  menuButton.setAttribute('aria-expanded', String(open));
});

document.querySelectorAll('.site-nav a').forEach((link) => {
  link.addEventListener('click', () => {
    nav.classList.remove('open');
    menuButton?.setAttribute('aria-expanded', 'false');
  });
});

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });

document.querySelectorAll('.reveal').forEach((element) => observer.observe(element));
document.getElementById('year').textContent = new Intl.DateTimeFormat('fa-IR-u-ca-persian-nu-latn', {
  year: 'numeric',
}).format(new Date());

fetch('https://api.github.com/repos/mortenaho/morixterm/releases/latest', {
  headers: { Accept: 'application/vnd.github+json' },
})
  .then((response) => {
    if (!response.ok) throw new Error('Release lookup failed');
    return response.json();
  })
  .then((release) => {
    if (!/^v[1-9][0-9]*$/.test(release.tag_name) || !Array.isArray(release.assets)) return;
    const version = release.tag_name.slice(1);
    document.querySelectorAll('[data-release-version]').forEach((element) => {
      element.textContent = version;
    });
    document.querySelectorAll('[data-release-headline]').forEach((element) => {
      element.textContent = `Version ${version} is out`;
    });
    const names = {
      installer: new RegExp(`^MoriXterm-${version}-Windows-x64-Setup\\.exe$`),
      portable: new RegExp(`^MoriXterm-${version}-Windows-x64-Portable\\.zip$`),
      appimage: new RegExp(`^MoriXterm-v${version}-Linux-x86_64\\.AppImage$`),
      deb: new RegExp(`^morixterm_${version}(?:\\.0\\.0)?_amd64\\.deb$`, 'i'),
    };
    document.querySelectorAll('[data-release-asset]').forEach((link) => {
      const asset = release.assets.find((item) => names[link.dataset.releaseAsset].test(item.name));
      if (asset && /^https:\/\/github\.com\/mortenaho\/morixterm\/releases\/download\//.test(asset.browser_download_url)) {
        link.href = asset.browser_download_url;
      }
    });
  })
  .catch(() => {
    // The fallback links still lead to the latest release when GitHub's API is unavailable.
  });
